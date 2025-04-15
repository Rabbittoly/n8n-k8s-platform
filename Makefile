# n8n Kubernetes Platform Makefile
# This Makefile provides commands for deploying, updating, and managing n8n in Kubernetes

# Load configuration if available
CONFIG_FILE := ./.config/platform.conf
ifneq (,$(wildcard $(CONFIG_FILE)))
include $(CONFIG_FILE)
endif

# Configuration with defaults
NAMESPACE ?= n8n
RELEASE_NAME ?= n8n
POSTGRES_RELEASE ?= postgresql
REDIS_RELEASE ?= redis
KUBECONFIG ?= ~/.kube/config
BACKUP_DIR ?= ./backups

.PHONY: help
help: ## Show this help message
	@echo 'n8n Kubernetes Platform Management'
	@echo ''
	@echo 'Usage:'
	@echo '  make [target]'
	@echo ''
	@echo 'Initial Setup:'
	@echo '  setup                Run the interactive setup wizard'
	@echo '  check-config         Check if configuration exists'
	@echo ''
	@echo 'Deployment:'
	@echo '  deploy               Deploy the complete n8n platform'
	@echo '  uninstall            Uninstall n8n, PostgreSQL, and Redis'
	@echo ''
	@echo 'Operations:'
	@echo '  status               Show status of the n8n deployment'
	@echo '  logs                 Show logs from n8n pods'
	@echo '  update               Update all components to the latest versions'
	@echo '  backup               Create a backup of n8n data'
	@echo '  restore BACKUP_FILE=path/to/backup  Restore from a backup'
	@echo ''
	@echo 'Validation:'
	@echo '  lint                 Run Helm lint on all charts'
	@echo '  dry-run              Run a dry-run installation of all components'
	@echo ''
	@echo 'For more information, see the README.md file.'

.PHONY: check-config
check-config: ## Check if configuration exists
	@if [ ! -f $(CONFIG_FILE) ]; then \
		echo "Configuration not found. Running setup wizard..."; \
		./setup.sh; \
	else \
		echo "Configuration found at $(CONFIG_FILE)"; \
		echo "You can rerun the setup wizard with 'make setup'"; \
	fi

.PHONY: setup
setup: ## Run the interactive setup wizard
	@./setup.sh

.PHONY: check-dependencies
check-dependencies: ## Check if required dependencies are installed
	@echo "Checking dependencies..."
	@which kubectl >/dev/null || (echo "kubectl not found. Please install kubectl" && exit 1)
	@which helm >/dev/null || (echo "helm not found. Please install helm" && exit 1)
	@which openssl >/dev/null || (echo "openssl not found. Please install openssl" && exit 1)
	@echo "All dependencies are installed."

.PHONY: deploy
deploy: check-config check-dependencies ## Deploy the complete n8n platform
	@./scripts/install.sh

.PHONY: status
status: ## Show status of the n8n deployment
	@echo "n8n Pods:"
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=n8n
	@echo ""
	@echo "PostgreSQL Pods:"
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=postgresql || echo "No PostgreSQL pods found"
	@echo ""
	@echo "Redis Pods:"
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=redis || echo "No Redis pods found"
	@echo ""
	@echo "Ingress:"
	@kubectl get ingressroute -n $(NAMESPACE) || echo "No IngressRoute found"

.PHONY: logs
logs: ## Show logs from n8n pods
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=n8n --tail=100 -f

.PHONY: update
update: check-config ## Update all components to the latest versions
	@./scripts/update.sh

.PHONY: backup
backup: ## Create a backup of n8n data
	@echo "Creating backup..."
	@mkdir -p $(BACKUP_DIR)
	@./scripts/backup.sh $(BACKUP_DIR)
	@echo "Backup completed!"

.PHONY: restore
restore: ## Restore from a backup
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "Error: BACKUP_FILE is required. Usage: make restore BACKUP_FILE=path/to/backup"; \
		exit 1; \
	fi
	@echo "Restoring from backup $(BACKUP_FILE)..."
	@./scripts/restore.sh $(BACKUP_FILE)
	@echo "Restore completed!"

.PHONY: uninstall
uninstall: ## Uninstall n8n, PostgreSQL, and Redis
	@echo "Creating final backup before uninstall..."
	@mkdir -p $(BACKUP_DIR)
	@./scripts/backup.sh $(BACKUP_DIR)/pre-uninstall-$(shell date +%Y%m%d-%H%M%S)
	@echo "Uninstalling n8n..."
	@helm uninstall $(RELEASE_NAME) --namespace $(NAMESPACE) || true
	@echo "Uninstalling Redis..."
	@helm uninstall $(REDIS_RELEASE) --namespace $(NAMESPACE) || true
	@echo "Uninstalling PostgreSQL..."
	@helm uninstall $(POSTGRES_RELEASE) --namespace $(NAMESPACE) || true
	@echo "Uninstallation completed."
	@echo "Note: PersistentVolumeClaims and Secrets are not deleted automatically."
	@echo "To completely remove all data, run:"
	@echo "  kubectl delete pvc --all -n $(NAMESPACE)"
	@echo "  kubectl delete secrets --all -n $(NAMESPACE)"

.PHONY: lint
lint: check-dependencies ## Run Helm lint on all charts
	@echo "Linting Helm charts..."
	@helm repo add bitnami https://charts.bitnami.com/bitnami || true
	@helm repo add n8n https://n8n-io.github.io/n8n-helm || true
	@helm repo update
	@echo "Linting PostgreSQL values..."
	@helm lint --values helm/postgresql/values.yaml bitnami/postgresql
	@echo "Linting Redis values..."
	@helm lint --values helm/redis/values.yaml bitnami/redis
	@if [ ! -f helm/n8n/values.yaml ]; then \
		cp helm/n8n/values.example.yaml helm/n8n/values.yaml; \
	fi
	@echo "Linting n8n values..."
	@helm lint --values helm/n8n/values.yaml n8n/n8n
	@echo "Linting shell scripts..."
	@find ./scripts -type f -name "*.sh" -exec bash -n {} \;
	@echo "Linting completed!"

.PHONY: dry-run
dry-run: check-dependencies ## Run a dry-run installation of all components
	@echo "Running dry-run installation..."
	@helm repo add bitnami https://charts.bitnami.com/bitnami || true
	@helm repo add n8n https://n8n-io.github.io/n8n-helm || true
	@helm repo update
	@echo "Dry-run PostgreSQL installation..."
	@helm upgrade --install --dry-run $(POSTGRES_RELEASE) bitnami/postgresql --namespace $(NAMESPACE) -f helm/postgresql/values.yaml
	@echo "Dry-run Redis installation..."
	@helm upgrade --install --dry-run $(REDIS_RELEASE) bitnami/redis --namespace $(NAMESPACE) -f helm/redis/values.yaml
	@if [ ! -f helm/n8n/values.yaml ]; then \
		cp helm/n8n/values.example.yaml helm/n8n/values.yaml; \
	fi
	@echo "Dry-run n8n installation..."
	@helm upgrade --install --dry-run $(RELEASE_NAME) n8n/n8n --namespace $(NAMESPACE) -f helm/n8n/values.yaml
	@echo "Dry-run completed!"

# Development commands
.PHONY: format-scripts
format-scripts: ## Format shell scripts
	@echo "Formatting shell scripts..."
	@find ./scripts -type f -name "*.sh" -exec shfmt -i 2 -w {} \;
	@echo "Formatting completed!"

.PHONY: check-scripts
check-scripts: ## Check shell scripts for common issues
	@echo "Checking shell scripts..."
	@find ./scripts -type f -name "*.sh" -exec shellcheck {} \;
	@echo "Checking completed!"

