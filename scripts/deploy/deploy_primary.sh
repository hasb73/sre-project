#!/bin/bash
# Deploy Primary Region Infrastructure and Applications

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_PRIMARY_DIR="$PROJECT_ROOT/terraform/environments/primary"
TERRAFORM_SHARED_DIR="$PROJECT_ROOT/terraform/shared"
LOG_FILE="/tmp/deploy_primary_$(date +%Y%m%d_%H%M%S).log"

# Deployment settings
PRIMARY_CONTEXT="primary-aks-cluster"
PRIMARY_RG="azure-maen-primary-rg"

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

# Function to check prerequisites
check_prerequisites() {
    print_step "Checking prerequisites..."
    
    local missing_tools=()
    
    if ! command -v az &> /dev/null; then
        missing_tools+=("azure-cli")
    fi
    
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v kustomize &> /dev/null; then
        missing_tools+=("kustomize")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check Azure CLI authentication
    if ! az account show &> /dev/null; then
        print_error "Not authenticated with Azure CLI. Please run: az login"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to validate Terraform backend
validate_terraform_backend() {
    print_step "Validating Terraform backend..."
    
    local backend_rg="terraform-state-rg"
    local backend_storage="tfstateazuredr"
    local backend_container="tfstate"
    
    if ! az group show --name "$backend_rg" &> /dev/null; then
        print_info "Creating Terraform backend resource group..."
        az group create --name "$backend_rg" --location uaenorth >> "$LOG_FILE" 2>&1
    fi
    
    if ! az storage account show --name "$backend_storage" --resource-group "$backend_rg" &> /dev/null; then
        print_info "Creating storage account: $backend_storage"
        az storage account create \
            --name "$backend_storage" \
            --resource-group "$backend_rg" \
            --location uaenorth \
            --sku Standard_LRS \
            --encryption-services blob \
            --min-tls-version TLS1_2 >> "$LOG_FILE" 2>&1
    fi
    
    if ! az storage container show --name "$backend_container" --account-name "$backend_storage" &> /dev/null; then
        print_info "Creating storage container: $backend_container"
        az storage container create \
            --name "$backend_container" \
            --account-name "$backend_storage" >> "$LOG_FILE" 2>&1
    fi
    
    print_success "Terraform backend validated"
}

# Function to plan shared resources
plan_shared_resources() {
    print_step "Planning shared resources deployment..."
    
    cd "$TERRAFORM_SHARED_DIR"
    
    if terraform state list &> /dev/null; then
        print_info "Shared resources already deployed, skipping..."
        cd "$PROJECT_ROOT"
        return 1
    fi
    
    print_info "Initializing Terraform..."
    terraform init >> "$LOG_FILE" 2>&1
    
    print_info "Running Terraform plan (dry run)..."
    echo ""
    echo "=========================================="
    echo "TERRAFORM PLAN (Shared Resources)"
    echo "=========================================="
    terraform plan
    echo "=========================================="
    echo ""
    
    cd "$PROJECT_ROOT"
    return 0
}

# Function to deploy shared resources
deploy_shared_resources() {
    print_step "Deploying shared resources..."
    
    cd "$TERRAFORM_SHARED_DIR"
    
    print_info "Applying Terraform configuration..."
    terraform apply -auto-approve >> "$LOG_FILE" 2>&1
    
    print_success "Shared resources deployed"
    cd "$PROJECT_ROOT"
}

# Function to plan primary infrastructure
plan_primary_infrastructure() {
    print_step "Planning primary region infrastructure deployment..."
    
    cd "$TERRAFORM_PRIMARY_DIR"
    
    print_info "Initializing Terraform..."
    terraform init >> "$LOG_FILE" 2>&1
    
    print_info "Running Terraform plan (dry run)..."
    echo ""
    echo "=========================================="
    echo "TERRAFORM PLAN (Primary Region)"
    echo "=========================================="
    terraform plan
    echo "=========================================="
    echo ""
    
    cd "$PROJECT_ROOT"
}

# Function to deploy primary infrastructure
deploy_primary_infrastructure() {
    print_step "Deploying primary region infrastructure..."
    
    cd "$TERRAFORM_PRIMARY_DIR"
    
    print_info "Applying Terraform configuration (this may take 10-15 minutes)..."
    terraform apply -auto-approve >> "$LOG_FILE" 2>&1
    
    print_success "Primary infrastructure deployed"
    cd "$PROJECT_ROOT"
}

# Function to configure kubectl
configure_kubectl() {
    print_step "Configuring kubectl for primary AKS cluster..."
    
    print_info "Getting AKS credentials..."
    az aks get-credentials \
        --resource-group "$PRIMARY_RG" \
        --name "$PRIMARY_CONTEXT" \
        --context "$PRIMARY_CONTEXT" \
        --overwrite-existing >> "$LOG_FILE" 2>&1
    
    kubectl config use-context "$PRIMARY_CONTEXT" >> "$LOG_FILE" 2>&1
    
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Failed to connect to AKS cluster"
        return 1
    fi
    
    local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    print_info "Connected to cluster with $node_count node(s)"
    
    print_success "kubectl configured"
}

# Function to deploy PostgreSQL
deploy_postgresql() {
    print_step "Deploying PostgreSQL to primary cluster..."
    
    kubectl config use-context "$PRIMARY_CONTEXT" >> "$LOG_FILE" 2>&1
    
    print_info "Applying PostgreSQL manifests via Kustomize..."
    kubectl apply -k "$PROJECT_ROOT/kubernetes/postgresql/primary/" >> "$LOG_FILE" 2>&1
    
    print_info "Waiting for PostgreSQL pod to be ready..."
    kubectl wait --for=condition=ready pod/postgresql-primary-0 \
        --namespace=database \
        --timeout=300s >> "$LOG_FILE" 2>&1 || true
    
    print_success "PostgreSQL deployed"
}

# Function to deploy JupyterHub resources
deploy_jupyterhub_resources() {
    print_step "Deploying JupyterHub Kubernetes resources..."
    
    kubectl config use-context "$PRIMARY_CONTEXT" >> "$LOG_FILE" 2>&1
    
    cd "$PROJECT_ROOT/kubernetes/jupyterhub"
    
    print_info "Applying JupyterHub ingress..."
    kubectl apply -f jupyterhub-ingress.yaml >> "$LOG_FILE" 2>&1
    
    print_info "Applying AzCopy sync cronjob..."
    kubectl apply -f azcopy-sync-cronjob.yaml >> "$LOG_FILE" 2>&1
    
    print_info "Applying Azure Files PV..."
    kubectl apply -f azure-files-pv-primary.yaml >> "$LOG_FILE" 2>&1
    
    print_info "Applying Secret Provider Class..."
    kubectl apply -f secret-provider-class-primary.yaml >> "$LOG_FILE" 2>&1
    
    print_success "JupyterHub resources deployed"
    cd "$PROJECT_ROOT"
}

# Function to deploy microservices
deploy_microservices() {
    print_step "Deploying microservices to primary cluster..."
    
    kubectl config use-context "$PRIMARY_CONTEXT" >> "$LOG_FILE" 2>&1
    
    # Step 1: Build and push images
    print_info "Building and pushing microservices images..."
    cd "$PROJECT_ROOT/stateless-app"
    
    if [ -f "build-and-push.sh" ]; then
        bash build-and-push.sh >> "$LOG_FILE" 2>&1
        print_success "Microservices images built and pushed"
    else
        print_error "build-and-push.sh not found"
        cd "$PROJECT_ROOT"
        return 1
    fi
    
    cd "$PROJECT_ROOT"
    
    # Step 2: Apply Kustomize manifests
    print_info "Applying microservices manifests via Kustomize..."
    kubectl apply -k "$PROJECT_ROOT/kubernetes/microservices/overlays/primary/" >> "$LOG_FILE" 2>&1
    
    print_info "Waiting for microservices to be ready..."
    kubectl wait --for=condition=available deployment --all \
        --namespace=app \
        --timeout=180s >> "$LOG_FILE" 2>&1 || true
    
    print_success "Microservices deployed"

    print_info "Setup the app namespace"
    sh $PROJECT_ROOT/kubernetes/microservices/scripts/setup-app-namespace.sh

}

# Function to display connection details
display_connection_details() {
    print_step "Gathering connection details..."
    
    echo ""
    echo "=========================================="
    echo "PRIMARY REGION DEPLOYMENT COMPLETE"
    echo "=========================================="
    echo ""
    
    cd "$TERRAFORM_PRIMARY_DIR"
    
    local resource_group=$(terraform output -raw resource_group_name 2>/dev/null || echo "N/A")
    local cluster_name=$(terraform output -raw aks_cluster_name 2>/dev/null || echo "N/A")
    local key_vault_name=$(terraform output -raw key_vault_name 2>/dev/null || echo "N/A")
    
    echo "Azure Resources:"
    echo "  Resource Group: $resource_group"
    echo "  AKS Cluster: $cluster_name"
    echo "  Key Vault: $key_vault_name"
    echo ""
    
    echo "Kubernetes Context: $PRIMARY_CONTEXT"
    echo ""
    
    echo "Deployed Components:"
    echo "  - PostgreSQL (via Kustomize)"
    echo "  - JupyterHub (via Terraform + Helm)"
    echo "  - JupyterHub Ingress"
    echo "  - AzCopy Sync CronJob"
    echo "  - Azure Files PV"
    echo "  - Secret Provider Class"
    echo "  - Microservices (via Kustomize)"
    echo ""
    
    echo "Useful Commands:"
    echo "  - View all pods: kubectl get pods --all-namespaces"
    echo "  - View services: kubectl get services --all-namespaces"
    echo "  - View ingress: kubectl get ingress --all-namespaces"
    echo ""
    
    echo "Deployment Log: $LOG_FILE"
    echo ""
    
    cd "$PROJECT_ROOT"
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "PRIMARY REGION DEPLOYMENT"
    echo "=========================================="
    echo ""
    echo "This script will deploy:"
    echo "  - Shared resources (Traffic Manager)"
    echo "  - Primary region infrastructure (VNet, AKS, Storage, Key Vault)"
    echo "  - PostgreSQL database (via Kustomize)"
    echo "  - JupyterHub resources (Ingress, PV, CronJob, Secrets)"
    echo "  - Microservices (build, push, deploy via Kustomize)"
    echo ""
    echo "Log file: $LOG_FILE"
    echo ""
    
    read -p "Continue with deployment? (yes/no): " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Deployment cancelled"
        exit 0
    fi
    
    # Execute prerequisite checks
    check_prerequisites
    validate_terraform_backend
    
    # Run Terraform plans (dry run)
    echo ""
    print_info "Running Terraform plans (dry run)..."
    echo ""
    
    local deploy_shared=false
    if plan_shared_resources; then
        deploy_shared=true
    fi
    
    plan_primary_infrastructure
    
    # Ask for confirmation after showing plans
    echo ""
    echo "=========================================="
    echo "DRY RUN COMPLETE"
    echo "=========================================="
    echo ""
    print_info "Review the Terraform plans above."
    echo ""
    read -p "Do you want to proceed with the actual deployment? Type 'DEPLOY' to continue: " -r
    echo ""
    if [[ ! $REPLY == "DEPLOY" ]]; then
        print_info "Deployment cancelled after dry run"
        exit 0
    fi
    
    local start_time=$(date +%s)
    
    # Execute deployment steps
    if [ "$deploy_shared" = true ]; then
        deploy_shared_resources
    fi
    deploy_primary_infrastructure
    configure_kubectl
    deploy_postgresql
    deploy_jupyterhub_resources
    deploy_microservices
    display_connection_details
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    echo ""
    print_success "PRIMARY REGION DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo ""

}

# Run main function
main "$@"
