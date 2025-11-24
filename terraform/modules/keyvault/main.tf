
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Key Vault
resource "azurerm_key_vault" "main" {
  name                       = var.key_vault_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.sku_name
  soft_delete_retention_days = var.soft_delete_retention_days
  purge_protection_enabled   = var.purge_protection_enabled

  # Use access policies instead of RBAC
  enable_rbac_authorization = false

  # Network rules
  network_acls {
    default_action             = var.network_acls_default_action
    bypass                     = "AzureServices"
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }

  tags = var.tags
}

# Access policy for Terraform service principal (for initial secret creation)
resource "azurerm_key_vault_access_policy" "terraform" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Recover",
    "Backup",
    "Restore",
    "Purge"
  ]
}

# Access policy for AKS managed identity
resource "azurerm_key_vault_access_policy" "aks" {
  count        = var.aks_identity_object_id != "" ? 1 : 0
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = var.aks_identity_object_id

  secret_permissions = [
    "Get",
    "List"
  ]
}

# PostgreSQL database password
resource "azurerm_key_vault_secret" "postgres_password" {
  name         = "postgresql-password"
  value        = var.postgres_password != "" ? var.postgres_password : random_password.postgres_password[0].result
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.terraform]

  tags = merge(
    var.tags,
    {
      "rotation-policy" = "90-days"
      "secret-type"     = "database-credential"
    }
  )

  lifecycle {
    ignore_changes = [value]
  }
}

# PostgreSQL replication user password
resource "azurerm_key_vault_secret" "postgres_replication_password" {
  name         = "postgresql-replication-password"
  value        = var.postgres_replication_password != "" ? var.postgres_replication_password : random_password.postgres_replication_password[0].result
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.terraform]

  tags = merge(
    var.tags,
    {
      "rotation-policy" = "90-days"
      "secret-type"     = "database-credential"
    }
  )

  lifecycle {
    ignore_changes = [value]
  }
}

# JupyterHub OAuth client ID
resource "azurerm_key_vault_secret" "jupyterhub_oauth_client_id" {
  name         = "jupyterhub-oauth-client-id"
  value        = var.jupyterhub_oauth_client_id
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.terraform]

  tags = merge(
    var.tags,
    {
      "secret-type" = "oauth-credential"
    }
  )

  lifecycle {
    ignore_changes = [value]
  }
}

# JupyterHub OAuth client secret
resource "azurerm_key_vault_secret" "jupyterhub_oauth_client_secret" {
  name         = "jupyterhub-oauth-client-secret"
  value        = var.jupyterhub_oauth_client_secret
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.terraform]

  tags = merge(
    var.tags,
    {
      "rotation-policy" = "180-days"
      "secret-type"     = "oauth-credential"
    }
  )

  lifecycle {
    ignore_changes = [value]
  }
}

# JupyterHub database password
resource "azurerm_key_vault_secret" "jupyterhub_db_password" {
  name         = "jupyterhub-db-password"
  value        = var.jupyterhub_db_password != "" ? var.jupyterhub_db_password : random_password.jupyterhub_db_password[0].result
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.terraform]

  tags = merge(
    var.tags,
    {
      "rotation-policy" = "90-days"
      "secret-type"     = "database-credential"
    }
  )

  lifecycle {
    ignore_changes = [value]
  }
}

# JupyterHub proxy secret token
resource "azurerm_key_vault_secret" "jupyterhub_proxy_secret_token" {
  name         = "jupyterhub-proxy-secret-token"
  value        = var.jupyterhub_proxy_secret_token != "" ? var.jupyterhub_proxy_secret_token : random_password.jupyterhub_proxy_secret_token[0].result
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.terraform]

  tags = merge(
    var.tags,
    {
      "rotation-policy" = "180-days"
      "secret-type"     = "application-secret"
    }
  )

  lifecycle {
    ignore_changes = [value]
  }
}

# Random password generation for secrets not provided
resource "random_password" "postgres_password" {
  count   = var.postgres_password == "" ? 1 : 0
  length  = 32
  special = true
}

resource "random_password" "postgres_replication_password" {
  count   = var.postgres_replication_password == "" ? 1 : 0
  length  = 32
  special = true
}

resource "random_password" "jupyterhub_db_password" {
  count   = var.jupyterhub_db_password == "" ? 1 : 0
  length  = 32
  special = true
}

resource "random_password" "jupyterhub_proxy_secret_token" {
  count   = var.jupyterhub_proxy_secret_token == "" ? 1 : 0
  length  = 64
  special = false
}

# Diagnostic settings for audit logging
resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  count                      = var.log_analytics_workspace_id != "" ? 1 : 0
  name                       = "${var.key_vault_name}-diagnostics"
  target_resource_id         = azurerm_key_vault.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AuditEvent"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
