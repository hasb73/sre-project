# AKS Module - Azure Kubernetes Service Cluster

# Log Analytics Workspace for Azure Monitor
resource "azurerm_log_analytics_workspace" "aks" {
  name                = "${var.environment}-aks-logs"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = var.tags
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = "${var.environment}-aks-cluster"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.environment}-aks"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {

    name                = "default"
    node_count          = var.node_count
    vm_size             = var.node_vm_size
    vnet_subnet_id      = var.aks_subnet_id
    enable_auto_scaling = var.enable_auto_scaling
    min_count           = var.enable_auto_scaling ? var.min_node_count : null
    max_count           = var.enable_auto_scaling ? var.max_node_count : null
    os_disk_size_gb     = var.os_disk_size_gb
    max_pods            = var.max_pods_per_node
    zones               = var.availability_zones
    os_sku              = "AzureLinux"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    service_cidr      = var.service_cidr
    dns_service_ip    = var.dns_service_ip
  }

  azure_active_directory_role_based_access_control {
    managed                = true
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id
  }

  # AGIC (Application Gateway Ingress Controller) addon
  dynamic "ingress_application_gateway" {
    for_each = var.enable_agic ? [1] : []
    content {
      gateway_id = var.appgw_id
    }
  }

  tags = var.tags
}

# Get current user/client configuration
data "azurerm_client_config" "current" {}

# Azure Kubernetes Service RBAC Cluster Admin role assignment for current user
resource "azurerm_role_assignment" "aks_cluster_admin" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Namespace: database
resource "kubernetes_namespace" "database" {
  metadata {
    name = "database"
    labels = {
      name        = "database"
      environment = var.environment
      managed-by  = "terraform"
    }
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}

# Namespace: microservices
resource "kubernetes_namespace" "microservices" {
  metadata {
    name = "microservices"
    labels = {
      name        = "microservices"
      environment = var.environment
      managed-by  = "terraform"
    }
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}

# Namespace: jupyterhub
resource "kubernetes_namespace" "jupyterhub" {
  metadata {
    name = "jupyterhub"
    labels = {
      name        = "jupyterhub"
      environment = var.environment
      managed-by  = "terraform"
    }
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}

# Azure Container Registry (shared across regions, created in UAE North)
resource "azurerm_container_registry" "acr" {
  count               = var.create_acr ? 1 : 0
  name                = "sreproject01"
  resource_group_name = var.resource_group_name
  location            = "uaenorth"
  sku                 = "Standard"
  admin_enabled       = false

  tags = merge(var.tags, {
    purpose = "shared-container-registry"
  })
}

# Attach ACR to AKS cluster (Pull permission)
resource "azurerm_role_assignment" "aks_acr_pull" {
  count                = var.create_acr ? 1 : 0
  scope                = azurerm_container_registry.acr[0].id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

# Grant current user AcrPush permission
resource "azurerm_role_assignment" "user_acr_push" {
  count                = var.create_acr ? 1 : 0
  scope                = azurerm_container_registry.acr[0].id
  role_definition_name = "AcrPush"
  principal_id         = data.azurerm_client_config.current.object_id
}
