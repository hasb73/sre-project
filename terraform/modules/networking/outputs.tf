# Networking Module Outputs

output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "aks_subnet_id" {
  description = "ID of the AKS subnet"
  value       = azurerm_subnet.aks.id
}

output "database_subnet_id" {
  description = "ID of the database subnet"
  value       = azurerm_subnet.database.id
}

output "services_subnet_id" {
  description = "ID of the services subnet"
  value       = azurerm_subnet.services.id
}

output "aks_nsg_id" {
  description = "ID of the AKS network security group"
  value       = azurerm_network_security_group.aks.id
}

output "database_nsg_id" {
  description = "ID of the database network security group"
  value       = azurerm_network_security_group.database.id
}

output "services_nsg_id" {
  description = "ID of the services network security group"
  value       = azurerm_network_security_group.services.id
}

output "vnet_peering_id" {
  description = "ID of the VNet peering (if created)"
  value       = length(azurerm_virtual_network_peering.to_peer) > 0 ? azurerm_virtual_network_peering.to_peer[0].id : null
}

output "appgw_subnet_id" {
  description = "ID of the Application Gateway subnet"
  value       = azurerm_subnet.appgw.id
}
