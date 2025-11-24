# JupyterHub Module Outputs

output "release_name" {
  description = "Name of the Helm release"
  value       = helm_release.jupyterhub.name
}

output "release_namespace" {
  description = "Namespace of the Helm release"
  value       = helm_release.jupyterhub.namespace
}

output "release_version" {
  description = "Version of the Helm release"
  value       = helm_release.jupyterhub.version
}

output "release_status" {
  description = "Status of the Helm release"
  value       = helm_release.jupyterhub.status
}

output "chart_version" {
  description = "Version of the JupyterHub chart"
  value       = helm_release.jupyterhub.metadata[0].chart
}
