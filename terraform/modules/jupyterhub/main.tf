# JupyterHub Module - Helm Chart Deployment

# JupyterHub Helm Release
resource "helm_release" "jupyterhub" {
  name       = "jupyterhub"
  repository = "https://hub.jupyter.org/helm-chart/"
  chart      = "jupyterhub"
  version    = var.jupyterhub_version
  namespace  = var.namespace

  # Wait for resources to be ready
  wait          = true
  wait_for_jobs = true
  timeout       = 600

  # Values file
  values = [
    file(var.values_file_path)
  ]

  # Override specific values
  set {
    name  = "hub.config.JupyterHub.extra_labels.region"
    value = var.environment
  }

  set {
    name  = "singleuser.extraEnv.REGION"
    value = var.environment
  }

  # Depends on namespace being created
  depends_on = [var.namespace_name]
}
