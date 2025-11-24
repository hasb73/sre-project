# Shared Resources Variables

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "sre-project"
}

variable "shared_resource_group_name" {
  description = "Name of the shared resource group"
  type        = string
  default     = "sre-project-shared-rg"
}

variable "primary_location" {
  description = "Primary Azure region"
  type        = string
  default     = "uaenorth"
}

variable "dr_location" {
  description = "DR Azure region"
  type        = string
  default     = "northeurope"
}

variable "traffic_manager_name" {
  description = "Name of the Traffic Manager profile"
  type        = string
  default     = "sre-project-tm"
}

variable "traffic_manager_dns_name" {
  description = "DNS name for Traffic Manager"
  type        = string
  default     = "sre-project-app"
}

variable "enable_vnet_peering" {
  description = "Enable VNet peering between regions"
  type        = bool
  default     = false
}

variable "primary_resource_group_name" {
  description = "Name of the primary region resource group"
  type        = string
  default     = ""
}

variable "primary_vnet_name" {
  description = "Name of the primary region VNet"
  type        = string
  default     = ""
}

variable "primary_vnet_id" {
  description = "ID of the primary region VNet"
  type        = string
  default     = ""
}

variable "dr_resource_group_name" {
  description = "Name of the DR region resource group"
  type        = string
  default     = ""
}

variable "dr_vnet_name" {
  description = "Name of the DR region VNet"
  type        = string
  default     = ""
}

variable "dr_vnet_id" {
  description = "ID of the DR region VNet"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "Azure Multi-Region DR"
    ManagedBy   = "Terraform"
    Environment = "Shared"
  }
}
