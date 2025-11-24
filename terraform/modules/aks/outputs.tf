# AKS Module Outputs

output "cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.id
}

output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint for the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.kube_config[0].host
  sensitive   = true
}

output "cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "kube_config" {
  description = "Kubernetes configuration (raw)"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "kube_config_object" {
  description = "Kubernetes configuration object"
  value       = azurerm_kubernetes_cluster.main.kube_config[0]
  sensitive   = true
}

output "cluster_identity_principal_id" {
  description = "Principal ID of the cluster managed identity"
  value       = azurerm_kubernetes_cluster.main.identity[0].principal_id
}

output "cluster_identity_tenant_id" {
  description = "Tenant ID of the cluster managed identity"
  value       = azurerm_kubernetes_cluster.main.identity[0].tenant_id
}

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet managed identity"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

output "kubelet_identity_client_id" {
  description = "Client ID of the kubelet managed identity"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].client_id
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.aks.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.aks.name
}

output "node_resource_group" {
  description = "Name of the auto-generated resource group for AKS nodes"
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

output "acr_id" {
  description = "ID of the Azure Container Registry"
  value       = var.create_acr ? azurerm_container_registry.acr[0].id : null
}

output "acr_name" {
  description = "Name of the Azure Container Registry"
  value       = var.create_acr ? azurerm_container_registry.acr[0].name : null
}

output "acr_login_server" {
  description = "Login server for the Azure Container Registry"
  value       = var.create_acr ? azurerm_container_registry.acr[0].login_server : null
}

output "namespaces" {
  description = "Created Kubernetes namespaces"
  value = {
    database      = kubernetes_namespace.database.metadata[0].name
    microservices = kubernetes_namespace.microservices.metadata[0].name
    jupyterhub    = kubernetes_namespace.jupyterhub.metadata[0].name
  }
}
