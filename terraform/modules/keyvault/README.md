# Azure Key Vault Terraform Module

This module creates an Azure Key Vault for secure secrets management in the multi-region DR setup.

## Features

- Azure Key Vault with RBAC authorization
- Network ACLs for secure access control
- Automatic secret generation for database passwords
- Access policies for AKS managed identity
- Audit logging via Azure Monitor
- Soft delete and purge protection

## Secrets Managed

The module creates and manages the following secrets:

1. **postgresql-password**: Main PostgreSQL database password
2. **postgresql-replication-password**: PostgreSQL replication user password
3. **jupyterhub-oauth-client-id**: JupyterHub OAuth client ID
4. **jupyterhub-oauth-client-secret**: JupyterHub OAuth client secret
5. **jupyterhub-db-password**: JupyterHub database password
6. **jupyterhub-proxy-secret-token**: JupyterHub proxy secret token

## Usage

```hcl
module "keyvault" {
  source = "../../modules/keyvault"

  key_vault_name      = "kv-myapp-primary"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.primary.name
  
  # AKS managed identity for CSI driver
  aks_identity_object_id = module.aks.kubelet_identity_object_id
  
  # Network security
  network_acls_default_action = "Deny"
  allowed_subnet_ids = [
    module.networking.aks_subnet_id,
    module.networking.services_subnet_id
  ]
  
  # Monitoring
  log_analytics_workspace_id = var.log_analytics_workspace_id
  
  # Optional: Provide custom secret values
  jupyterhub_oauth_client_id     = var.jupyterhub_oauth_client_id
  jupyterhub_oauth_client_secret = var.jupyterhub_oauth_client_secret
  
  tags = var.tags
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| azurerm | ~> 3.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| key_vault_name | Name of the Azure Key Vault | `string` | n/a | yes |
| location | Azure region for the Key Vault | `string` | n/a | yes |
| resource_group_name | Name of the resource group | `string` | n/a | yes |
| sku_name | SKU name for the Key Vault | `string` | `"standard"` | no |
| soft_delete_retention_days | Number of days to retain deleted Key Vault | `number` | `90` | no |
| purge_protection_enabled | Enable purge protection | `bool` | `true` | no |
| network_acls_default_action | Default action for network ACLs | `string` | `"Deny"` | no |
| allowed_ip_ranges | List of IP ranges allowed to access | `list(string)` | `[]` | no |
| allowed_subnet_ids | List of subnet IDs allowed to access | `list(string)` | `[]` | no |
| aks_identity_object_id | Object ID of the AKS managed identity | `string` | `""` | no |
| log_analytics_workspace_id | Log Analytics workspace ID | `string` | `""` | no |
| postgres_password | PostgreSQL password (auto-generated if empty) | `string` | `""` | no |
| postgres_replication_password | PostgreSQL replication password | `string` | `""` | no |
| jupyterhub_oauth_client_id | JupyterHub OAuth client ID | `string` | `""` | no |
| jupyterhub_oauth_client_secret | JupyterHub OAuth client secret | `string` | `""` | no |
| jupyterhub_db_password | JupyterHub database password | `string` | `""` | no |
| jupyterhub_proxy_secret_token | JupyterHub proxy secret token | `string` | `""` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| key_vault_id | ID of the Key Vault |
| key_vault_name | Name of the Key Vault |
| key_vault_uri | URI of the Key Vault |
| tenant_id | Azure AD tenant ID |
| postgres_password_secret_name | Name of the PostgreSQL password secret |
| postgres_replication_password_secret_name | Name of the PostgreSQL replication password secret |
| jupyterhub_oauth_client_id_secret_name | Name of the JupyterHub OAuth client ID secret |
| jupyterhub_oauth_client_secret_secret_name | Name of the JupyterHub OAuth client secret |
| jupyterhub_db_password_secret_name | Name of the JupyterHub database password secret |
| jupyterhub_proxy_secret_token_secret_name | Name of the JupyterHub proxy secret token |

## Security Considerations

1. **Network Isolation**: By default, the Key Vault denies all network access except from specified subnets
2. **RBAC Authorization**: Uses Azure RBAC for fine-grained access control
3. **Audit Logging**: All access is logged to Azure Monitor for compliance
4. **Soft Delete**: Protects against accidental deletion with 90-day retention
5. **Purge Protection**: Prevents permanent deletion during retention period

## Secret Rotation

Secrets are tagged with rotation policies:
- Database credentials: 90 days
- OAuth credentials: 180 days
- Application secrets: 180 days

See the main documentation for secret rotation procedures.
