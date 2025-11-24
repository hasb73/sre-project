# JupyterHub Module Variables

variable "environment" {
  description = "Environment name (primary or dr)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for JupyterHub"
  type        = string
  default     = "jupyterhub"
}

variable "namespace_name" {
  description = "Name of the namespace (for dependency)"
  type        = string
}

variable "jupyterhub_version" {
  description = "JupyterHub Helm chart version"
  type        = string
  default     = "4.3.1"
}

variable "values_file_path" {
  description = "Path to the Helm values file"
  type        = string
}
