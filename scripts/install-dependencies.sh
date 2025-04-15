#!/bin/bash
# Script to install all dependencies required for n8n on Kubernetes
# Optimized for Ubuntu Server 22.04

set -e

# Color codes for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}    Installing dependencies for n8n platform    ${NC}"
echo -e "${BLUE}================================================${NC}"
echo

# Check if running as root or with sudo
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}This script must be run as root or with sudo privileges${NC}"
    exit 1
fi

# Update package lists
echo -e "${YELLOW}Updating package lists...${NC}"
apt-get update
echo -e "${GREEN}Package lists updated.${NC}"
echo

# Install prerequisites
echo -e "${YELLOW}Installing prerequisites...${NC}"
apt-get install -y curl wget apt-transport-https ca-certificates gnupg lsb-release make openssl
echo -e "${GREEN}Prerequisites installed.${NC}"
echo

# Install kubectl
echo -e "${YELLOW}Installing kubectl...${NC}"
if ! command -v kubectl &> /dev/null; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/
    echo -e "${GREEN}kubectl installed.${NC}"
else
    echo -e "${GREEN}kubectl is already installed.${NC}"
fi
echo

# Install Helm
echo -e "${YELLOW}Installing Helm...${NC}"
if ! command -v helm &> /dev/null; then
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    echo -e "${GREEN}Helm installed.${NC}"
else
    echo -e "${GREEN}Helm is already installed.${NC}"
fi
echo

# Check if Kubernetes is installed (check for K3s, K8s, etc.)
if ! systemctl is-active --quiet k3s && ! command -v kubeadm &> /dev/null; then
    echo -e "${YELLOW}No Kubernetes distribution detected. Installing K3s...${NC}"
    echo -e "${YELLOW}This is a lightweight Kubernetes distribution suitable for this server.${NC}"
    echo
    
    # Ask if user wants to install K3s
    read -p "Do you want to install K3s (recommended for small servers)? [Y/n]: " -n 1 -r install_k3s
    echo
    
    if [[ $install_k3s =~ ^[Yy]$ ]] || [[ -z $install_k3s ]]; then
        echo -e "${YELLOW}Installing K3s...${NC}"
        # Install K3s without Traefik (we'll use our own ingress)
        curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -
        
        # Set up kubectl configuration
        mkdir -p ~/.kube
        cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
        chmod 600 ~/.kube/config
        
        # Wait for K3s to start
        echo -e "${YELLOW}Waiting for K3s to start...${NC}"
        sleep 10
        
        # Check if K3s is running
        if systemctl is-active --quiet k3s; then
            echo -e "${GREEN}K3s installed and running.${NC}"
        else
            echo -e "${RED}K3s installation may have failed. Please check 'systemctl status k3s'.${NC}"
        fi
    else
        echo -e "${YELLOW}Skipping K3s installation. You will need to install a Kubernetes distribution manually.${NC}"
    fi
else
    echo -e "${GREEN}Kubernetes is already installed.${NC}"
fi
echo

# Configure kubectl for K3s if it's installed
if systemctl is-active --quiet k3s; then
    echo -e "${YELLOW}Configuring kubectl for K3s...${NC}"
    mkdir -p ~/.kube
    cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    chmod 600 ~/.kube/config
    echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
    export KUBECONFIG=~/.kube/config
    echo -e "${GREEN}kubectl configured for K3s.${NC}"
    echo
fi

# Verify installations
echo -e "${YELLOW}Verifying installations...${NC}"
echo -e "kubectl version: $(kubectl version --client --output=yaml | grep gitVersion || echo 'Not installed')"
echo -e "helm version: $(helm version --short || echo 'Not installed')"
if systemctl is-active --quiet k3s; then
    echo -e "K3s status: Running"
    echo -e "Kubernetes nodes: $(kubectl get nodes -o name || echo 'Error')"
else
    echo -e "K3s status: Not installed or not running"
fi
echo

echo -e "${BLUE}================================================${NC}"
echo -e "${GREEN}Dependencies installation completed!${NC}"
echo -e "${BLUE}================================================${NC}"
echo
echo -e "You can now proceed with the n8n platform setup:"
echo -e "  ${YELLOW}cd /path/to/n8n-k8s-platform${NC}"
echo -e "  ${YELLOW}./setup.sh${NC}"
echo
echo -e "After setup, deploy with:"
echo -e "  ${YELLOW}make deploy${NC}"
echo