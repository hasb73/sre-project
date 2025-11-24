# Key Vault Module Variables

variable "key_vault_name" {
  description = "Name of the Azure Key Vault"
  type        = string

  validation {
    condition     = length(var.key_vault_name) >= 3 && length(var.key_vault_name) <= 24
    error_message = "Key Vault name must be between 3 and 24 characters."
  }
}

variable "location" {
  description = "Azure region for the Key Vault"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "sku_name" {
  description = "SKU name for the Key Vault (standard or premium)"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "SKU name must be either 'standard' or 'premium'."
  }
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain deleted Key Vault"
  type        = number
  default     = 90

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "Soft delete retention days must be between 7 and 90."
  }
}

variable "purge_protection_enabled" {
  description = "Enable purge protection for the Key Vault"
  type        = bool
  default     = true
}

variable "network_acls_default_action" {
  description = "Default action for network ACLs (Allow or Deny)"
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Allow", "Deny"], var.network_acls_default_action)
    error_message = "Network ACLs default action must be either 'Allow' or 'Deny'."
  }
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access the Key Vault"
  type        = list(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "List of subnet IDs allowed to access the Key Vault"
  type        = list(string)
  default     = []
}

variable "aks_identity_object_id" {
  description = "Object ID of the AKS managed identity for Key Vault access"
  type        = string
  default     = ""
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostic settings"
  type        = string
  default     = ""
}

# Secret values
variable "postgres_password" {
  description = "PostgreSQL database password (leave empty to auto-generate)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "postgres_replication_password" {
  description = "PostgreSQL replication user password (leave empty to auto-generate)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "jupyterhub_oauth_client_id" {
  description = "JupyterHub OAuth client ID"
  type        = string
  default     = ""
}

variable "jupyterhub_oauth_client_secret" {
  description = "JupyterHub OAuth client secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "jupyterhub_db_password" {
  description = "JupyterHub database password (leave empty to auto-generate)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "jupyterhub_proxy_secret_token" {
  description = "JupyterHub proxy secret token (leave empty to auto-generate)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
