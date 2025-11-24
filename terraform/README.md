# Azure Multi-Region DR - Terraform Infrastructure

This directory contains Terraform configurations for deploying a multi-region disaster recovery infrastructure on Azure.

## Directory Structure

```
terraform/
├── modules/              # Reusable Terraform modules
│   ├── networking/       # VNet, subnets, NSGs, VNet peering
│   ├── aks/              # Azure Kubernetes Service with Log Analytics
│   ├── storage/          # Storage accounts and disk storage
│   └── keyvault/         # Azure Key Vault for secrets management
├── environments/         # Environment-specific configurations
│   ├── primary/          # Primary region (uaenorth)
│   └── dr/               # DR region (northeurope)
└── shared/               # Shared resources (Traffic Manager, VNet peering)
```

## Modules

### Key Vault Module

The Key Vault module provides secure secrets management for the multi-region DR setup.

**Resources Created:**
- Azure Key Vault with RBAC authorization
- Access policies for AKS managed identity
- Secrets for database passwords (auto-generated if not provided)
- Secrets for JupyterHub authentication
- Diagnostic settings for audit logging

**Key Features:**
- Network ACLs restricting access to AKS subnets only
- Automatic password generation for database credentials
- Soft delete and purge protection enabled
- Integration with Azure Monitor for audit logging
- Support for secret rotation with tagged rotation policies

**Module Inputs:**
- `key_vault_name` - Key Vault name (must be globally unique, 3-24 characters)
- `location` - Azure region
- `resource_group_name` - Resource group name
- `aks_identity_object_id` - AKS kubelet identity object ID for access
- `network_acls_default_action` - Default network action (default: Deny)
- `allowed_subnet_ids` - List of subnet IDs allowed to access Key Vault
- `log_analytics_workspace_id` - Log Analytics workspace ID for diagnostics
- `postgres_password` - PostgreSQL password (auto-generated if empty)
- `postgres_replication_password` - Replication password (auto-generated if empty)
- `jupyterhub_oauth_client_id` - JupyterHub OAuth client ID
- `jupyterhub_oauth_client_secret` - JupyterHub OAuth client secret
- `jupyterhub_db_password` - JupyterHub database password (auto-generated if empty)
- `jupyterhub_proxy_secret_token` - JupyterHub proxy token (auto-generated if empty)

**Module Outputs:**
- `key_vault_id` - Key Vault resource ID
- `key_vault_name` - Key Vault name
- `key_vault_uri` - Key Vault URI
- `tenant_id` - Azure AD tenant ID
- Secret names for all managed secrets

**See also:** `docs/secrets-management.md` for detailed secrets management procedures.

### Networking Module

The networking module creates the foundational network infrastructure for each region.

**Resources Created:**
- Virtual Network (VNet) with configurable CIDR blocks
- Three subnets:
  - AKS subnet for Kubernetes nodes
  - Database subnet for PostgreSQL instances
  - Services subnet for additional services
- Network Security Groups (NSGs) for each subnet with security rules
- VNet peering configuration (optional) for cross-region connectivity

**Key Features:**
- Configurable address spaces for VNets and subnets
- NSG rules for database replication (PostgreSQL port 5432)
- NSG rules for application traffic (HTTP/HTTPS)
- Support for VNet peering between primary and DR regions
- Subnet delegation support for Azure services

**Module Inputs:**
- `environment` - Environment name (primary or dr)
- `location` - Azure region
- `resource_group_name` - Resource group name
- `vnet_address_space` - VNet CIDR block
- `aks_subnet_address_prefix` - AKS subnet CIDR
- `database_subnet_address_prefix` - Database subnet CIDR
- `services_subnet_address_prefix` - Services subnet CIDR
- `peer_vnet_id` - (Optional) VNet ID to peer with
- `peer_database_subnet_address_prefix` - Database subnet CIDR of peer region

**Module Outputs:**
- `vnet_id` - Virtual Network ID
- `vnet_name` - Virtual Network name
- `aks_subnet_id` - AKS subnet ID
- `database_subnet_id` - Database subnet ID
- `services_subnet_id` - Services subnet ID
- `aks_nsg_id`, `database_nsg_id`, `services_nsg_id` - NSG IDs
- `vnet_peering_id` - VNet peering ID (if configured)

### AKS Module

The AKS module provisions a fully configured Azure Kubernetes Service cluster with monitoring and security features.

**Resources Created:**
- Log Analytics Workspace for Azure Monitor
- AKS Cluster with configurable node pools
- System-assigned managed identity for the cluster
- Azure CNI networking configuration
- Azure AD integration with RBAC

**Key Features:**
- **Networking:** Azure CNI network plugin with Azure network policy
- **Monitoring:** Integrated Azure Monitor with dedicated Log Analytics workspace
- **Security:** Azure AD managed RBAC with configurable admin groups
- **Scalability:** Support for autoscaling with configurable min/max node counts
- **High Availability:** Support for availability zones
- **Node Configuration:** Configurable VM sizes, OS disk size, and max pods per node

**Module Inputs:**
- `environment` - Environment name (primary or dr)
- `location` - Azure region
- `resource_group_name` - Resource group name
- `aks_subnet_id` - Subnet ID for AKS nodes
- `kubernetes_version` - Kubernetes version (default: 1.27)
- `node_count` - Number of nodes (default: 3)
- `node_vm_size` - VM size for nodes (default: Standard_D2s_v3)
- `enable_auto_scaling` - Enable autoscaling (default: false)
- `min_node_count` - Minimum nodes when autoscaling (default: 1)
- `max_node_count` - Maximum nodes when autoscaling (default: 5)
- `os_disk_size_gb` - OS disk size in GB (default: 128)
- `max_pods_per_node` - Maximum pods per node (default: 30)
- `availability_zones` - Availability zones for node pool (default: [])
- `service_cidr` - Kubernetes service CIDR (default: 10.0.0.0/16)
- `dns_service_ip` - Kubernetes DNS service IP (default: 10.0.0.10)
- `docker_bridge_cidr` - Docker bridge CIDR (default: 172.17.0.1/16)
- `admin_group_object_ids` - Azure AD admin group IDs (default: [])
- `log_retention_days` - Log retention in days (default: 30)

**Module Outputs:**
- `cluster_id` - AKS cluster ID
- `cluster_name` - AKS cluster name
- `cluster_endpoint` - Cluster API endpoint (sensitive)
- `cluster_fqdn` - Cluster FQDN
- `kube_config` - Raw kubeconfig (sensitive)
- `kube_config_object` - Kubeconfig object (sensitive)
- `cluster_identity_principal_id` - Cluster managed identity principal ID
- `cluster_identity_tenant_id` - Cluster managed identity tenant ID
- `kubelet_identity_object_id` - Kubelet managed identity object ID
- `kubelet_identity_client_id` - Kubelet managed identity client ID
- `log_analytics_workspace_id` - Log Analytics workspace ID
- `log_analytics_workspace_name` - Log Analytics workspace name
- `node_resource_group` - Auto-generated node resource group name

## Prerequisites

- Azure CLI (version 2.50+)
- Terraform (version 1.5+)
- Azure subscription with appropriate permissions
- Service principal or managed identity for Terraform

## Backend Configuration

Before deploying, you need to create an Azure Storage Account for Terraform state:

```bash
# Create resource group for Terraform state
az group create --name terraform-state-rg --location uaenorth

# Create storage account (name must be globally unique)
az storage account create \
  --name tfstateazuredr \
  --resource-group terraform-state-rg \
  --location uaenorth \
  --sku Standard_LRS \
  --encryption-services blob

# Create container for state files
az storage container create \
  --name tfstate \
  --account-name tfstateazuredr
```

## Deployment Order

1. **Deploy Shared Resources** (Traffic Manager, Log Analytics)
2. **Deploy Primary Region** (VNet, AKS, Storage)
3. **Deploy DR Region** (VNet, AKS, Storage)
4. **Enable VNet Peering** (Update shared resources)

## Usage

### 1. Deploy Primary Region

Deploy the primary region infrastructure first:

```bash
cd environments/primary
terraform init
terraform plan
terraform apply
```

This will create:
- Resource group in UAE North region
- VNet with three subnets (AKS, database, services)
- Network Security Groups with security rules
- AKS cluster with 3 nodes
- Log Analytics workspace for monitoring
- Storage account for persistent volumes

### 2. Deploy DR Region

Deploy the DR region infrastructure:

```bash
cd ../dr
terraform init
terraform plan
terraform apply
```

This will create:
- Resource group in North Europe region
- VNet with three subnets (AKS, database, services)
- Network Security Groups with security rules
- AKS cluster with 1 node (cost-optimized for DR)
- Log Analytics workspace for monitoring
- Storage account for persistent volumes

### 3. Configure kubectl Access

After deployment, configure kubectl to access both clusters:

```bash
# Get credentials for primary cluster
az aks get-credentials \
  --resource-group azure-maen-primary-rg \
  --name primary-aks-cluster \
  --context primary

# Get credentials for DR cluster
az aks get-credentials \
  --resource-group azure-meun-dr-rg \
  --name dr-aks-cluster \
  --context dr

# Switch between clusters
kubectl config use-context primary
kubectl config use-context dr
```

### 4. Verify Deployment

Verify the infrastructure is deployed correctly:

```bash
# Check primary cluster
kubectl config use-context primary
kubectl get nodes
kubectl get namespaces

# Check DR cluster
kubectl config use-context dr
kubectl get nodes
kubectl get namespaces

# View Azure Monitor logs
az monitor log-analytics workspace show \
  --resource-group azure-maen-primary-rg \
  --workspace-name primary-aks-logs
```

## Customization

### Environment Variables

Edit the `variables.tf` files in each environment to customize default values:

**Network Configuration:**
- `vnet_address_space` - VNet CIDR block (Primary: 10.1.0.0/16, DR: 10.2.0.0/16)
- `aks_subnet_address_prefix` - AKS subnet CIDR
- `database_subnet_address_prefix` - Database subnet CIDR
- `services_subnet_address_prefix` - Services subnet CIDR

**AKS Configuration:**
- `kubernetes_version` - Kubernetes version (default: 1.27)
- `aks_node_count` - Number of nodes (Primary: 3, DR: 1)
- `aks_node_vm_size` - VM size (default: Standard_D2s_v3)
- `enable_auto_scaling` - Enable autoscaling (default: false)
- `min_node_count` - Minimum nodes when autoscaling
- `max_node_count` - Maximum nodes when autoscaling

**Storage Configuration:**
- `storage_account_suffix` - Unique suffix for storage account name
- `storage_account_tier` - Storage tier (default: Standard)
- `storage_replication_type` - Replication type (default: LRS)
- `blob_retention_days` - Blob retention period (default: 7)

**Security Configuration:**
- `admin_group_object_ids` - Azure AD group IDs for cluster admin access

**Tags:**
- `tags` - Resource tags for organization and cost tracking

### Example: Enable Autoscaling

To enable autoscaling for the primary cluster, update `environments/primary/variables.tf`:

```hcl
variable "enable_auto_scaling" {
  description = "Enable autoscaling for AKS node pool"
  type        = bool
  default     = true  # Changed from false
}

variable "min_node_count" {
  description = "Minimum number of nodes when autoscaling is enabled"
  type        = number
  default     = 2  # Changed from 1
}

variable "max_node_count" {
  description = "Maximum number of nodes when autoscaling is enabled"
  type        = number
  default     = 10  # Changed from 5
}
```

## Outputs

After deployment, Terraform will output important resource information:

**Networking Outputs:**
- `vnet_id` - Virtual Network ID
- `vnet_name` - Virtual Network name
- `aks_subnet_id` - AKS subnet ID
- `database_subnet_id` - Database subnet ID
- `services_subnet_id` - Services subnet ID

**AKS Outputs:**
- `cluster_id` - AKS cluster ID
- `cluster_name` - AKS cluster name
- `cluster_endpoint` - Cluster API endpoint (sensitive)
- `cluster_fqdn` - Cluster FQDN
- `kube_config` - Raw kubeconfig for kubectl access (sensitive)
- `log_analytics_workspace_id` - Log Analytics workspace ID
- `node_resource_group` - Auto-generated resource group for AKS nodes

**Storage Outputs:**
- Storage account IDs and names
- Storage class configurations

To view outputs after deployment:

```bash
cd environments/primary
terraform output

# View sensitive outputs
terraform output -json kube_config | jq -r '.' > ~/.kube/primary-config
```

## Monitoring and Security

### Azure Monitor Integration

Each AKS cluster is integrated with Azure Monitor for comprehensive observability:

- **Container Insights:** Automatic collection of container logs and metrics
- **Log Analytics Workspace:** Dedicated workspace per cluster for log storage
- **Retention Policy:** Configurable log retention (default: 30 days)
- **Metrics:** CPU, memory, network, and disk metrics for nodes and pods

Access logs via Azure Portal or CLI:

```bash
# Query logs using Azure CLI
az monitor log-analytics query \
  --workspace primary-aks-logs \
  --analytics-query "ContainerLog | where TimeGenerated > ago(1h) | limit 100"
```

### Security Features

**Network Security:**
- Network Security Groups (NSGs) with restrictive rules
- Azure CNI for native VNet integration
- Azure Network Policy for pod-to-pod traffic control
- Private subnet isolation for databases

**Identity and Access:**
- Azure AD integration for cluster authentication
- Azure RBAC for Kubernetes authorization
- System-assigned managed identities for cluster and kubelet
- Configurable admin group access via Azure AD groups

**Best Practices:**
- Separate resource groups per environment
- Least privilege access via RBAC
- Network segmentation with dedicated subnets
- Encrypted storage for Terraform state

## State Management

Terraform state is stored in Azure Storage with:
- Separate state files for each environment (primary.terraform.tfstate, dr.terraform.tfstate)
- State locking via blob leases to prevent concurrent modifications
- Versioning enabled for state recovery
- Encrypted at rest using Azure Storage encryption

## Cleanup

To destroy resources (in reverse order of creation):

```bash
# Destroy DR region first
cd environments/dr
terraform destroy -auto-approve

# Destroy primary region
cd ../primary
terraform destroy -auto-approve

# Destroy shared resources (if applicable)
cd ../../shared
terraform destroy -auto-approve
```

**Important:** Destroying AKS clusters will also delete:
- All Kubernetes workloads and data
- Associated Log Analytics workspaces
- Node resource groups and their resources

## Troubleshooting

### Common Issues

**Issue: Terraform init fails with backend error**
```
Solution: Ensure the Azure Storage account and container exist:
az storage account show --name tfstateazuredr --resource-group terraform-state-rg
```

**Issue: AKS cluster creation fails with quota error**
```
Solution: Check your Azure subscription quotas:
az vm list-usage --location uaenorth --output table
Request quota increase if needed.
```

**Issue: Cannot access AKS cluster with kubectl**
```
Solution: Get fresh credentials:
az aks get-credentials --resource-group azure-maen-primary-rg --name primary-aks-cluster --overwrite-existing
```

**Issue: VNet peering fails**
```
Solution: Ensure both VNets are deployed and address spaces don't overlap.
Check NSG rules allow traffic between regions.
```

**Issue: Log Analytics workspace not receiving data**
```
Solution: Verify the oms_agent is running:
kubectl get pods -n kube-system | grep oms
Check workspace configuration in Azure Portal.
```

### Validation Commands

```bash
# Validate Terraform configuration
terraform validate

# Check Terraform plan without applying
terraform plan

# Verify AKS cluster health
az aks show --resource-group azure-maen-primary-rg --name primary-aks-cluster --query "provisioningState"

# Check node status
kubectl get nodes -o wide

# Verify networking
kubectl get svc -A
kubectl get networkpolicies -A
```

## Additional Resources

- [Azure Kubernetes Service Documentation](https://docs.microsoft.com/azure/aks/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure CNI Networking](https://docs.microsoft.com/azure/aks/configure-azure-cni)
- [Azure Monitor for Containers](https://docs.microsoft.com/azure/azure-monitor/containers/container-insights-overview)
