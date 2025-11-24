#!/bin/bash
# Cleanup Primary Region Infrastructure and Applications
# This script removes all resources from the primary region

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_PRIMARY_DIR="$PROJECT_ROOT/terraform/environments/primary"
LOG_FILE="/tmp/cleanup_primary_$(date +%Y%m%d_%H%M%S).log"

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

print_warning() {
    echo "[WARNING] $1" | tee -a "$LOG_FILE"
}

# Function to delete Kubernetes resources
delete_kubernetes_resources() {
    print_step "Deleting Kubernetes resources from primary cluster..."
    
    # Try to get credentials
    if az aks get-credentials \
        --resource-group "$PRIMARY_RG" \
        --name "$PRIMARY_CONTEXT" \
        --context "$PRIMARY_CONTEXT" \
        --overwrite-existing >> "$LOG_FILE" 2>&1; then
        
        kubectl config use-context "$PRIMARY_CONTEXT" >> "$LOG_FILE" 2>&1
        
        # Delete microservices
        print_info "Deleting microservices..."
        kubectl delete -k "$PROJECT_ROOT/kubernetes/microservices/overlays/primary/" >> "$LOG_FILE" 2>&1 || true
        
        # Delete JupyterHub resources
        print_info "Deleting JupyterHub resources..."
        kubectl delete -f "$PROJECT_ROOT/kubernetes/jupyterhub/jupyterhub-ingress.yaml" >> "$LOG_FILE" 2>&1 || true
        kubectl delete -f "$PROJECT_ROOT/kubernetes/jupyterhub/azcopy-sync-cronjob.yaml" >> "$LOG_FILE" 2>&1 || true
        kubectl delete -f "$PROJECT_ROOT/kubernetes/jupyterhub/azure-files-pv-primary.yaml" >> "$LOG_FILE" 2>&1 || true
        kubectl delete -f "$PROJECT_ROOT/kubernetes/jupyterhub/secret-provider-class-primary.yaml" >> "$LOG_FILE" 2>&1 || true
        
        # Delete PostgreSQL
        print_info "Deleting PostgreSQL..."
        kubectl delete -k "$PROJECT_ROOT/kubernetes/postgresql/primary/" >> "$LOG_FILE" 2>&1 || true
        
        # Delete namespaces (this will delete all resources in them)
        print_info "Deleting namespaces..."
        kubectl delete namespace app >> "$LOG_FILE" 2>&1 || true
        kubectl delete namespace database >> "$LOG_FILE" 2>&1 || true
        kubectl delete namespace jupyterhub >> "$LOG_FILE" 2>&1 || true
        
        print_success "Kubernetes resources deleted"
    else
        print_warning "Could not connect to primary cluster (may already be deleted)"
    fi
}

# Function to run Terraform destroy dry run
terraform_destroy_plan() {
    print_step "Running Terraform destroy dry run for primary region..."
    
    cd "$TERRAFORM_PRIMARY_DIR"
    
    if [ ! -f "terraform.tfstate" ] && ! terraform state list &> /dev/null; then
        print_warning "No Terraform state found, skipping..."
        cd "$PROJECT_ROOT"
        return 1
    fi
    
    print_info "Initializing Terraform..."
    terraform init >> "$LOG_FILE" 2>&1
    
    print_info "Planning destroy (dry run)..."
    echo ""
    echo "=========================================="
    echo "TERRAFORM DESTROY PLAN (Primary Region)"
    echo "=========================================="
    terraform plan -destroy
    echo "=========================================="
    echo ""
    
    cd "$PROJECT_ROOT"
    return 0
}

# Function to destroy Terraform infrastructure
destroy_terraform_infrastructure() {
    print_step "Destroying primary region Terraform infrastructure..."
    
    cd "$TERRAFORM_PRIMARY_DIR"
    
    print_info "Destroying Terraform resources (this may take 10-15 minutes)..."
    terraform destroy -auto-approve >> "$LOG_FILE" 2>&1
    
    print_success "Terraform infrastructure destroyed"
    cd "$PROJECT_ROOT"
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "PRIMARY REGION CLEANUP"
    echo "=========================================="
    echo ""
    echo "WARNING: This will DELETE all resources in the primary region:"
    echo "  - All Kubernetes resources (microservices, JupyterHub, PostgreSQL)"
    echo "  - All namespaces (app, database, jupyterhub)"
    echo "  - AKS cluster"
    echo "  - Virtual Network"
    echo "  - Storage accounts"
    echo "  - Key Vault"
    echo "  - All other Terraform-managed resources"
    echo ""
    echo "This action CANNOT be undone!"
    echo ""
    echo "Log file: $LOG_FILE"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " -r
    echo ""
    if [[ ! $REPLY == "DELETE" ]]; then
        print_info "Cleanup cancelled"
        exit 0
    fi
    
    # Run Terraform destroy dry run first
    if terraform_destroy_plan; then
        echo ""
        read -p "Do you want to proceed with the actual destroy? Type 'YES' to continue: " -r
        echo ""
        if [[ ! $REPLY == "YES" ]]; then
            print_info "Cleanup cancelled after dry run"
            exit 0
        fi
    else
        print_warning "No Terraform state found, will only delete Kubernetes resources"
        echo ""
        read -p "Continue with Kubernetes resource deletion? Type 'YES' to continue: " -r
        echo ""
        if [[ ! $REPLY == "YES" ]]; then
            print_info "Cleanup cancelled"
            exit 0
        fi
    fi
    
    local start_time=$(date +%s)
    
    # Execute cleanup steps
    delete_kubernetes_resources
    
    # Only destroy if there was a state
    if [ -d "$TERRAFORM_PRIMARY_DIR" ] && ([ -f "$TERRAFORM_PRIMARY_DIR/terraform.tfstate" ] || terraform -chdir="$TERRAFORM_PRIMARY_DIR" state list &> /dev/null); then
        destroy_terraform_infrastructure
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    echo ""
    print_success "PRIMARY REGION CLEANUP COMPLETED!"
    print_info "Total time: ${minutes}m ${seconds}s"
    echo ""
    
    print_info "Cleanup log: $LOG_FILE"
    echo ""
}

# Run main function
main "$@"
