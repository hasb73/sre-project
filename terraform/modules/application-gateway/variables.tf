# Application Gateway Module Variables

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

variable "appgw_subnet_id" {
  description = "ID of the subnet for Application Gateway"
  type        = string
}

variable "sku_name" {
  description = "SKU name for Application Gateway"
  type        = string
  default     = "Standard_v2"

  validation {
    condition     = contains(["Standard_v2", "WAF_v2"], var.sku_name)
    error_message = "SKU name must be either Standard_v2 or WAF_v2."
  }
}

variable "sku_tier" {
  description = "SKU tier for Application Gateway"
  type        = string
  default     = "Standard_v2"

  validation {
    condition     = contains(["Standard_v2", "WAF_v2"], var.sku_tier)
    error_message = "SKU tier must be either Standard_v2 or WAF_v2."
  }
}

variable "capacity" {
  description = "Capacity (instance count) for Application Gateway"
  type        = number
  default     = 2

  validation {
    condition     = var.capacity >= 1 && var.capacity <= 125
    error_message = "Capacity must be between 1 and 125."
  }
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
