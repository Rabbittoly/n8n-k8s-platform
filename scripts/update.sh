#!/bin/bash
# n8n Platform Update Script
# This script updates all components of the n8n platform to their latest versions
set -e

# Configuration
NAMESPACE="n8n"
POSTGRES_RELEASE="postgresql"
REDIS_RELEASE="redis"
N8N_RELEASE="n8n"

# Print header
echo "=========================================="
echo "n8n Kubernetes Platform Update"
echo "=========================================="
echo ""

# Check for required tools
echo "Checking dependencies..."
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed. Aborting." >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "helm is required but not installed. Aborting." >&2; exit 1; }
echo "All dependencies are installed."
echo ""

# Update Helm repositories
echo "Updating Helm repositories..."
helm repo update
echo "Helm repositories updated."
echo ""

# Create pre-update backup
echo "Creating pre-update backup..."
BACKUP_DIR="./backups/pre-update-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
./scripts/backup.sh "$BACKUP_DIR"
echo "Pre-update backup created at $BACKUP_DIR"
echo ""

# Update PostgreSQL
echo "Updating PostgreSQL..."
helm upgrade $POSTGRES_RELEASE bitnami/postgresql \
  --namespace $NAMESPACE \
  -f helm/postgresql/values.yaml
echo "PostgreSQL update in progress."
echo ""

# Update Redis
echo "Updating Redis..."
helm upgrade $REDIS_RELEASE bitnami/redis \
  --namespace $NAMESPACE \
  -f helm/redis/values.yaml
echo "Redis update in progress."
echo ""

# Wait for PostgreSQL and Redis to be ready
echo "Waiting for PostgreSQL to be ready..."
kubectl rollout status statefulset/$POSTGRES_RELEASE --namespace $NAMESPACE --timeout=300s
echo "PostgreSQL is ready."
echo ""

echo "Waiting for Redis to be ready..."
kubectl rollout status statefulset/$REDIS_RELEASE-master --namespace $NAMESPACE --timeout=300s
echo "Redis is ready."
echo ""

# Update n8n
echo "Updating n8n..."
helm upgrade $N8N_RELEASE n8n/n8n \
  --namespace $NAMESPACE \
  -f helm/n8n/values.yaml
echo "n8n update in progress."
echo ""

# Update Ingress resources
echo "Updating Ingress resources..."
kubectl apply -f k8s/ingress/traefik.yaml -n $NAMESPACE
echo "Ingress resources updated."
echo ""

# Wait for n8n to be ready
echo "Waiting for n8n to be ready..."
kubectl rollout status deployment/$N8N_RELEASE --namespace $NAMESPACE --timeout=300s
echo "n8n is ready."
echo ""

# Finish update
echo "=========================================="
echo "Update completed! 🎉"
echo "=========================================="
echo ""
echo "All components have been updated to their latest versions."
echo ""
echo "To check the status of the deployment:"
echo "  kubectl get pods -n $NAMESPACE"
echo ""
echo "To view n8n logs:"
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=n8n --tail=100 -f"
echo ""
echo "If you need to rollback, you can use:"
echo "  helm rollback $N8N_RELEASE --namespace $NAMESPACE"
echo "  helm rollback $POSTGRES_RELEASE --namespace $NAMESPACE"
echo "  helm rollback $REDIS_RELEASE --namespace $NAMESPACE"
echo ""
echo "A backup was created before the update at: $BACKUP_DIR"
echo ""
echo "Done! 🚀"