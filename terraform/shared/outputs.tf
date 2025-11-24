# Shared Resources Outputs

output "shared_resource_group_name" {
  description = "Name of the shared resource group"
  value       = azurerm_resource_group.shared.name
}

output "jupyterhub_traffic_manager_id" {
  description = "ID of the JupyterHub Traffic Manager profile"
  value       = azurerm_traffic_manager_profile.jupyterhub.id
}

output "jupyterhub_traffic_manager_fqdn" {
  description = "FQDN of the JupyterHub Traffic Manager profile"
  value       = azurerm_traffic_manager_profile.jupyterhub.fqdn
}

output "microservices_traffic_manager_id" {
  description = "ID of the Microservices Traffic Manager profile"
  value       = azurerm_traffic_manager_profile.microservices.id
}

output "microservices_traffic_manager_fqdn" {
  description = "FQDN of the Microservices Traffic Manager profile"
  value       = azurerm_traffic_manager_profile.microservices.fqdn
}

output "jupyterhub_access_url" {
  description = "JupyterHub global access URL"
  value       = "http://${azurerm_traffic_manager_profile.jupyterhub.fqdn}/"
}

output "microservices_access_url" {
  description = "Microservices global API access URL"
  value       = "http://${azurerm_traffic_manager_profile.microservices.fqdn}/api/v1/info"
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}
