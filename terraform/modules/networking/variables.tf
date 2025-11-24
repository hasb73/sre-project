# Networking Module Variables

variable "environment" {
  description = "Environment name (primary or dr)"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the VNet"
  type        = string
}

variable "aks_subnet_address_prefix" {
  description = "Address prefix for AKS subnet"
  type        = string
}

variable "database_subnet_address_prefix" {
  description = "Address prefix for database subnet"
  type        = string
}

variable "services_subnet_address_prefix" {
  description = "Address prefix for services subnet"
  type        = string
}

variable "peer_database_subnet_address_prefix" {
  description = "Address prefix of peer region database subnet for NSG rules"
  type        = string
  default     = ""
}

variable "peer_vnet_id" {
  description = "ID of the peer region VNet for VNet peering"
  type        = string
  default     = ""
}

variable "peer_environment" {
  description = "Environment name of peer region (for peering name)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "appgw_subnet_address_prefix" {
  description = "Address prefix for Application Gateway subnet"
  type        = string
}
