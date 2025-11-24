# Storage Module - Storage Accounts and Disk Storage Classes

resource "azurerm_storage_account" "main" {
  name                     = "${var.storage_account_suffix}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = var.account_tier
  account_replication_type = var.replication_type
  account_kind             = "StorageV2"

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.blob_retention_days
    }

    container_delete_retention_policy {
      days = var.blob_retention_days
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "backups" {
  name                  = "backups"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Recovery Services Vault for backups
resource "azurerm_recovery_services_vault" "main" {
  count               = var.enable_backup ? 1 : 0
  name                = "${var.environment}-recovery-vault"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  soft_delete_enabled = true

  tags = var.tags
}

# Backup policy for storage account
resource "azurerm_backup_policy_file_share" "main" {
  count               = var.enable_backup ? 1 : 0
  name                = "${var.environment}-backup-policy"
  resource_group_name = var.resource_group_name
  recovery_vault_name = azurerm_recovery_services_vault.main[0].name

  backup {
    frequency = "Daily"
    time      = "23:00"
  }

  retention_daily {
    count = var.backup_retention_days
  }

  retention_weekly {
    count    = 4
    weekdays = ["Sunday"]
  }

  retention_monthly {
    count    = 12
    weekdays = ["Sunday"]
    weeks    = ["First"]
  }
}

# Backup container for storage account
resource "azurerm_backup_container_storage_account" "main" {
  count               = var.enable_backup ? 1 : 0
  resource_group_name = var.resource_group_name
  recovery_vault_name = azurerm_recovery_services_vault.main[0].name
  storage_account_id  = azurerm_storage_account.main.id
}

# Azure File Share for JupyterHub users
resource "azurerm_storage_share" "jupyterhub_users" {
  name                 = "jupyterhub-users"
  storage_account_name = azurerm_storage_account.main.name
  quota                = var.file_share_quota_gb

  metadata = {
    environment = var.environment
    purpose     = "jupyterhub_user_storage"
    managedby   = "terraform"
  }
}
