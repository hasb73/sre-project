# Primary Region Outputs

output "resource_group_name" {
  description = "Name of the primary resource group"
  value       = azurerm_resource_group.primary.name
}

output "vnet_id" {
  description = "ID of the primary VNet"
  value       = module.networking.vnet_id
}

output "vnet_name" {
  description = "Name of the primary VNet"
  value       = module.networking.vnet_name
}

output "aks_cluster_name" {
  description = "Name of the primary AKS cluster"
  value       = module.aks.cluster_name
}

output "aks_cluster_endpoint" {
  description = "Endpoint for the primary AKS cluster"
  value       = module.aks.cluster_endpoint
  sensitive   = true
}

output "kube_config" {
  description = "Kubernetes configuration for primary cluster"
  value       = module.aks.kube_config
  sensitive   = true
}

output "storage_account_name" {
  description = "Name of the primary storage account"
  value       = module.storage.storage_account_name
}

output "storage_account_id" {
  description = "ID of the primary storage account"
  value       = module.storage.storage_account_id
}

output "key_vault_id" {
  description = "ID of the primary Key Vault"
  value       = module.keyvault.key_vault_id
}

output "key_vault_name" {
  description = "Name of the primary Key Vault"
  value       = module.keyvault.key_vault_name
}

output "key_vault_uri" {
  description = "URI of the primary Key Vault"
  value       = module.keyvault.key_vault_uri
}

output "tenant_id" {
  description = "Azure AD tenant ID"
  value       = module.keyvault.tenant_id
}

output "kubelet_identity_client_id" {
  description = "Client ID of the AKS kubelet managed identity"
  value       = module.aks.kubelet_identity_client_id
}
