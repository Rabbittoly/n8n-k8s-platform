#!/bin/bash
# n8n Platform Backup Script
# This script creates a comprehensive backup of the n8n platform
set -e

# Configuration
NAMESPACE="n8n"
POSTGRES_POD="postgresql-0"
DATABASE_NAME="n8n"
DATABASE_USER="n8n"

# Determine backup directory
if [ -z "$1" ]; then
  BACKUP_DIR="./backups/$(date +%Y%m%d-%H%M%S)"
else
  BACKUP_DIR="$1"
fi

# Print header
echo "=========================================="
echo "n8n Kubernetes Platform Backup"
echo "=========================================="
echo "Backup directory: $BACKUP_DIR"
echo ""

# Check for required tools
echo "Checking dependencies..."
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed. Aborting." >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "helm is required but not installed. Aborting." >&2; exit 1; }
echo "All dependencies are installed."
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR/configs"
mkdir -p "$BACKUP_DIR/resources"
mkdir -p "$BACKUP_DIR/databases"

# Backup Helm releases
echo "Backing up Helm releases..."
helm get values n8n -n $NAMESPACE -o yaml > "$BACKUP_DIR/configs/n8n-values.yaml"
helm get values postgresql -n $NAMESPACE -o yaml > "$BACKUP_DIR/configs/postgresql-values.yaml"
helm get values redis -n $NAMESPACE -o yaml > "$BACKUP_DIR/configs/redis-values.yaml"
echo "Helm releases backed up."
echo ""

# Backup Kubernetes resources
echo "Backing up Kubernetes resources..."
kubectl get all -n $NAMESPACE -o yaml > "$BACKUP_DIR/resources/all-resources.yaml"
kubectl get secrets -n $NAMESPACE -o yaml > "$BACKUP_DIR/resources/secrets.yaml"
kubectl get configmaps -n $NAMESPACE -o yaml > "$BACKUP_DIR/resources/configmaps.yaml"
kubectl get pvc -n $NAMESPACE -o yaml > "$BACKUP_DIR/resources/persistent-volume-claims.yaml"
kubectl get ingress -n $NAMESPACE -o yaml > "$BACKUP_DIR/resources/ingress.yaml"
kubectl get ingressroute.traefik.containo.us -n $NAMESPACE -o yaml > "$BACKUP_DIR/resources/ingressroute.yaml" 2>/dev/null || true
echo "Kubernetes resources backed up."
echo ""

# Backup PostgreSQL database
echo "Backing up PostgreSQL database..."
if kubectl get pod $POSTGRES_POD -n $NAMESPACE >/dev/null 2>&1; then
  echo "Creating PostgreSQL dump..."
  
  # Check if pg_dump is available in the pod
  if kubectl exec -n $NAMESPACE $POSTGRES_POD -- which pg_dump >/dev/null 2>&1; then
    # Create database dump
    kubectl exec -n $NAMESPACE $POSTGRES_POD -- pg_dump -U $DATABASE_USER $DATABASE_NAME > "$BACKUP_DIR/databases/n8n-database.sql"
    
    # Create compressed version
    gzip -c "$BACKUP_DIR/databases/n8n-database.sql" > "$BACKUP_DIR/databases/n8n-database.sql.gz"
    echo "PostgreSQL database dumped and compressed."
  else
    echo "pg_dump not available in the PostgreSQL pod. Using alternative method..."
    
    # Create a temporary pod with PostgreSQL client tools
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pg-dump-tool
  namespace: $NAMESPACE
spec:
  containers:
  - name: pg-dump
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
    echo "Waiting for temporary backup pod to be ready..."
    kubectl wait --for=condition=ready pod/pg-dump-tool -n $NAMESPACE --timeout=60s
    
    # Create database dump
    kubectl exec -n $NAMESPACE pg-dump-tool -- pg_dump -h postgresql -U $DATABASE_USER $DATABASE_NAME > "$BACKUP_DIR/databases/n8n-database.sql"
    
    # Create compressed version
    gzip -c "$BACKUP_DIR/databases/n8n-database.sql" > "$BACKUP_DIR/databases/n8n-database.sql.gz"
    
    # Delete the temporary pod
    kubectl delete pod pg-dump-tool -n $NAMESPACE
    echo "PostgreSQL database dumped and compressed using temporary pod."
  fi
  
  echo "PostgreSQL database backup completed."
else
  echo "Warning: PostgreSQL pod $POSTGRES_POD not found. Database backup skipped."
fi
echo ""

# Backup n8n data (if any PVC is used)
echo "Checking for n8n persistent data..."
N8N_PVC=$(kubectl get pvc -n $NAMESPACE -l app.kubernetes.io/name=n8n -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$N8N_PVC" ]; then
  echo "Found n8n PVC: $N8N_PVC"
  
  # Create temporary pod to mount the PVC
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: n8n-backup-pod
  namespace: $NAMESPACE
spec:
  containers:
  - name: backup
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
  echo "Waiting for backup pod to be ready..."
  kubectl wait --for=condition=ready pod/n8n-backup-pod -n $NAMESPACE --timeout=60s
  
  # Create tar archive of n8n data
  echo "Creating archive of n8n data..."
  kubectl exec -n $NAMESPACE n8n-backup-pod -- tar -czf /tmp/n8n-data.tar.gz -C /data .
  
  # Copy tar from pod to local
  echo "Copying data archive from pod..."
  kubectl cp $NAMESPACE/n8n-backup-pod:/tmp/n8n-data.tar.gz "$BACKUP_DIR/databases/n8n-data.tar.gz"
  
  # Delete the temporary pod
  kubectl delete pod n8n-backup-pod -n $NAMESPACE
  echo "n8n data backup completed."
else
  echo "No n8n PVC found. Data backup skipped."
fi
echo ""

# Create metadata file
echo "Creating backup metadata..."
cat <<EOF > "$BACKUP_DIR/backup-info.txt"
n8n Kubernetes Platform Backup
==============================
Date: $(date)
Namespace: $NAMESPACE
Kubernetes Context: $(kubectl config current-context)
Backup Type: Full (Configs, Resources, Database, Data)

Contents:
- configs/: Helm values for n8n, PostgreSQL, and Redis
- resources/: Kubernetes resource definitions
- databases/: PostgreSQL database dump and n8n data

Restore Command:
./scripts/restore.sh $BACKUP_DIR
EOF
echo "Backup metadata created."
echo ""

# Create a single archive of all backups
echo "Creating final backup archive..."
ARCHIVE_NAME="n8n-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf "$BACKUP_DIR/../$ARCHIVE_NAME" -C "$BACKUP_DIR/.." "$(basename "$BACKUP_DIR")"
echo "Backup archive created: $BACKUP_DIR/../$ARCHIVE_NAME"
echo ""

# Print backup summary
echo "=========================================="
echo "Backup completed! 🎉"
echo "=========================================="
echo ""
echo "Backup location: $BACKUP_DIR"
echo "Backup archive: $BACKUP_DIR/../$ARCHIVE_NAME"
echo ""
echo "The backup includes:"
echo "  - Helm release configurations"
echo "  - Kubernetes resources (deployments, services, etc.)"
echo "  - PostgreSQL database dump"
[ -n "$N8N_PVC" ] && echo "  - n8n data archive"
echo ""
echo "To restore from this backup, run:"
echo "  ./scripts/restore.sh $BACKUP_DIR"
echo "or"
echo "  ./scripts/restore.sh $BACKUP_DIR/../$ARCHIVE_NAME"
echo ""
echo "Done! 🚀"