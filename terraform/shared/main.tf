# Shared Resources - VNet Peering and Traffic Manager

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstateazuredr"
    container_name       = "tfstate"
    key                  = "shared.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

# Resource group for shared resources
resource "azurerm_resource_group" "shared" {
  name     = var.shared_resource_group_name
  location = var.primary_location

  tags = var.tags
}

# Traffic Manager Profile for JupyterHub
resource "azurerm_traffic_manager_profile" "jupyterhub" {
  name                   = "jupyterhub-tm"
  resource_group_name    = azurerm_resource_group.shared.name
  traffic_routing_method = "Priority"

  dns_config {
    relative_name = "jupyterhub"
    ttl           = 10
  }

  monitor_config {
    protocol                     = "HTTP"
    port                         = 80
    path                         = "/hub/login"
    interval_in_seconds          = 30
    timeout_in_seconds           = 10
    tolerated_number_of_failures = 3
  }

  tags = merge(var.tags, {
    application = "jupyterhub"
  })
}

# Traffic Manager Profile for Microservices
resource "azurerm_traffic_manager_profile" "microservices" {
  name                   = "microservices-tm"
  resource_group_name    = azurerm_resource_group.shared.name
  traffic_routing_method = "Priority"

  dns_config {
    relative_name = "microservices"
    ttl           = 10
  }

  monitor_config {
    protocol                     = "HTTP"
    port                         = 80
    path                         = "/api/v1/info"
    interval_in_seconds          = 30
    timeout_in_seconds           = 10
    tolerated_number_of_failures = 3
  }

  tags = merge(var.tags, {
    application = "microservices"
  })
}

# VNet Peering - Primary to DR
resource "azurerm_virtual_network_peering" "primary_to_dr" {
  count                        = var.enable_vnet_peering ? 1 : 0
  name                         = "primary-to-dr-peering"
  resource_group_name          = var.primary_resource_group_name
  virtual_network_name         = var.primary_vnet_name
  remote_virtual_network_id    = var.dr_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
}

# VNet Peering - DR to Primary
resource "azurerm_virtual_network_peering" "dr_to_primary" {
  count                        = var.enable_vnet_peering ? 1 : 0
  name                         = "dr-to-primary-peering"
  resource_group_name          = var.dr_resource_group_name
  virtual_network_name         = var.dr_vnet_name
  remote_virtual_network_id    = var.primary_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.project_name}-logs"
  location            = azurerm_resource_group.shared.location
  resource_group_name = azurerm_resource_group.shared.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = var.tags
}

