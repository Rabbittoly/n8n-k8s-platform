# n8n Kubernetes Platform

[![CI/CD](https://github.com/username/n8n-k8s-platform/actions/workflows/deploy.yml/badge.svg)](https://github.com/username/n8n-k8s-platform/actions/workflows/deploy.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

A production-ready Kubernetes deployment for n8n workflow automation platform with PostgreSQL and Redis. This repository is designed as a template for deploying n8n in a production Kubernetes environment with high availability, scalability, and security.

## 🌟 Features

* **Interactive Setup** : Simple wizard for configuring your deployment
* **Complete Production Setup** : Fully configured n8n with PostgreSQL and Redis backends
* **High Availability** : Multiple replicas, auto-scaling, and proper health checks
* **Security** : TLS encryption, secure secrets management, proper RBAC
* **Observability** : Prometheus metrics, Grafana dashboards, and structured logging
* **Simplicity** : Deploy with a single command using Make
* **GitOps Ready** : Properly structured for GitOps workflows with ArgoCD or Flux
* **CI/CD** : Built-in GitHub Actions for validation and deployment

## 🚀 Getting Started

### Use As Template

This repository is designed to be used as a template:

1. Click the "Use this template" button on GitHub or fork the repository
2. Clone your copy of the repository to your local machine
3. Run the interactive setup wizard to configure your deployment
4. Deploy with a single command

### Prerequisites

* Kubernetes cluster (v1.26+)
* kubectl configured to access your cluster
* Helm (v3.11+)
* Make
* Domain name pointing to your cluster's ingress

### Installation

1. Clone your copy of the repository:

   ```bash
   git clone https://github.com/Rabbittoly/n8n-k8s-platform.git
   cd n8n-k8s-platform
   ```
2. Run the interactive setup wizard:

   ```bash
   ./setup.sh
   ```

   The wizard will guide you through configuring your deployment, including:

   * Domain name
   * Database settings
   * Resource limits
   * TLS configuration
   * Monitoring setup

   All settings are saved and can be changed at any time by running `./setup.sh` again.
3. Deploy with a single command:

   ```bash
   make deploy
   ```
4. Access n8n at your configured domain (e.g., https://n8n.example.com)

## 📦 Architecture

The platform consists of the following components:

```
                                 ┌──────────────┐
                                 │   Internet   │
                                 └──────┬───────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Kubernetes Cluster                          │
│                                                                  │
│   ┌───────────┐      ┌─────────────────────────────────────┐    │
│   │  Traefik  │──────►  Ingress (n8n.example.com)          │    │
│   └───────────┘      └────────────────┬────────────────────┘    │
│                                       │                          │
│                                       ▼                          │
│   ┌───────────────────────────────────────────────────────┐     │
│   │                    n8n Deployment                      │     │
│   │                                                        │     │
│   │   ┌──────────┐  ┌──────────┐  ┌──────────┐            │     │
│   │   │   Pod 1  │  │   Pod 2  │  │   Pod N  │            │     │
│   │   └──────────┘  └──────────┘  └──────────┘            │     │
│   │         │              │             │                 │     │
│   └─────────┼──────────────┼─────────────┼─────────────────┘     │
│             │              │             │                       │
│             ▼              ▼             ▼                       │
│   ┌─────────────────┐    ┌─────────────────┐                     │
│   │   PostgreSQL    │    │      Redis      │                     │
│   │   (Stateful)    │    │   (Stateful)    │                     │
│   └─────────────────┘    └─────────────────┘                     │
│                                                                  │
│   ┌─────────────────┐    ┌─────────────────┐                     │
│   │   Prometheus    │    │     Grafana     │                     │
│   │   (Monitoring)  │    │  (Dashboards)   │                     │
│   └─────────────────┘    └─────────────────┘                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## 🛠️ Usage

### Makefile Commands

This repository includes a Makefile with common operations:

```bash
# Run the interactive setup wizard
make setup

# Deploy everything
make deploy

# Update to the latest version
make update

# Create a backup
make backup

# Show n8n logs
make logs

# Get n8n status
make status

# Uninstall everything
make uninstall
```

Run `make help` to see all available commands.

### Customization

The interactive setup wizard helps you configure most aspects of the deployment. If you need more advanced customization:

* Modify `helm/n8n/values.yaml` to customize n8n settings
* Modify `helm/postgresql/values.yaml` to customize PostgreSQL settings
* Modify `helm/redis/values.yaml` to customize Redis settings
* Modify `k8s/ingress/traefik.yaml` to customize ingress settings

### Accessing n8n

Once deployed, n8n will be available at your configured domain (e.g., https://n8n.example.com).

Default login credentials are:

* Username: admin@example.com
* Password: (Generated during setup and printed in console)

To get the password after deployment:

```bash
kubectl get secret -n n8n n8n-secrets -o jsonpath='{.data.initialPassword}' | base64 -d
```

## ⚙️ Configuration

All configuration is handled through the interactive setup wizard (`./setup.sh`). The wizard generates configuration files that are used by the deployment scripts.

Your configuration is saved in `.config/platform.conf` and can be edited manually if needed.

### Environment Variables

All n8n environment variables can be configured through the setup wizard. The most important ones are:

* `N8N_ENCRYPTION_KEY`: Encryption key for sensitive data
* `WEBHOOK_URL`: URL for webhooks
* `N8N_HOST`: Hostname for n8n
* `N8N_PORT`: Port for n8n
* `DB_TYPE`: Database type (postgresdb)
* `DB_POSTGRESDB_*`: PostgreSQL connection settings
* `N8N_REDIS_*`: Redis connection settings

### Secrets Management

Sensitive information is stored in Kubernetes Secrets:

* `n8n-secrets`: Contains encryption key and webhook URL
* `postgresql`: Contains PostgreSQL credentials
* `redis`: Contains Redis credentials
* `n8n-smtp-secrets`: Contains SMTP credentials (if configured)

### Scaling

n8n is configured with horizontal pod autoscaling (HPA) that will automatically scale based on CPU and memory usage. You can adjust the scaling parameters in the setup wizard.

## 🔍 Monitoring

This setup includes Prometheus for metrics collection and Grafana for visualization. You can enable monitoring during the setup process.

Monitoring dashboards can be accessed at:

* Prometheus: http://prometheus.monitoring.svc.cluster.local:9090 (cluster internal)
* Grafana: http://grafana.monitoring.svc.cluster.local:3000 (cluster internal)

You can expose these services externally by creating additional ingress resources.

## 🛡️ Security

This deployment follows security best practices:

* All sensitive data stored in Kubernetes Secrets
* TLS encryption for all external traffic
* Non-root containers with proper security contexts
* Resource limits to prevent resource exhaustion attacks
* Network policies to restrict traffic
* Regular security updates through CI/CD

## 📚 Disaster Recovery

### Backup Procedures

Use the provided backup script to create backups:

```bash
make backup
```

This will create a backup of:

* PostgreSQL database
* n8n configuration
* Kubernetes resources

Backups are stored in the `./backups` directory.

### Restoration Procedures

To restore from a backup:

1. Ensure the cluster is running
2. Run the restore command with the backup file:
   ```bash
   make restore BACKUP_FILE=./backups/n8n-backup-20250414-120000.tar.gz
   ```

## 📅 Maintenance

### Updates

To update to the latest version:

```bash
make update
```

This will:

1. Update all Helm repositories
2. Upgrade n8n, PostgreSQL, and Redis to their latest versions
3. Apply any configuration changes

### Troubleshooting

Common issues and their solutions:

1. **Pods not starting** : Check events and logs

```bash
   kubectl describe pod -n n8n [pod-name]
   kubectl logs -n n8n [pod-name]
```

1. **Database connection issues** : Verify PostgreSQL connectivity

```bash
   kubectl exec -it -n n8n [n8n-pod-name] -- sh -c "nc -zv postgresql 5432"
```

1. **Redis connection issues** : Verify Redis connectivity

```bash
   kubectl exec -it -n n8n [n8n-pod-name] -- sh -c "nc -zv redis-master 6379"
```

1. **Ingress not working** : Check Traefik logs and configuration

```bash
   kubectl logs -n traefik [traefik-pod-name]
   kubectl get ingressroute -n n8n
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License

## 🔗 Links

* [n8n Documentation](https://docs.n8n.io/)
* [Kubernetes Documentation](https://kubernetes.io/docs/)
* [Helm Documentation](https://helm.sh/docs/)
