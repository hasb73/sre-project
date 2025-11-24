# Primary Region Configuration Values

resource_group_name = "azure-maen-primary-rg"
location            = "uaenorth"

# Network Configuration
vnet_address_space                = "10.1.0.0/16"
aks_subnet_address_prefix         = "10.1.0.0/20"
database_subnet_address_prefix    = "10.1.16.0/24"
services_subnet_address_prefix    = "10.1.17.0/24"
appgw_subnet_address_prefix       = "10.1.18.0/24"
dr_database_subnet_address_prefix = "10.2.16.0/24"

# AKS Configuration
kubernetes_version  = "1.32"
aks_node_count      = 2
aks_node_vm_size    = "Standard_D2s_v3"
enable_auto_scaling = true
min_node_count      = 1
max_node_count      = 5

# Kubernetes Service Configuration
service_cidr   = "10.0.0.0/16"
dns_service_ip = "10.0.0.10"

# Storage Configuration
storage_account_suffix   = "primaryst01"
storage_account_tier     = "Standard"
storage_replication_type = "LRS"
blob_retention_days      = 7

# Key Vault Configuration
key_vault_name                        = "kv-sreproject-primary-01"
key_vault_network_acls_default_action = "Allow"  # Temporarily allow all for initial setup
log_analytics_workspace_id            = ""

# Tags
tags = {
  Project     = "SRE Project - Multi Region DR"
  Environment = "Primary"
  SupportDL = "DL-EDA"
  Owner = "hasan.banswarawal"
}
