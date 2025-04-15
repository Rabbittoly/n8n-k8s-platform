
# n8n Kubernetes Platform

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

A production-ready Kubernetes deployment for n8n workflow automation platform with PostgreSQL and Redis. This repository is designed as a template that works even on small servers (2 CPU, 4GB RAM) with the option to scale up for larger deployments.

## 🌟 Features

* **Works on Minimal Hardware** : Optimized for servers with just 2 CPU cores and 4GB RAM
* **Automatic Dependencies** : Installs all requirements on Ubuntu Server 22.04 automatically
* **Interactive Setup** : Simple wizard for configuring your deployment
* **Complete Solution** : Fully configured n8n with PostgreSQL and Redis backends
* **Security** : TLS encryption, secure secrets management, proper RBAC
* **Simplicity** : Deploy with a single command using Make
* **GitOps Ready** : Properly structured for GitOps workflows
* **Scalability** : Easily adjust resources as your needs grow

## 🚀 Getting Started

### Prerequisites

* Ubuntu Server 22.04 (recommended)
* At least 2 CPU cores and 4GB RAM
* Basic knowledge of Linux command line
* A domain name pointing to your server's IP address

### Quick Install

1. Clone this repository:

   ```bash
   git clone https://github.com/rabbittoly/n8n-k8s-platform.git
   cd n8n-k8s-platform
   ```
2. Make the setup script executable and run it:

   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```

   The wizard will:

   * Check and install required dependencies (kubectl, helm, K3s)
   * Guide you through configuring your deployment
   * Optimize settings for your server size
3. Deploy with a single command:

   ```bash
   make deploy
   ```
4. Access n8n at your configured domain (e.g., https://n8n.example.com)

## 📦 Architecture

```
                      ┌──────────────┐
                      │   Internet   │
                      └──────┬───────┘
                             │
                             ▼
┌──────────────────────────────────────────────────┐
│                Kubernetes (K3s)                  │
│                                                  │
│   ┌───────────┐      ┌──────────────────┐        │
│   │  Traefik  │──────►  Ingress Route   │        │
│   └───────────┘      └─────────┬────────┘        │
│                                │                  │
│                                ▼                  │
│   ┌────────────────────────────────────────┐     │
│   │               n8n Pod                  │     │
│   └───────────────┬──────────┬─────────────┘     │
│                   │          │                    │
│                   ▼          ▼                    │
│   ┌───────────────────┐    ┌───────────────┐     │
│   │   PostgreSQL      │    │     Redis     │     │
│   │   (StatefulSet)   │    │ (StatefulSet) │     │
│   └───────────────────┘    └───────────────┘     │
│                                                  │
└──────────────────────────────────────────────────┘
```

## 🛠️ Usage

### Makefile Commands

This repository includes a Makefile with common operations:

```bash
# Install dependencies
make dependencies

# Run the interactive setup wizard
make setup

# Deploy everything
make deploy

# Check status of deployment
make status

# View logs
make logs

# Update to the latest version
make update

# Create a backup
make backup

# Restore from backup
make restore BACKUP_FILE=./backups/n8n-backup-20250414-120000.tar.gz

# Uninstall
make uninstall
```

Run `make help` to see all available commands.

## ⚙️ Configuration Options

The interactive setup wizard offers several pre-configured options:

### Server Size

1. **Small (2 CPU, 4GB RAM)**
   * Single n8n replica
   * Minimal resource allocation
   * No Redis replication
   * Monitoring disabled by default
2. **Medium (4 CPU, 8GB RAM)**
   * 2 n8n replicas for high availability
   * Moderate resource allocation
   * Basic monitoring
3. **Large (8+ CPU, 16+ GB RAM)**
   * 3+ n8n replicas
   * Redis replication
   * Full monitoring stack
   * Auto-scaling enabled
4. **Custom**
   * Manually configure all settings

### Component Options

* **External Database** : Connect to an existing PostgreSQL database
* **External Redis** : Connect to an existing Redis instance
* **TLS** : Automatically configure Let's Encrypt certificates
* **SMTP** : Configure email notifications
* **Monitoring** : Install Prometheus and Grafana (optional)

## 🔍 Performance Considerations

For small servers (2 CPU, 4GB RAM):

* Single n8n replica to conserve resources
* Disabled monitoring to save memory
* Reduced database connection limits
* Conservative memory settings for PostgreSQL and Redis
* No Redis replication

As your needs grow, you can easily reconfigure:

1. Run `./setup.sh` again and select a larger server profile
2. Run `make deploy` to apply the new configuration

## 🛡️ Security

This deployment follows security best practices:

* All sensitive data stored in Kubernetes Secrets
* TLS encryption for all external traffic
* Non-root containers with proper security contexts
* Network policies to restrict traffic

## 📚 Disaster Recovery

### Backup and Restore

```bash
# Create a backup
make backup

# Restore from a backup
make restore BACKUP_FILE=./backups/n8n-backup-20250414-120000.tar.gz
```

## 📅 Maintenance

### Updates

To update to the latest version:

```bash
make update
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License.

## 🔗 Links

* [n8n Documentation](https://docs.n8n.io/)
* [Kubernetes Documentation](https://kubernetes.io/docs/)
* [K3s Documentation](https://docs.k3s.io/)
* [Helm Documentation](https://helm.sh/docs/)
