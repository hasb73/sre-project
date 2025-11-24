# Storage Module Outputs

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "backups_container_name" {
  description = "Name of the backups container"
  value       = azurerm_storage_container.backups.name
}

output "recovery_vault_id" {
  description = "ID of the recovery services vault (if backup is enabled)"
  value       = var.enable_backup ? azurerm_recovery_services_vault.main[0].id : null
}

output "recovery_vault_name" {
  description = "Name of the recovery services vault (if backup is enabled)"
  value       = var.enable_backup ? azurerm_recovery_services_vault.main[0].name : null
}

output "backup_policy_id" {
  description = "ID of the backup policy (if backup is enabled)"
  value       = var.enable_backup ? azurerm_backup_policy_file_share.main[0].id : null
}

output "storage_class_name" {
  description = "Name of the storage class for Kubernetes persistent volumes"
  value       = "managed-${lower(var.disk_storage_tier)}"
}

output "disk_storage_tier" {
  description = "Azure Disk storage tier for persistent volumes"
  value       = var.disk_storage_tier
}

output "file_share_name" {
  description = "Name of the JupyterHub users file share"
  value       = azurerm_storage_share.jupyterhub_users.name
}

output "file_share_url" {
  description = "URL of the JupyterHub users file share"
  value       = azurerm_storage_share.jupyterhub_users.url
}
