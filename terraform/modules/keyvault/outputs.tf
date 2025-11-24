# Key Vault Module Outputs

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "tenant_id" {
  description = "Azure AD tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "postgres_password_secret_name" {
  description = "Name of the PostgreSQL password secret in Key Vault"
  value       = azurerm_key_vault_secret.postgres_password.name
}

output "postgres_replication_password_secret_name" {
  description = "Name of the PostgreSQL replication password secret in Key Vault"
  value       = azurerm_key_vault_secret.postgres_replication_password.name
}

output "jupyterhub_oauth_client_id_secret_name" {
  description = "Name of the JupyterHub OAuth client ID secret in Key Vault"
  value       = azurerm_key_vault_secret.jupyterhub_oauth_client_id.name
}

output "jupyterhub_oauth_client_secret_secret_name" {
  description = "Name of the JupyterHub OAuth client secret in Key Vault"
  value       = azurerm_key_vault_secret.jupyterhub_oauth_client_secret.name
}

output "jupyterhub_db_password_secret_name" {
  description = "Name of the JupyterHub database password secret in Key Vault"
  value       = azurerm_key_vault_secret.jupyterhub_db_password.name
}

output "jupyterhub_proxy_secret_token_secret_name" {
  description = "Name of the JupyterHub proxy secret token in Key Vault"
  value       = azurerm_key_vault_secret.jupyterhub_proxy_secret_token.name
}
