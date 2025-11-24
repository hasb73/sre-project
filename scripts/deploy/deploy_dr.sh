#!/bin/bash
# Deploy DR Region Infrastructure and Applications

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DR_DIR="$PROJECT_ROOT/terraform/environments/dr"
TERRAFORM_PRIMARY_DIR="$PROJECT_ROOT/terraform/environments/primary"
LOG_FILE="/tmp/deploy_dr_$(date +%Y%m%d_%H%M%S).log"

# Deployment settings
PRIMARY_CONTEXT="primary-aks-cluster"
DR_CONTEXT="dr-aks-cluster"
PRIMARY_RG="azure-maen-primary-rg"
DR_RG="azure-meun-dr-rg"

# Function to print output
print_info() {
    echo "[INFO] $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo "[ERROR] $1" | tee -a "$LOG_FILE"
}

print_step() {
    echo "[STEP] $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo "[SUCCESS] $1" | tee -a "$LOG_FILE"
}


# Function to plan DR infrastructure
plan_dr_infrastructure() {
    print_step "Planning DR region infrastructure deployment..."
    
    cd "$TERRAFORM_DR_DIR"
    
    print_info "Initializing Terraform..."
    terraform init >> "$LOG_FILE" 2>&1
    
    print_info "Running Terraform plan (dry run)..."
    echo ""
    echo "=========================================="
    echo "TERRAFORM PLAN (DR Region)"
    echo "=========================================="
    terraform plan
    echo "=========================================="
    echo ""
    
    cd "$PROJECT_ROOT"
}

# Function to deploy DR infrastructure
deploy_dr_infrastructure() {
    print_step "Deploying DR region infrastructure..."
    
    cd "$TERRAFORM_DR_DIR"
    
    print_info "Applying Terraform configuration (this may take 10-15 minutes)..."
    terraform apply -auto-approve >> "$LOG_FILE" 2>&1
    
    print_success "DR infrastructure deployed"
    cd "$PROJECT_ROOT"
}

# Function to configure kubectl for DR cluster
configure_kubectl_dr() {
    print_step "Configuring kubectl for DR AKS cluster..."
    
    print_info "Getting AKS credentials..."
    az aks get-credentials \
        --resource-group "$DR_RG" \
        --name "$DR_CONTEXT" \
        --context "$DR_CONTEXT" \
        --overwrite-existing >> "$LOG_FILE" 2>&1
    
    kubectl config use-context "$DR_CONTEXT" >> "$LOG_FILE" 2>&1
    
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Failed to connect to DR AKS cluster"
        return 1
    fi
    
    local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    print_info "Connected to DR cluster with $node_count node(s)"
    
    print_success "kubectl configured for DR cluster"
}

# Function to setup replication user on primary
setup_replication_user() {
    print_step "Setting up replication user on primary database..."
    
    kubectl config use-context "$PRIMARY_CONTEXT" >> "$LOG_FILE" 2>&1
    
    # Get replication password from secret
    local repl_password=$(kubectl get secret postgresql-secret --namespace=database -o jsonpath='{.data.replication-password}' 2>/dev/null | base64 -d)
    
    if [ -z "$repl_password" ]; then
        print_error "Replication password not found in primary cluster secret"
        return 1
    fi
    
    print_info "Creating replication user and slot on primary..."
    
    # Create replication user
    kubectl exec -it postgresql-primary-0 --namespace=database -- psql -U postgres -c "
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'replicator') THEN
                CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '$repl_password';
            END IF;
        END
        \$\$;
    " >> "$LOG_FILE" 2>&1 || true
    
    # Create replication slot
    kubectl exec -it postgresql-primary-0 --namespace=database -- psql -U postgres -c "
        SELECT pg_create_physical_replication_slot('replication_slot_1');
    " >> "$LOG_FILE" 2>&1 || true
    
    # Update pg_hba.conf
    kubectl exec -it postgresql-primary-0 --namespace=database -- bash -c "
        echo 'host replication replicator 10.0.0.0/8 md5' >> /var/lib/postgresql/data/pgdata/pg_hba.conf
        echo 'host replication replicator 10.1.0.0/16 md5' >> /var/lib/postgresql/data/pgdata/pg_hba.conf
        echo 'host replication replicator 10.2.0.0/16 md5' >> /var/lib/postgresql/data/pgdata/pg_hba.conf
    " >> "$LOG_FILE" 2>&1 || true
    
    # Reload PostgreSQL configuration
    kubectl exec -it postgresql-primary-0 --namespace=database -- psql -U postgres -c "SELECT pg_reload_conf();" >> "$LOG_FILE" 2>&1
    
    print_success "Replication user setup completed"
}

# Function to deploy PostgreSQL secondary
deploy_postgresql_secondary() {
    print_step "Deploying PostgreSQL secondary to DR cluster..."
    
    kubectl config use-context "$DR_CONTEXT" >> "$LOG_FILE" 2>&1
    
    print_info "Applying PostgreSQL secondary manifests via Kustomize..."
    kubectl apply -k "$PROJECT_ROOT/kubernetes/postgresql/secondary/" >> "$LOG_FILE" 2>&1
    
    print_info "Waiting for PostgreSQL secondary pod to be ready..."
    kubectl wait --for=condition=ready pod/postgresql-secondary-0 \
        --namespace=database \
        --timeout=600s >> "$LOG_FILE" 2>&1 || true
    
    print_success "PostgreSQL secondary deployed"
}

# Function to deploy JupyterHub resources
deploy_jupyterhub_resources() {
    print_step "Deploying JupyterHub Kubernetes resources to DR..."
    
    kubectl config use-context "$DR_CONTEXT" >> "$LOG_FILE" 2>&1
    
    cd "$PROJECT_ROOT/kubernetes/jupyterhub"
    
    print_info "Applying JupyterHub ingress..."
    kubectl apply -f jupyterhub-ingress.yaml >> "$LOG_FILE" 2>&1
    
    
    print_info "Applying Azure Files PV..."
    kubectl apply -f azure-files-pv-dr.yaml >> "$LOG_FILE" 2>&1
    
    print_info "Applying Secret Provider Class..."
    kubectl apply -f secret-provider-class-dr.yaml >> "$LOG_FILE" 2>&1
    
    print_success "JupyterHub resources deployed"
    cd "$PROJECT_ROOT"
}

# Function to deploy microservices
deploy_microservices() {
    print_step "Deploying microservices to DR cluster..."
    
    kubectl config use-context "$DR_CONTEXT" >> "$LOG_FILE" 2>&1
    
    # Microservices images are already built and pushed from primary deployment
    print_info "Using microservices images from ACR (already pushed from primary)"
    
    # Apply Kustomize manifests for DR
    print_info "Applying microservices manifests via Kustomize..."
    kubectl apply -k "$PROJECT_ROOT/kubernetes/microservices/dr/" >> "$LOG_FILE" 2>&1
    
    print_info "Waiting for microservices to be ready..."
    kubectl wait --for=condition=available deployment --all \
        --namespace=app \
        --timeout=180s >> "$LOG_FILE" 2>&1 || true
    
    print_success "Microservices deployed"

    print_info "Setup the app namespace"
    sh $PROJECT_ROOT/kubernetes/microservices/setup-app-namespace.sh
}

# Function to display connection details
display_connection_details() {
    print_step "Gathering connection details..."
    
    echo ""
    echo "=========================================="
    echo "DR REGION DEPLOYMENT COMPLETE"
    echo "=========================================="
    echo ""
    
    cd "$TERRAFORM_DR_DIR"
    
    local resource_group=$(terraform output -raw resource_group_name 2>/dev/null || echo "N/A")
    local cluster_name=$(terraform output -raw aks_cluster_name 2>/dev/null || echo "N/A")
    local key_vault_name=$(terraform output -raw key_vault_name 2>/dev/null || echo "N/A")
    
    echo "Azure Resources:"
    echo "  Resource Group: $resource_group"
    echo "  AKS Cluster: $cluster_name"
    echo "  Key Vault: $key_vault_name"
    echo ""
    
    echo "Kubernetes Context: $DR_CONTEXT"
    echo ""
    
    echo "Deployed Components:"
    echo "  - PostgreSQL Secondary (via Kustomize)"
    echo "  - JupyterHub (via Terraform + Helm)"
    echo "  - JupyterHub Ingress"
    echo "  - AzCopy Sync CronJob"
    echo "  - Azure Files PV"
    echo "  - Secret Provider Class"
    echo "  - Microservices (via Kustomize)"
    echo ""
    
    echo "Replication Status:"
    kubectl config use-context "$PRIMARY_CONTEXT" >> "$LOG_FILE" 2>&1
    local repl_info=$(kubectl exec postgresql-primary-0 --namespace=database -- psql -U postgres -t -c "
        SELECT application_name, state, sync_state
        FROM pg_stat_replication 
        WHERE application_name = 'secondary';
    " 2>/dev/null || echo "  Not yet established")
    
    if [ -n "$repl_info" ]; then
        echo "$repl_info"
    else
        echo "  Status: Initializing (check again in a few minutes)"
    fi
    echo ""
    
    
    echo "Deployment Log: $LOG_FILE"
    echo ""
    
    cd "$PROJECT_ROOT"
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "DR REGION DEPLOYMENT"
    echo "=========================================="
    echo ""
    echo "This script will deploy:"
    echo "  - DR region infrastructure (VNet, AKS, Storage, Key Vault)"
    echo "  - PostgreSQL secondary database with replication (via Kustomize)"
    echo "  - JupyterHub resources (Ingress, PV, CronJob, Secrets)"
    echo "  - Microservices (deploy via Kustomize)"
    echo ""
    echo "Prerequisites:"
    echo "  - Primary region must be deployed"
    echo "  - Primary PostgreSQL must be operational"
    echo ""
    echo "Log file: $LOG_FILE"
    echo ""
    
    read -p "Continue with DR deployment? (yes/no): " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Deployment cancelled"
        exit 0
    fi
    
    # Execute prerequisite checks
    check_prerequisites
    verify_primary_deployment
    
    # Run Terraform plan (dry run)
    echo ""
    print_info "Running Terraform plan (dry run)..."
    echo ""
    
    plan_dr_infrastructure
    
    # Ask for confirmation after showing plan
    echo ""
    echo "=========================================="
    echo "DRY RUN COMPLETE"
    echo "=========================================="
    echo ""
    print_info "Review the Terraform plan above."
    echo ""
    read -p "Do you want to proceed with the actual deployment? Type 'DEPLOY' to continue: " -r
    echo ""
    if [[ ! $REPLY == "DEPLOY" ]]; then
        print_info "Deployment cancelled after dry run"
        exit 0
    fi
    
    local start_time=$(date +%s)
    
    # Execute deployment steps
    deploy_dr_infrastructure
    configure_kubectl_dr
    setup_replication_user
    deploy_postgresql_secondary
    deploy_jupyterhub_resources
    deploy_microservices
    display_connection_details
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
  

}

# Run main function
main "$@"
