# Application Gateway Module Outputs

output "appgw_id" {
  description = "ID of the Application Gateway"
  value       = azurerm_application_gateway.main.id
}

output "appgw_name" {
  description = "Name of the Application Gateway"
  value       = azurerm_application_gateway.main.name
}

output "public_ip_address" {
  description = "Public IP address of the Application Gateway"
  value       = azurerm_public_ip.appgw.ip_address
}

output "public_ip_fqdn" {
  description = "FQDN of the Application Gateway public IP"
  value       = azurerm_public_ip.appgw.fqdn
}

output "frontend_ip_configuration_name" {
  description = "Name of the frontend IP configuration"
  value       = "appgw-frontend-ip"
}

output "backend_address_pool_name" {
  description = "Name of the default backend address pool"
  value       = "default-backend-pool"
}
