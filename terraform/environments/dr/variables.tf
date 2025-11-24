# DR Region Variables

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "azure-meun-dr-rg"
}

variable "location" {
  description = "Azure region for DR resources"
  type        = string
  default     = "northeurope"
}

variable "vnet_address_space" {
  description = "Address space for the VNet"
  type        = string
  default     = "10.2.0.0/16"
}

variable "aks_subnet_address_prefix" {
  description = "Address prefix for AKS subnet"
  type        = string
  default     = "10.2.0.0/20"
}

variable "database_subnet_address_prefix" {
  description = "Address prefix for database subnet"
  type        = string
  default     = "10.2.16.0/24"
}

variable "services_subnet_address_prefix" {
  description = "Address prefix for services subnet"
  type        = string
  default     = "10.2.17.0/24"
}

variable "appgw_subnet_address_prefix" {
  description = "Address prefix for Application Gateway subnet"
  type        = string
  default     = "10.2.18.0/24"
}

variable "primary_database_subnet_address_prefix" {
  description = "Address prefix of primary region database subnet for NSG rules"
  type        = string
  default     = "10.1.16.0/24"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.27"
}

variable "aks_node_count" {
  description = "Number of nodes in the AKS cluster"
  type        = number
  default     = 1
}

variable "aks_node_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "enable_auto_scaling" {
  description = "Enable autoscaling for AKS node pool"
  type        = bool
  default     = false
}

variable "min_node_count" {
  description = "Minimum number of nodes when autoscaling is enabled"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of nodes when autoscaling is enabled"
  type        = number
  default     = 3
}

variable "service_cidr" {
  description = "CIDR for Kubernetes services"
  type        = string
  default     = "10.0.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address for Kubernetes DNS service"
  type        = string
  default     = "10.0.0.10"
}

variable "admin_group_object_ids" {
  description = "Azure AD group object IDs for cluster admin access"
  type        = list(string)
  default     = []
}

variable "storage_account_suffix" {
  description = "Suffix for storage account name (must be globally unique)"
  type        = string
  default     = "drst01"
}

variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
}

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
}

variable "blob_retention_days" {
  description = "Number of days to retain deleted blobs"
  type        = number
  default     = 7
}

variable "key_vault_name" {
  description = "Name of the Azure Key Vault (must be globally unique, 3-24 characters)"
  type        = string
  default     = "kv-azdr-dr"
}

variable "key_vault_network_acls_default_action" {
  description = "Default action for Key Vault network ACLs"
  type        = string
  default     = "Deny"
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for Key Vault diagnostics"
  type        = string
  default     = ""
}

variable "jupyterhub_oauth_client_id" {
  description = "JupyterHub OAuth client ID (optional)"
  type        = string
  default     = ""
}

variable "jupyterhub_oauth_client_secret" {
  description = "JupyterHub OAuth client secret (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "SRE Project - Multi Region DR"
    Environment = "Primary"
    SupportDL = "DL-EDA"
    Owner = "hasan.banswarawala"
  }
}

variable "jupyterhub_version" {
  description = "JupyterHub Helm chart version"
  type        = string
  default     = "4.3.1"
}
