# Storage Module Variables

variable "environment" {
  description = "Environment name (primary or dr)"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "storage_account_suffix" {
  description = "Suffix for storage account name (must be globally unique)"
  type        = string
}

variable "account_tier" {
  description = "Storage account tier (Standard or Premium)"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "Account tier must be either Standard or Premium."
  }
}

variable "replication_type" {
  description = "Storage account replication type (LRS, ZRS, GRS, GZRS)"
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], var.replication_type)
    error_message = "Replication type must be one of: LRS, ZRS, GRS, GZRS, RAGRS, RAGZRS."
  }
}

variable "blob_retention_days" {
  description = "Number of days to retain deleted blobs and containers"
  type        = number
  default     = 7

  validation {
    condition     = var.blob_retention_days >= 1 && var.blob_retention_days <= 365
    error_message = "Blob retention days must be between 1 and 365."
  }
}

variable "enable_backup" {
  description = "Enable backup policy for storage account"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain daily backups"
  type        = number
  default     = 30

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 9999
    error_message = "Backup retention days must be between 7 and 9999."
  }
}

variable "disk_storage_tier" {
  description = "Storage tier for Azure Disk (Standard_LRS, Premium_LRS, StandardSSD_LRS, UltraSSD_LRS, Premium_ZRS, StandardSSD_ZRS)"
  type        = string
  default     = "Premium_LRS"

  validation {
    condition     = contains(["Standard_LRS", "Premium_LRS", "StandardSSD_LRS", "UltraSSD_LRS", "Premium_ZRS", "StandardSSD_ZRS"], var.disk_storage_tier)
    error_message = "Disk storage tier must be one of: Standard_LRS, Premium_LRS, StandardSSD_LRS, UltraSSD_LRS, Premium_ZRS, StandardSSD_ZRS."
  }
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "file_share_quota_gb" {
  description = "Quota for Azure File Share in GB"
  type        = number
  default     = 100

  validation {
    condition     = var.file_share_quota_gb >= 1 && var.file_share_quota_gb <= 102400
    error_message = "File share quota must be between 1 and 102400 GB."
  }
}
