# Primary Region Environment Configuration

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }

  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstateazuredr"
    container_name       = "tfstate"
    key                  = "primary.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

# Kubernetes provider configuration (configured after AKS is created)
provider "kubernetes" {
  host                   = module.aks.cluster_endpoint
  client_certificate     = base64decode(module.aks.kube_config_object.client_certificate)
  client_key             = base64decode(module.aks.kube_config_object.client_key)
  cluster_ca_certificate = base64decode(module.aks.kube_config_object.cluster_ca_certificate)
}

# Helm provider configuration (configured after AKS is created)
provider "helm" {
  kubernetes {
    host                   = module.aks.cluster_endpoint
    client_certificate     = base64decode(module.aks.kube_config_object.client_certificate)
    client_key             = base64decode(module.aks.kube_config_object.client_key)
    cluster_ca_certificate = base64decode(module.aks.kube_config_object.cluster_ca_certificate)
  }
}

# Resource group for primary region
resource "azurerm_resource_group" "primary" {
  name     = var.resource_group_name
  location = var.location

  tags = var.tags
}

# Networking module
module "networking" {
  source = "../../modules/networking"

  environment                         = "primary"
  location                            = var.location
  resource_group_name                 = azurerm_resource_group.primary.name
  vnet_address_space                  = var.vnet_address_space
  aks_subnet_address_prefix           = var.aks_subnet_address_prefix
  database_subnet_address_prefix      = var.database_subnet_address_prefix
  services_subnet_address_prefix      = var.services_subnet_address_prefix
  appgw_subnet_address_prefix         = var.appgw_subnet_address_prefix
  peer_database_subnet_address_prefix = var.dr_database_subnet_address_prefix

  tags = var.tags
}

# Application Gateway module
module "application_gateway" {
  source = "../../modules/application-gateway"

  environment         = "primary"
  location            = var.location
  resource_group_name = azurerm_resource_group.primary.name
  appgw_subnet_id     = module.networking.appgw_subnet_id

  tags = var.tags
}

# AKS module
module "aks" {
  source = "../../modules/aks"

  environment            = "primary"
  location               = var.location
  resource_group_name    = azurerm_resource_group.primary.name
  aks_subnet_id          = module.networking.aks_subnet_id
  kubernetes_version     = var.kubernetes_version
  node_count             = var.aks_node_count
  node_vm_size           = var.aks_node_vm_size
  enable_auto_scaling    = var.enable_auto_scaling
  min_node_count         = var.min_node_count
  max_node_count         = var.max_node_count
  service_cidr           = var.service_cidr
  dns_service_ip         = var.dns_service_ip
  admin_group_object_ids = var.admin_group_object_ids
  create_acr             = true   # Create ACR only in primary region
  enable_agic            = true   # Enable AGIC addon
  appgw_id               = module.application_gateway.appgw_id

  tags = var.tags
}

# Storage module
module "storage" {
  source = "../../modules/storage"

  environment            = "primary"
  location               = var.location
  resource_group_name    = azurerm_resource_group.primary.name
  storage_account_suffix = var.storage_account_suffix
  account_tier           = var.storage_account_tier
  replication_type       = var.storage_replication_type
  blob_retention_days    = var.blob_retention_days

  tags = var.tags
}

# Key Vault module
module "keyvault" {
  source = "../../modules/keyvault"

  key_vault_name      = var.key_vault_name
  location            = var.location
  resource_group_name = azurerm_resource_group.primary.name

  # AKS managed identity for CSI driver access
  aks_identity_object_id = module.aks.kubelet_identity_object_id

  # Network security - allow access from AKS and services subnets
  network_acls_default_action = var.key_vault_network_acls_default_action
  allowed_subnet_ids = [
    module.networking.aks_subnet_id,
    module.networking.services_subnet_id
  ]

  # Monitoring
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # Optional: Provide custom secret values via variables
  jupyterhub_oauth_client_id     = var.jupyterhub_oauth_client_id
  jupyterhub_oauth_client_secret = var.jupyterhub_oauth_client_secret

  tags = var.tags
}

# JupyterHub module
module "jupyterhub" {
  source = "../../modules/jupyterhub"

  environment        = "primary"
  namespace          = "jupyterhub"
  namespace_name     = module.aks.namespaces.jupyterhub
  jupyterhub_version = var.jupyterhub_version
  values_file_path   = "../../../kubernetes/jupyterhub/values-primary.yaml"

  depends_on = [
    module.aks,
    module.keyvault
  ]
}
