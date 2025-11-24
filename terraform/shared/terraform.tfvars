# Shared Resources Configuration Values

project_name               = "sre-project"
shared_resource_group_name = "shared-rg"
primary_location           = "uaenorth"
dr_location                = "northeurope"

# Traffic Manager Configuration
traffic_manager_name     = "sre-project-tm"
traffic_manager_dns_name = "sre-project-app"

# VNet Peering Configuration (set to false initially, enable after both regions are deployed)
enable_vnet_peering = true

# Primary Region VNet Information (required when enable_vnet_peering = true)
primary_resource_group_name = "azure-maen-primary-rg"
primary_vnet_name           = "primary-vnet"
primary_vnet_id             = "/subscriptions/6c083348-f38d-4a4f-8523-51354d6b6cc1/resourceGroups/azure-maen-primary-rg/providers/Microsoft.Network/virtualNetworks/primary-vnet"

# DR Region VNet Information (required when enable_vnet_peering = true)
dr_resource_group_name = "azure-meun-dr-rg"
dr_vnet_name           = "dr-vnet"
dr_vnet_id             = "/subscriptions/6c083348-f38d-4a4f-8523-51354d6b6cc1/resourceGroups/azure-meun-dr-rg/providers/Microsoft.Network/virtualNetworks/dr-vnet" 

# Log Analytics Configuration
log_retention_days = 30

# Tags
tags = {
  Project     = "Azure Multi-Region DR"
  ManagedBy   = "Terraform"
  Environment = "Shared"
}
