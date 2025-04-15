#!/bin/bash
# n8n Platform Restore Script
# This script restores a backup of the n8n platform
set -e

# Configuration
NAMESPACE="n8n"
POSTGRES_POD="postgresql-0"
DATABASE_NAME="n8n"
DATABASE_USER="n8n"

# Check for backup path argument
if [ -z "$1" ]; then
  echo "Error: Backup path is required."
  echo "Usage: $0 /path/to/backup"
  exit 1
fi

# Determine backup directory
BACKUP_PATH="$1"

# Check if it's a tar.gz archive or a directory
if [[ "$BACKUP_PATH" == *.tar.gz ]]; then
  # Extract the archive to a temporary directory
  TEMP_DIR=$(mktemp -d)
  echo "Extracting backup archive to temporary directory..."
  tar -xzf "$BACKUP_PATH" -C "$TEMP_DIR"
  
  # Find the backup directory inside the temp dir
  BACKUP_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d | grep -v "^$TEMP_DIR$" | head -1)
  
  if [ -z "$BACKUP_DIR" ]; then
    echo "Error: Could not find backup directory in archive."
    rm -rf "$TEMP_DIR"
    exit 1
  fi
  
  echo "Using extracted backup at $BACKUP_DIR"
else
  # Use the provided directory
  BACKUP_DIR="$BACKUP_PATH"
  
  # Verify it's a valid backup directory
  if [ ! -d "$BACKUP_DIR/configs" ] || [ ! -d "$BACKUP_DIR/resources" ] || [ ! -d "$BACKUP_DIR/databases" ]; then
    echo "Error: Invalid backup directory structure. Missing required subdirectories."
    exit 1
  fi
  
  echo "Using backup directory at $BACKUP_DIR"
fi

# Print header
echo "=========================================="
echo "n8n Kubernetes Platform Restore"
echo "=========================================="
echo "Backup directory: $BACKUP_DIR"
echo ""

# Check for required tools
echo "Checking dependencies..."
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed. Aborting." >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "helm is required but not installed. Aborting." >&2; exit 1; }
echo "All dependencies are installed."
echo ""

# Check if namespace exists
if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
  echo "Creating namespace $NAMESPACE..."
  kubectl create namespace $NAMESPACE
fi

# Prompt for confirmation
echo "WARNING: This will restore n8n to the state in this backup."
echo "All current data will be replaced with the backup data."
echo ""
read -p "Are you sure you want to proceed? (y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Restore aborted."
  exit 1
fi
echo ""

# Create pre-restore backup
echo "Creating pre-restore backup..."
PRE_RESTORE_BACKUP_DIR="./backups/pre-restore-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$PRE_RESTORE_BACKUP_DIR"
./scripts/backup.sh "$PRE_RESTORE_BACKUP_DIR" || true
echo "Pre-restore backup created at $PRE_RESTORE_BACKUP_DIR"
echo ""

# Restore secrets
echo "Restoring secrets..."
if [ -f "$BACKUP_DIR/resources/secrets.yaml" ]; then
  # Delete any existing secrets to avoid conflicts
  kubectl get secrets -n $NAMESPACE -o name | xargs -r kubectl delete -n $NAMESPACE
  
  # Apply secrets from backup
  kubectl apply -f "$BACKUP_DIR/resources/secrets.yaml"
  echo "Secrets restored."
else
  echo "No secrets backup found. Skipping."
fi
echo ""

# Restore config maps
echo "Restoring config maps..."
if [ -f "$BACKUP_DIR/resources/configmaps.yaml" ]; then
  # Delete any existing config maps to avoid conflicts
  kubectl get configmaps -n $NAMESPACE -o name | grep -v "kube-root-ca.crt" | xargs -r kubectl delete -n $NAMESPACE
  
  # Apply config maps from backup
  kubectl apply -f "$BACKUP_DIR/resources/configmaps.yaml"
  echo "Config maps restored."
else
  echo "No config maps backup found. Skipping."
fi
echo ""

# Restore persistent volume claims
echo "Restoring persistent volume claims..."
if [ -f "$BACKUP_DIR/resources/persistent-volume-claims.yaml" ]; then
  # Apply PVCs from backup (don't delete existing ones to preserve data)
  kubectl apply -f "$BACKUP_DIR/resources/persistent-volume-claims.yaml"
  echo "Persistent volume claims restored."
else
  echo "No PVC backup found. Skipping."
fi
echo ""

# Restore PostgreSQL
echo "Restoring PostgreSQL..."
if [ -f "$BACKUP_DIR/configs/postgresql-values.yaml" ]; then
  helm upgrade --install postgresql bitnami/postgresql \
    --namespace $NAMESPACE \
    -f "$BACKUP_DIR/configs/postgresql-values.yaml"
  echo "PostgreSQL Helm release restored."
  
  # Wait for PostgreSQL to be ready
  echo "Waiting for PostgreSQL to be ready..."
  kubectl wait --for=condition=ready pod/$POSTGRES_POD --namespace $NAMESPACE --timeout=300s
  
  # Restore database
  if [ -f "$BACKUP_DIR/databases/n8n-database.sql" ]; then
    echo "Restoring PostgreSQL database..."
    
    # Check if we can directly use the pod
    if kubectl exec -n $NAMESPACE $POSTGRES_POD -- which psql >/dev/null 2>&1; then
      cat "$BACKUP_DIR/databases/n8n-database.sql" | kubectl exec -i -n $NAMESPACE $POSTGRES_POD -- psql -U $DATABASE_USER $DATABASE_NAME
      echo "PostgreSQL database restored."
    else
      echo "psql not available in the PostgreSQL pod. Using alternative method..."
      
      # Create a temporary pod with PostgreSQL client tools
      cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pg-restore-tool
  namespace: $NAMESPACE
spec:
  containers:
  - name: pg-restore
    image: bitnami/postgresql:latest
    command:
    - /bin/sh
    - -c
    - sleep 3600
    env:
    - name: PGPASSWORD
      valueFrom:
        secretKeyRef:
          name: postgresql
          key: password
  restartPolicy: Never
EOF
      
      # Wait for the pod to be ready
      echo "Waiting for temporary restore pod to be ready..."
      kubectl wait --for=condition=ready pod/pg-restore-tool -n $NAMESPACE --timeout=60s
      
      # Restore database
      cat "$BACKUP_DIR/databases/n8n-database.sql" | kubectl exec -i -n $NAMESPACE pg-restore-tool -- psql -h postgresql -U $DATABASE_USER $DATABASE_NAME
      
      # Delete the temporary pod
      kubectl delete pod pg-restore-tool -n $NAMESPACE
      echo "PostgreSQL database restored using temporary pod."
    fi
  elif [ -f "$BACKUP_DIR/databases/n8n-database.sql.gz" ]; then
    echo "Restoring compressed PostgreSQL database..."
    
    # Create a temporary file
    TEMP_SQL=$(mktemp)
    gunzip -c "$BACKUP_DIR/databases/n8n-database.sql.gz" > "$TEMP_SQL"
    
    # Restore using the temporary file
    cat "$TEMP_SQL" | kubectl exec -i -n $NAMESPACE $POSTGRES_POD -- psql -U $DATABASE_USER $DATABASE_NAME
    
    # Clean up
    rm "$TEMP_SQL"
    echo "Compressed PostgreSQL database restored."
  else
    echo "No database backup found. Skipping database restore."
  fi
else
  echo "No PostgreSQL config backup found. Skipping PostgreSQL restore."
fi
echo ""

# Restore Redis
echo "Restoring Redis..."
if [ -f "$BACKUP_DIR/configs/redis-values.yaml" ]; then
  helm upgrade --install redis bitnami/redis \
    --namespace $NAMESPACE \
    -f "$BACKUP_DIR/configs/redis-values.yaml"
  echo "Redis Helm release restored."
  
  # Wait for Redis to be ready
  echo "Waiting for Redis to be ready..."
  kubectl wait --for=condition=ready pod/redis-master-0 --namespace $NAMESPACE --timeout=300s
else
  echo "No Redis config backup found. Skipping Redis restore."
fi
echo ""

# Restore n8n data (if any)
echo "Checking for n8n data backup..."
if [ -f "$BACKUP_DIR/databases/n8n-data.tar.gz" ]; then
  echo "Found n8n data backup."
  
  # Find n8n PVC
  N8N_PVC=$(kubectl get pvc -n $NAMESPACE -l app.kubernetes.io/name=n8n -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  
  if [ -n "$N8N_PVC" ]; then
    echo "Found n8n PVC: $N8N_PVC"
    
    # Create temporary pod to mount the PVC
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: n8n-restore-pod
  namespace: $NAMESPACE
spec:
  containers:
  - name: restore
    image: busybox
    command:
    - /bin/sh
    - -c
    - sleep 3600
    volumeMounts:
    - name: n8n-data
      mountPath: /data
  volumes:
  - name: n8n-data
    persistentVolumeClaim:
      claimName: $N8N_PVC
  restartPolicy: Never
EOF
    
    # Wait for the pod to be ready
    echo "Waiting for restore pod to be ready..."
    kubectl wait --for=condition=ready pod/n8n-restore-pod -n $NAMESPACE --timeout=60s
    
    # Clear existing data
    kubectl exec -n $NAMESPACE n8n-restore-pod -- rm -rf /data/*
    
    # Copy tar to pod
    echo "Copying data archive to pod..."
    kubectl cp "$BACKUP_DIR/databases/n8n-data.tar.gz" $NAMESPACE/n8n-restore-pod:/tmp/n8n-data.tar.gz
    
    # Extract tar in pod
    echo "Extracting data archive in pod..."
    kubectl exec -n $NAMESPACE n8n-restore-pod -- tar -xzf /tmp/n8n-data.tar.gz -C /data
    
    # Delete the temporary pod
    kubectl delete pod n8n-restore-pod -n $NAMESPACE
    echo "n8n data restored."
  else
    echo "No n8n PVC found. Data restore skipped."
  fi
else
  echo "No n8n data backup found. Data restore skipped."
fi
echo ""

# Restore n8n
echo "Restoring n8n..."
if [ -f "$BACKUP_DIR/configs/n8n-values.yaml" ]; then
  helm upgrade --install n8n n8n/n8n \
    --namespace $NAMESPACE \
    -f "$BACKUP_DIR/configs/n8n-values.yaml"
  echo "n8n Helm release restored."
else
  echo "No n8n config backup found. Skipping n8n restore."
fi
echo ""

# Restore ingress
echo "Restoring ingress resources..."
if [ -f "$BACKUP_DIR/resources/ingress.yaml" ]; then
  kubectl apply -f "$BACKUP_DIR/resources/ingress.yaml"
  echo "Ingress resources restored."
fi

if [ -f "$BACKUP_DIR/resources/ingressroute.yaml" ]; then
  kubectl apply -f "$BACKUP_DIR/resources/ingressroute.yaml"
  echo "IngressRoute resources restored."
else
  # Apply default IngressRoute
  kubectl apply -f k8s/ingress/traefik.yaml -n $NAMESPACE
  echo "Default IngressRoute applied."
fi
echo ""

# Wait for n8n to be ready
echo "Waiting for n8n to be ready..."
kubectl wait --for=condition=available deployment/n8n --namespace $NAMESPACE --timeout=300s
echo "n8n is ready."
echo ""

# Clean up temporary directory if used
if [[ "$BACKUP_PATH" == *.tar.gz ]]; then
  echo "Cleaning up temporary files..."
  rm -rf "$TEMP_DIR"
  echo "Cleanup complete."
fi
echo ""

# Print restore summary
echo "=========================================="
echo "Restore completed! 🎉"
echo "=========================================="
echo ""
echo "The n8n platform has been restored from backup: $BACKUP_PATH"
echo ""
echo "The following components were restored:"
[ -f "$BACKUP_DIR/configs/postgresql-values.yaml" ] && echo "  - PostgreSQL"
[ -f "$BACKUP_DIR/configs/redis-values.yaml" ] && echo "  - Redis"
[ -f "$BACKUP_DIR/configs/n8n-values.yaml" ] && echo "  - n8n"
[ -f "$BACKUP_DIR/resources/secrets.yaml" ] && echo "  - Secrets"
[ -f "$BACKUP_DIR/resources/configmaps.yaml" ] && echo "  - ConfigMaps"
[ -f "$BACKUP_DIR/resources/persistent-volume-claims.yaml" ] && echo "  - PersistentVolumeClaims"
[ -f "$BACKUP_DIR/databases/n8n-database.sql" -o -f "$BACKUP_DIR/databases/n8n-database.sql.gz" ] && echo "  - PostgreSQL database"
[ -f "$BACKUP_DIR/databases/n8n-data.tar.gz" ] && echo "  - n8n data"
echo ""
echo "A pre-restore backup was created at: $PRE_RESTORE_BACKUP_DIR"
echo "If needed, you can restore to the pre-restore state with:"
echo "  ./scripts/restore.sh $PRE_RESTORE_BACKUP_DIR"
echo ""
echo "n8n should now be available at the configured URL."
echo ""
echo "Done! 🚀"