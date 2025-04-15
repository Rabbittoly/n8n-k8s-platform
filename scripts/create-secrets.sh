#!/bin/bash
# Script to create necessary Kubernetes secrets for n8n platform
set -e

# Color codes for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get configuration from environment or use defaults
NAMESPACE=${NAMESPACE:-"n8n"}
DOMAIN=${DOMAIN:-"n8n.example.com"}

# Load configuration if available and not already set
CONFIG_FILE="./.config/platform.conf"
if [ -f "$CONFIG_FILE" ] && [ -z "$DOMAIN" ]; then
  echo -e "${BLUE}Loading configuration from $CONFIG_FILE...${NC}"
  source "$CONFIG_FILE"
fi

# Print header
echo -e "${YELLOW}Creating Kubernetes secrets for n8n platform...${NC}"
echo

# Check if namespace exists
if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
  echo -e "${YELLOW}Creating namespace $NAMESPACE...${NC}"
  kubectl create namespace $NAMESPACE
fi

# Generate random encryption key for n8n if not provided
if [ -z "$ENCRYPTION_KEY" ]; then
  ENCRYPTION_KEY=$(openssl rand -hex 32)
  echo -e "${GREEN}Generated encryption key for n8n.${NC}"
else
  echo -e "${GREEN}Using provided encryption key.${NC}"
fi

# Generate random password for initial admin user if not provided
if [ -z "$INITIAL_PASSWORD" ]; then
  INITIAL_PASSWORD=$(openssl rand -base64 12)
  echo -e "${GREEN}Generated initial admin password.${NC}"
else
  echo -e "${GREEN}Using provided initial password.${NC}"
fi

# Create webhook URL from domain
WEBHOOK_URL="https://$DOMAIN/"
echo -e "${GREEN}Using webhook URL: $WEBHOOK_URL${NC}"

# Create the n8n-secrets secret
echo -e "${YELLOW}Creating n8n-secrets...${NC}"
kubectl create secret generic n8n-secrets \
  --namespace $NAMESPACE \
  --from-literal=encryptionKey=$ENCRYPTION_KEY \
  --from-literal=webhookUrl=$WEBHOOK_URL \
  --from-literal=initialPassword=$INITIAL_PASSWORD \
  --dry-run=client -o yaml | kubectl apply -f -

# Handle PostgreSQL secrets
if [ "$USE_EXTERNAL_PG" = "true" ]; then
  # Use provided external PostgreSQL credentials
  echo -e "${YELLOW}Creating PostgreSQL secret with external credentials...${NC}"
  kubectl create secret generic postgresql \
    --namespace $NAMESPACE \
    --from-literal=postgres-password="$PG_PASSWORD" \
    --from-literal=password="$PG_PASSWORD" \
    --from-literal=username="$PG_USERNAME" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  # Generate random passwords for PostgreSQL
  if [ -z "$PG_PASSWORD" ]; then
    PG_PASSWORD=$(openssl rand -base64 16)
    echo -e "${GREEN}Generated PostgreSQL password.${NC}"
  else
    echo -e "${GREEN}Using provided PostgreSQL password.${NC}"
  fi
  
  # Create the PostgreSQL secret
  echo -e "${YELLOW}Creating PostgreSQL secret...${NC}"
  kubectl create secret generic postgresql \
    --namespace $NAMESPACE \
    --from-literal=postgres-password=$PG_PASSWORD \
    --from-literal=password=$PG_PASSWORD \
    --from-literal=username=n8n \
    --dry-run=client -o yaml | kubectl apply -f -
fi

# Handle Redis secrets
if [ "$USE_EXTERNAL_REDIS" = "true" ]; then
  # Use provided external Redis credentials
  echo -e "${YELLOW}Creating Redis secret with external credentials...${NC}"
  kubectl create secret generic redis \
    --namespace $NAMESPACE \
    --from-literal=redis-password="$REDIS_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  # Generate random password for Redis
  if [ -z "$REDIS_PASSWORD" ]; then
    REDIS_PASSWORD=$(openssl rand -base64 16)
    echo -e "${GREEN}Generated Redis password.${NC}"
  else
    echo -e "${GREEN}Using provided Redis password.${NC}"
  fi
  
  # Create the Redis secret
  echo -e "${YELLOW}Creating Redis secret...${NC}"
  kubectl create secret generic redis \
    --namespace $NAMESPACE \
    --from-literal=redis-password=$REDIS_PASSWORD \
    --dry-run=client -o yaml | kubectl apply -f -
fi

# Create SMTP secrets if configured
if [ "$CONFIGURE_SMTP" = "true" ]; then
  echo -e "${YELLOW}Creating SMTP secrets...${NC}"
  kubectl create secret generic n8n-smtp-secrets \
    --namespace $NAMESPACE \
    --from-literal=smtpUser="$SMTP_USER" \
    --from-literal=smtpPass="$SMTP_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo -e "${GREEN}SMTP secrets created.${NC}"
fi

# Save secrets locally (optional, for backup purposes)
SECRETS_DIR="./.secrets"
mkdir -p $SECRETS_DIR
chmod 700 $SECRETS_DIR

# Save secrets to local file
{
  echo "# n8n Platform Secrets - $(date)"
  echo "# IMPORTANT: This file contains sensitive information. Keep it secure."
  echo ""
  echo "ENCRYPTION_KEY=$ENCRYPTION_KEY"
  echo "INITIAL_PASSWORD=$INITIAL_PASSWORD"
  echo "WEBHOOK_URL=$WEBHOOK_URL"
  if [ "$USE_EXTERNAL_PG" != "true" ]; then
    echo "POSTGRES_PASSWORD=$PG_PASSWORD"
  fi
  if [ "$USE_EXTERNAL_REDIS" != "true" ]; then
    echo "REDIS_PASSWORD=$REDIS_PASSWORD"
  fi
  if [ "$CONFIGURE_SMTP" = "true" ]; then
    echo "SMTP_USER=$SMTP_USER"
    echo "SMTP_PASSWORD=$SMTP_PASSWORD"
  fi
  echo ""
  echo "# Generated on $(date)"
} > $SECRETS_DIR/secrets.env

echo -e "${GREEN}Secrets backup saved to $SECRETS_DIR/secrets.env${NC}"
echo -e "${YELLOW}(This file is for backup purposes only. Keep it secure!)${NC}"
echo

# Print information 
echo -e "${GREEN}All secrets have been created in namespace $NAMESPACE.${NC}"
echo
echo -e "${BLUE}Initial admin password: ${YELLOW}$INITIAL_PASSWORD${NC}"
echo -e "${YELLOW}(Make sure to change this after first login!)${NC}"
echo
echo -e "${BLUE}Secrets summary:${NC}"
echo -e "- n8n-secrets: Contains encryption key, webhook URL, and initial password"
echo -e "- postgresql: Contains PostgreSQL credentials"
echo -e "- redis: Contains Redis password"
if [ "$CONFIGURE_SMTP" = "true" ]; then
  echo -e "- n8n-smtp-secrets: Contains SMTP credentials"
fi
echo
echo -e "${GREEN}Secrets creation completed.${NC}"