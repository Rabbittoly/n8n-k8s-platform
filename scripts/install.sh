#!/bin/bash
# n8n Installation Script
# This script installs the complete n8n platform with all its dependencies
set -e

# Color codes for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Load configuration if available
CONFIG_FILE="./.config/platform.conf"
if [ -f "$CONFIG_FILE" ]; then
  echo -e "${BLUE}Loading configuration from $CONFIG_FILE...${NC}"
  source "$CONFIG_FILE"
else
  echo -e "${YELLOW}Configuration file not found. Running setup wizard...${NC}"
  ./setup.sh
  source "$CONFIG_FILE"
fi

# Set defaults for variables that might not be in the config
NAMESPACE=${NAMESPACE:-"n8n"}
DOMAIN=${DOMAIN:-"n8n.example.com"}
EMAIL=${EMAIL:-"admin@example.com"}
INSTALL_MONITORING=${INSTALL_MONITORING:-"true"}

# Print header
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}n8n Kubernetes Platform Installation${NC}"
echo -e "${BLUE}=========================================${NC}"
echo

# Check for required tools
echo -e "${YELLOW}Checking dependencies...${NC}"
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}kubectl is required but not installed. Aborting.${NC}" >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}helm is required but not installed. Aborting.${NC}" >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo -e "${RED}openssl is required but not installed. Aborting.${NC}" >&2; exit 1; }
echo -e "${GREEN}All dependencies are installed.${NC}"
echo

# Create namespace if it doesn't exist
echo -e "${YELLOW}Creating namespace $NAMESPACE if it doesn't exist...${NC}"
kubectl get namespace $NAMESPACE >/dev/null 2>&1 || kubectl create namespace $NAMESPACE
echo -e "${GREEN}Namespace ready.${NC}"
echo

# Add Helm repositories
echo -e "${YELLOW}Adding Helm repositories...${NC}"
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add n8n https://n8n-io.github.io/n8n-helm
helm repo add traefik https://helm.traefik.io/traefik
helm repo add jetstack https://charts.jetstack.io
if [ "$INSTALL_MONITORING" = "true" ]; then
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
fi
helm repo update
echo -e "${GREEN}Helm repositories added.${NC}"
echo

# Create secrets
echo -e "${YELLOW}Creating secrets...${NC}"
# Export variables for create-secrets.sh
export DOMAIN NAMESPACE
if [ -n "$PG_USERNAME" ]; then export PG_USERNAME; fi
if [ -n "$PG_PASSWORD" ]; then export PG_PASSWORD; fi
if [ -n "$REDIS_PASSWORD" ]; then export REDIS_PASSWORD; fi
if [ "$CONFIGURE_SMTP" = "true" ]; then
  export SMTP_USER="$SMTP_USER"
  export SMTP_PASSWORD="$SMTP_PASSWORD"
fi

./scripts/create-secrets.sh
echo -e "${GREEN}Secrets created.${NC}"
echo

# Install Traefik if not already installed
echo -e "${YELLOW}Installing Traefik...${NC}"
kubectl get namespace traefik >/dev/null 2>&1 || kubectl create namespace traefik
helm upgrade --install traefik traefik/traefik --namespace traefik
echo -e "${GREEN}Traefik installed.${NC}"
echo

# Install cert-manager if not already installed and TLS is enabled
if [ "$USE_TLS" = "true" ]; then
  echo -e "${YELLOW}Installing cert-manager...${NC}"
  kubectl get namespace cert-manager >/dev/null 2>&1 || kubectl create namespace cert-manager
  helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --set installCRDs=true
  echo -e "${YELLOW}Waiting for cert-manager pods to be ready...${NC}"
  kubectl wait --for=condition=available deployment/cert-manager-webhook -n cert-manager --timeout=120s
  echo -e "${GREEN}cert-manager installed.${NC}"
  echo

  # Create ClusterIssuer for Let's Encrypt
  echo -e "${YELLOW}Creating Let's Encrypt ClusterIssuer...${NC}"
  kubectl apply -f k8s/cert-manager/cluster-issuer.yaml
  echo -e "${GREEN}ClusterIssuer created.${NC}"
  echo
fi

# Install PostgreSQL if not using external
if [ "$USE_EXTERNAL_PG" != "true" ]; then
  echo -e "${YELLOW}Installing PostgreSQL...${NC}"
  helm upgrade --install postgresql bitnami/postgresql \
    --namespace $NAMESPACE \
    -f helm/postgresql/values.yaml
  echo -e "${GREEN}PostgreSQL installation in progress. This may take a few minutes.${NC}"
  echo
fi

# Install Redis if not using external
if [ "$USE_EXTERNAL_REDIS" != "true" ]; then
  echo -e "${YELLOW}Installing Redis...${NC}"
  helm upgrade --install redis bitnami/redis \
    --namespace $NAMESPACE \
    -f helm/redis/values.yaml
  echo -e "${GREEN}Redis installation in progress. This may take a few minutes.${NC}"
  echo
fi

# Wait for PostgreSQL and Redis to be ready
if [ "$USE_EXTERNAL_PG" != "true" ]; then
  echo -e "${YELLOW}Waiting for PostgreSQL to be ready...${NC}"
  kubectl wait --for=condition=ready pod/postgresql-0 --namespace $NAMESPACE --timeout=300s
  echo -e "${GREEN}PostgreSQL is ready.${NC}"
fi

if [ "$USE_EXTERNAL_REDIS" != "true" ]; then
  echo -e "${YELLOW}Waiting for Redis to be ready...${NC}"
  kubectl wait --for=condition=ready pod/redis-master-0 --namespace $NAMESPACE --timeout=300s
  echo -e "${GREEN}Redis is ready.${NC}"
fi
echo

# Install n8n
echo -e "${YELLOW}Installing n8n...${NC}"
helm upgrade --install n8n n8n/n8n \
  --namespace $NAMESPACE \
  -f helm/n8n/values.yaml
echo -e "${GREEN}n8n installation in progress...${NC}"
echo

# Apply Traefik IngressRoute
echo -e "${YELLOW}Configuring Traefik IngressRoute...${NC}"
kubectl apply -f k8s/ingress/traefik.yaml -n $NAMESPACE
echo -e "${GREEN}IngressRoute configured.${NC}"
echo

# Install monitoring if enabled
if [ "$INSTALL_MONITORING" = "true" ]; then
  echo -e "${YELLOW}Installing monitoring (Prometheus/Grafana)...${NC}"
  kubectl get namespace monitoring >/dev/null 2>&1 || kubectl create namespace monitoring
  
  # Install Prometheus and Grafana
  helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --set grafana.adminPassword=admin \
    --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
    --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false
  
  # Apply n8n Grafana dashboard
  kubectl apply -f k8s/monitoring/grafana.yaml -n monitoring
  
  # Apply n8n service monitor
  kubectl apply -f k8s/monitoring/prometheus.yaml -n monitoring
  
  echo -e "${GREEN}Monitoring installed.${NC}"
  echo
fi

# Finish installation
echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Installation completed! 🎉${NC}"
echo -e "${BLUE}=========================================${NC}"
echo
echo -e "n8n should be available soon at: ${YELLOW}https://$DOMAIN${NC}"
echo
echo -e "To get the initial admin password (if configured):"
echo -e "  ${YELLOW}kubectl get secret -n $NAMESPACE n8n-secrets -o jsonpath='{.data.initialPassword}' | base64 -d${NC}"
echo
echo -e "To check the status of the deployment:"
echo -e "  ${YELLOW}kubectl get pods -n $NAMESPACE${NC}"
echo
echo -e "To view n8n logs:"
echo -e "  ${YELLOW}kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=n8n --tail=100 -f${NC}"
echo

if [ "$INSTALL_MONITORING" = "true" ]; then
  echo -e "Monitoring is available at:"
  echo -e "  Prometheus: ${YELLOW}http://monitoring-prometheus.monitoring.svc.cluster.local:9090${NC}"
  echo -e "  Grafana:    ${YELLOW}http://monitoring-grafana.monitoring.svc.cluster.local:3000${NC}"
  echo -e "  Grafana default credentials: admin / admin"
  echo -e "  (expose these services externally by creating additional ingress resources)"
  echo
fi

echo -e "${GREEN}Done! 🚀${NC}"