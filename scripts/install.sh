#!/bin/bash
# n8n Platform Setup Script
# Interactive setup wizard for configuring n8n deployment
# Optimized for minimal servers (2 CPU, 4GB RAM)

set -e

# Color codes for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print header
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}   n8n Kubernetes Platform - Setup Wizard       ${NC}"
echo -e "${BLUE}================================================${NC}"
echo
echo -e "This wizard will help you configure your n8n platform deployment."
echo -e "The settings will be saved and can be changed later if needed."
echo

# Check dependencies first
if ! command -v kubectl &> /dev/null || ! command -v helm &> /dev/null; then
    echo -e "${YELLOW}Required dependencies (kubectl and/or helm) are not installed.${NC}"
    echo -e "${YELLOW}Would you like to install them now?${NC}"
    read -p "Install dependencies? [Y/n]: " -n 1 -r install_deps
    echo
    
    if [[ $install_deps =~ ^[Yy]$ ]] || [[ -z $install_deps ]]; then
        echo -e "${YELLOW}Installing dependencies...${NC}"
        chmod +x scripts/install-dependencies.sh
        ./scripts/install-dependencies.sh
    else
        echo -e "${RED}Dependencies are required to proceed. Please install them manually.${NC}"
        echo -e "${YELLOW}Run: ./scripts/install-dependencies.sh${NC}"
        exit 1
    fi
fi

# Create config directory if it doesn't exist
CONFIG_DIR="./.config"
mkdir -p "$CONFIG_DIR"
CONFIG_FILE="$CONFIG_DIR/platform.conf"

# Function to prompt for a value with a default
prompt_with_default() {
  local prompt_text="$1"
  local default_val="$2"
  local var_name="$3"
  local current_val="${!var_name}"
  
  # If there's a current value, use it as default
  if [ -n "$current_val" ]; then
    default_val="$current_val"
  fi
  
  # Show prompt with default
  if [ -n "$default_val" ]; then
    read -p "$prompt_text [$default_val]: " input
    if [ -z "$input" ]; then
      input="$default_val"
    fi
  else
    read -p "$prompt_text: " input
  fi
  
  # Set the value in the calling environment
  eval "$var_name=\"$input\""
}

# Function to prompt for a yes/no value
prompt_yes_no() {
  local prompt_text="$1"
  local default_val="$2" # Should be "y" or "n"
  local var_name="$3"
  local current_val="${!var_name}"
  
  # If there's a current value, use it as default
  if [ -n "$current_val" ]; then
    if [ "$current_val" = "true" ]; then
      default_val="y"
    else
      default_val="n"
    fi
  fi
  
  while true; do
    # Show prompt with default
    if [ "$default_val" = "y" ]; then
      read -p "$prompt_text [Y/n]: " input
      if [ -z "$input" ]; then
        input="y"
      fi
    else
      read -p "$prompt_text [y/N]: " input
      if [ -z "$input" ]; then
        input="n"
      fi
    fi
    
    case $input in
      [Yy]* ) eval "$var_name=\"true\""; break;;
      [Nn]* ) eval "$var_name=\"false\""; break;;
      * ) echo "Please answer yes (y) or no (n).";;
    esac
  done
}

# Load existing configuration if available
if [ -f "$CONFIG_FILE" ]; then
  echo -e "${YELLOW}Loading existing configuration...${NC}"
  source "$CONFIG_FILE"
  echo -e "${GREEN}Configuration loaded. You can update values or press Enter to keep current ones.${NC}"
  echo
fi

echo -e "${BLUE}=== Basic Configuration ===${NC}"

# Domain configuration
prompt_with_default "Domain for n8n" "n8n.example.com" "DOMAIN"
prompt_with_default "Email address (for Let's Encrypt)" "admin@example.com" "EMAIL"

# Environment selection
echo
echo "Select environment type:"
echo "  1) Production"
echo "  2) Staging"
echo "  3) Development"
read -p "Environment [1]: " ENV_CHOICE
case $ENV_CHOICE in
  2) ENVIRONMENT="staging";;
  3) ENVIRONMENT="development";;
  *) ENVIRONMENT="production";;
esac

echo
echo -e "${BLUE}=== Cluster Configuration ===${NC}"

# Namespace
prompt_with_default "Kubernetes namespace" "n8n" "NAMESPACE"

# Storage
echo
prompt_with_default "Storage class (leave empty for default)" "" "STORAGE_CLASS"

# Server size selection
echo
echo "Select server size configuration:"
echo "  1) Small (2 CPU, 4GB RAM)"
echo "  2) Medium (4 CPU, 8GB RAM)"
echo "  3) Large (8+ CPU, 16+ GB RAM)"
echo "  4) Custom"
read -p "Server size [1]: " SIZE_CHOICE

case $SIZE_CHOICE in
  2)
    # Medium server configuration
    N8N_REPLICAS="2"
    CONFIGURE_RESOURCES="true"
    N8N_CPU_LIMIT="1"
    N8N_MEMORY_LIMIT="2048"
    N8N_CPU_REQUEST="500m"
    N8N_MEMORY_REQUEST="1024"
    PG_CPU_LIMIT="1"
    PG_MEMORY_LIMIT="2048"
    PG_CPU_REQUEST="500m"
    PG_MEMORY_REQUEST="1024"
    REDIS_CPU_LIMIT="500m"
    REDIS_MEMORY_LIMIT="1024"
    REDIS_CPU_REQUEST="250m"
    REDIS_MEMORY_REQUEST="512"
    INSTALL_MONITORING="true"
    ;;
  3)
    # Large server configuration
    N8N_REPLICAS="3"
    CONFIGURE_RESOURCES="true"
    N8N_CPU_LIMIT="2"
    N8N_MEMORY_LIMIT="4096"
    N8N_CPU_REQUEST="1"
    N8N_MEMORY_REQUEST="2048"
    PG_CPU_LIMIT="2"
    PG_MEMORY_LIMIT="4096"
    PG_CPU_REQUEST="1"
    PG_MEMORY_REQUEST="2048"
    REDIS_CPU_LIMIT="1"
    REDIS_MEMORY_LIMIT="2048"
    REDIS_CPU_REQUEST="500m"
    REDIS_MEMORY_REQUEST="1024"
    INSTALL_MONITORING="true"
    ;;
  4)
    # Custom configuration
    echo
    prompt_yes_no "Configure resource limits and requests?" "y" "CONFIGURE_RESOURCES"
    
    if [ "$CONFIGURE_RESOURCES" = "true" ]; then
      echo
      echo -e "${BLUE}=== Resource Configuration ===${NC}"
      
      # n8n resources
      echo "n8n resources:"
      prompt_with_default "  CPU limit (cores)" "500m" "N8N_CPU_LIMIT"
      prompt_with_default "  Memory limit (Mi)" "1024" "N8N_MEMORY_LIMIT"
      prompt_with_default "  CPU request (cores)" "250m" "N8N_CPU_REQUEST"
      prompt_with_default "  Memory request (Mi)" "512" "N8N_MEMORY_REQUEST"
      
      # PostgreSQL resources
      echo
      echo "PostgreSQL resources:"
      prompt_with_default "  CPU limit (cores)" "500m" "PG_CPU_LIMIT"
      prompt_with_default "  Memory limit (Mi)" "1024" "PG_MEMORY_LIMIT"
      prompt_with_default "  CPU request (cores)" "250m" "PG_CPU_REQUEST"
      prompt_with_default "  Memory request (Mi)" "512" "PG_MEMORY_REQUEST"
      
      # Redis resources
      echo
      echo "Redis resources:"
      prompt_with_default "  CPU limit (cores)" "250m" "REDIS_CPU_LIMIT"
      prompt_with_default "  Memory limit (Mi)" "512" "REDIS_MEMORY_LIMIT"
      prompt_with_default "  CPU request (cores)" "100m" "REDIS_CPU_REQUEST"
      prompt_with_default "  Memory request (Mi)" "256" "REDIS_MEMORY_REQUEST"
    fi
    ;;
  *)
    # Small server configuration (default)
    N8N_REPLICAS="1"
    CONFIGURE_RESOURCES="true"
    N8N_CPU_LIMIT="500m"
    N8N_MEMORY_LIMIT="1024"
    N8N_CPU_REQUEST="250m"
    N8N_MEMORY_REQUEST="512"
    PG_CPU_LIMIT="500m"
    PG_MEMORY_LIMIT="1024"
    PG_CPU_REQUEST="250m"
    PG_MEMORY_REQUEST="512"
    REDIS_CPU_LIMIT="250m"
    REDIS_MEMORY_LIMIT="512"
    REDIS_CPU_REQUEST="100m"
    REDIS_MEMORY_REQUEST="256"
    INSTALL_MONITORING="false"
    ;;
esac

echo
echo -e "${BLUE}=== Component Configuration ===${NC}"

# Replicas
if [ -z "$N8N_REPLICAS" ]; then
  prompt_with_default "Number of n8n replicas" "1" "N8N_REPLICAS"
fi

# PostgreSQL and Redis configuration
prompt_yes_no "Use external PostgreSQL database?" "n" "USE_EXTERNAL_PG"
if [ "$USE_EXTERNAL_PG" = "true" ]; then
  prompt_with_default "PostgreSQL host" "postgres.example.com" "PG_HOST"
  prompt_with_default "PostgreSQL port" "5432" "PG_PORT"
  prompt_with_default "PostgreSQL database" "n8n" "PG_DATABASE"
  prompt_with_default "PostgreSQL username" "n8n" "PG_USERNAME"
  prompt_with_default "PostgreSQL password" "" "PG_PASSWORD"
fi

prompt_yes_no "Use external Redis instance?" "n" "USE_EXTERNAL_REDIS"
if [ "$USE_EXTERNAL_REDIS" = "true" ]; then
  prompt_with_default "Redis host" "redis.example.com" "REDIS_HOST"
  prompt_with_default "Redis port" "6379" "REDIS_PORT"
  prompt_with_default "Redis password" "" "REDIS_PASSWORD"
fi

echo
echo -e "${BLUE}=== Additional Features ===${NC}"

# TLS configuration
prompt_yes_no "Configure TLS with Let's Encrypt?" "y" "USE_TLS"

# Monitoring (default to off for small servers)
if [ -z "$INSTALL_MONITORING" ]; then
  prompt_yes_no "Install monitoring (Prometheus/Grafana)?" "n" "INSTALL_MONITORING"
fi

# SMTP configuration
prompt_yes_no "Configure SMTP for email notifications?" "n" "CONFIGURE_SMTP"
if [ "$CONFIGURE_SMTP" = "true" ]; then
  prompt_with_default "SMTP host" "smtp.example.com" "SMTP_HOST"
  prompt_with_default "SMTP port" "587" "SMTP_PORT"
  prompt_with_default "SMTP username" "user@example.com" "SMTP_USER"
  prompt_with_default "SMTP password" "" "SMTP_PASSWORD"
  prompt_with_default "SMTP sender email" "n8n@example.com" "SMTP_SENDER"
fi

# Save the configuration
echo
echo -e "${YELLOW}Saving configuration...${NC}"

cat > "$CONFIG_FILE" <<EOL
# n8n Platform Configuration
# Generated on $(date)

# Basic Configuration
DOMAIN="$DOMAIN"
EMAIL="$EMAIL"
ENVIRONMENT="$ENVIRONMENT"
NAMESPACE="$NAMESPACE"
STORAGE_CLASS="$STORAGE_CLASS"

# Resource Configuration
CONFIGURE_RESOURCES="$CONFIGURE_RESOURCES"
N8N_CPU_LIMIT="$N8N_CPU_LIMIT"
N8N_MEMORY_LIMIT="$N8N_MEMORY_LIMIT"
N8N_CPU_REQUEST="$N8N_CPU_REQUEST"
N8N_MEMORY_REQUEST="$N8N_MEMORY_REQUEST"
PG_CPU_LIMIT="$PG_CPU_LIMIT"
PG_MEMORY_LIMIT="$PG_MEMORY_LIMIT"
PG_CPU_REQUEST="$PG_CPU_REQUEST"
PG_MEMORY_REQUEST="$PG_MEMORY_REQUEST"
REDIS_CPU_LIMIT="$REDIS_CPU_LIMIT"
REDIS_MEMORY_LIMIT="$REDIS_MEMORY_LIMIT"
REDIS_CPU_REQUEST="$REDIS_CPU_REQUEST"
REDIS_MEMORY_REQUEST="$REDIS_MEMORY_REQUEST"

# Component Configuration
N8N_REPLICAS="$N8N_REPLICAS"
USE_EXTERNAL_PG="$USE_EXTERNAL_PG"
PG_HOST="$PG_HOST"
PG_PORT="$PG_PORT"
PG_DATABASE="$PG_DATABASE"
PG_USERNAME="$PG_USERNAME"
PG_PASSWORD="$PG_PASSWORD"
USE_EXTERNAL_REDIS="$USE_EXTERNAL_REDIS"
REDIS_HOST="$REDIS_HOST"
REDIS_PORT="$REDIS_PORT"
REDIS_PASSWORD="$REDIS_PASSWORD"

# Additional Features
USE_TLS="$USE_TLS"
INSTALL_MONITORING="$INSTALL_MONITORING"
CONFIGURE_SMTP="$CONFIGURE_SMTP"
SMTP_HOST="$SMTP_HOST"
SMTP_PORT="$SMTP_PORT"
SMTP_USER="$SMTP_USER"
SMTP_PASSWORD="$SMTP_PASSWORD"
SMTP_SENDER="$SMTP_SENDER"
EOL

echo -e "${GREEN}Configuration saved to $CONFIG_FILE${NC}"
echo

# Make all scripts executable
echo -e "${YELLOW}Making scripts executable...${NC}"
chmod +x scripts/*.sh
echo -e "${GREEN}Scripts are now executable${NC}"
echo

# Update configuration files based on settings
echo -e "${YELLOW}Updating configuration files...${NC}"

# Update n8n values.yaml
echo "Updating n8n values.yaml..."
cp helm/n8n/values.example.yaml helm/n8n/values.yaml
sed -i "s/n8n.example.com/$DOMAIN/g" helm/n8n/values.yaml
sed -i "s/replicaCount: 2/replicaCount: $N8N_REPLICAS/g" helm/n8n/values.yaml

# Update storage class if specified
if [ -n "$STORAGE_CLASS" ]; then
  sed -i "s/storageClass: \"\"/storageClass: \"$STORAGE_CLASS\"/g" helm/n8n/values.yaml
  sed -i "s/storageClass: \"\"/storageClass: \"$STORAGE_CLASS\"/g" helm/postgresql/values.yaml
  sed -i "s/storageClass: \"\"/storageClass: \"$STORAGE_CLASS\"/g" helm/redis/values.yaml
fi

# Update resource settings if enabled
if [ "$CONFIGURE_RESOURCES" = "true" ]; then
  # Update n8n resources
  sed -i "s/cpu: 1/cpu: $N8N_CPU_LIMIT/g" helm/n8n/values.yaml
  sed -i "s/memory: 2Gi/memory: ${N8N_MEMORY_LIMIT}Mi/g" helm/n8n/values.yaml
  sed -i "s/cpu: 500m/cpu: $N8N_CPU_REQUEST/g" helm/n8n/values.yaml
  sed -i "s/memory: 1Gi/memory: ${N8N_MEMORY_REQUEST}Mi/g" helm/n8n/values.yaml
  
  # Update PostgreSQL resources
  sed -i "s/cpu: 1/cpu: $PG_CPU_LIMIT/g" helm/postgresql/values.yaml
  sed -i "s/memory: 2Gi/memory: ${PG_MEMORY_LIMIT}Mi/g" helm/postgresql/values.yaml
  sed -i "s/cpu: 500m/cpu: $PG_CPU_REQUEST/g" helm/postgresql/values.yaml
  sed -i "s/memory: 1Gi/memory: ${PG_MEMORY_REQUEST}Mi/g" helm/postgresql/values.yaml
  
  # Update Redis resources
  sed -i "s/cpu: 1000m/cpu: $REDIS_CPU_LIMIT/g" helm/redis/values.yaml
  sed -i "s/memory: 1Gi/memory: ${REDIS_MEMORY_LIMIT}Mi/g" helm/redis/values.yaml
  sed -i "s/cpu: 500m/cpu: $REDIS_CPU_REQUEST/g" helm/redis/values.yaml
  sed -i "s/memory: 512Mi/memory: ${REDIS_MEMORY_REQUEST}Mi/g" helm/redis/values.yaml
fi

# Update SMTP settings if enabled
if [ "$CONFIGURE_SMTP" = "true" ]; then
  # Uncomment SMTP settings in values.yaml
  sed -i 's/# - name: N8N_EMAIL_MODE/- name: N8N_EMAIL_MODE/g' helm/n8n/values.yaml
  sed -i 's/#   value: "smtp"/  value: "smtp"/g' helm/n8n/values.yaml
  sed -i 's/# - name: N8N_SMTP_HOST/- name: N8N_SMTP_HOST/g' helm/n8n/values.yaml
  sed -i "s/#   value: \"smtp.example.com\"/  value: \"$SMTP_HOST\"/g" helm/n8n/values.yaml
  sed -i 's/# - name: N8N_SMTP_PORT/- name: N8N_SMTP_PORT/g' helm/n8n/values.yaml
  sed -i "s/#   value: \"587\"/  value: \"$SMTP_PORT\"/g" helm/n8n/values.yaml
  sed -i 's/# - name: N8N_SMTP_USER/- name: N8N_SMTP_USER/g' helm/n8n/values.yaml
  sed -i 's/# - name: N8N_SMTP_PASS/- name: N8N_SMTP_PASS/g' helm/n8n/values.yaml
  sed -i 's/# - name: N8N_SMTP_SENDER/- name: N8N_SMTP_SENDER/g' helm/n8n/values.yaml
  sed -i "s/#   value: \"n8n@example.com\"/  value: \"$SMTP_SENDER\"/g" helm/n8n/values.yaml
fi

# Update ingress configuration
echo "Updating ingress configuration..."
sed -i "s/n8n.example.com/$DOMAIN/g" k8s/ingress/traefik.yaml

# Update cert-manager configuration
echo "Updating cert-manager configuration..."
sed -i "s/admin@example.com/$EMAIL/g" k8s/cert-manager/cluster-issuer.yaml

echo -e "${GREEN}Configuration files updated successfully!${NC}"
echo

# Output summary
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}   Setup Complete - Deployment Summary          ${NC}"
echo -e "${BLUE}================================================${NC}"
echo
echo -e "Your n8n platform has been configured with the following settings:"
echo -e "  Domain:           ${GREEN}$DOMAIN${NC}"
echo -e "  Environment:      ${GREEN}$ENVIRONMENT${NC}"
echo -e "  Namespace:        ${GREEN}$NAMESPACE${NC}"
echo -e "  n8n Replicas:     ${GREEN}$N8N_REPLICAS${NC}"
echo
echo -e "To deploy your platform, run:"
echo -e "  ${YELLOW}make deploy${NC}"
echo
echo -e "To view all available commands:"
echo -e "  ${YELLOW}make help${NC}"
echo
echo -e "Your configuration is saved and can be modified at any time by running:"
echo -e "  ${YELLOW}./setup.sh${NC}"
echo
echo -e "${GREEN}Setup completed successfully!${NC}"