# JupyterHub Terraform Implementation

This document describes the Terraform implementation for deploying JupyterHub using Helm.

## Summary

JupyterHub is now deployed using Terraform with the Helm provider, ensuring consistent and reproducible deployments across both Primary and DR regions.

---

## Module Structure

### JupyterHub Module (`terraform/modules/jupyterhub/`)

#### Resources:
- **Helm Release** - Deploys JupyterHub chart from official repository

#### Features:
- ✅ Automated deployment using Helm
- ✅ Environment-specific values files
- ✅ Waits for resources to be ready
- ✅ Integrated with AKS authentication
- ✅ Depends on namespace creation

#### Configuration:
```hcl
resource "helm_release" "jupyterhub" {
  name       = "jupyterhub"
  repository = "https://hub.jupyter.org/helm-chart/"
  chart      = "jupyterhub"
  version    = "3.3.7"
  namespace  = "jupyterhub"
  
  wait          = true
  wait_for_jobs = true
  timeout       = 600
}
```

---

## Environment Configuration

### Primary Region

**Module Call:**
```hcl
module "jupyterhub" {
  source = "../../modules/jupyterhub"

  environment                 = "primary"
  namespace                   = "jupyterhub"
  namespace_name              = module.aks.namespaces.jupyterhub
  jupyterhub_version          = "3.3.7"
  values_file_path            = "../../kubernetes/jupyterhub/values-primary.yaml"
  kube_host                   = module.aks.cluster_endpoint
  kube_client_certificate     = module.aks.kube_config_object.client_certificate
  kube_client_key             = module.aks.kube_config_object.client_key
  kube_cluster_ca_certificate = module.aks.kube_config_object.cluster_ca_certificate
}
```

**Values File:** `kubernetes/jupyterhub/values-primary.yaml`

### DR Region

**Module Call:**
```hcl
module "jupyterhub" {
  source = "../../modules/jupyterhub"

  environment                 = "dr"
  namespace                   = "jupyterhub"
  namespace_name              = module.aks.namespaces.jupyterhub
  jupyterhub_version          = "3.3.7"
  values_file_path            = "../../kubernetes/jupyterhub/values-dr.yaml"
  kube_host                   = module.aks.cluster_endpoint
  kube_client_certificate     = module.aks.kube_config_object.client_certificate
  kube_client_key             = module.aks.kube_config_object.client_key
  kube_cluster_ca_certificate = module.aks.kube_config_object.cluster_ca_certificate
}
```

**Values File:** `kubernetes/jupyterhub/values-dr.yaml`

---

## Dependencies

### Module Dependencies:
1. **AKS Module** - Cluster must exist
2. **Namespace** - jupyterhub namespace must be created
3. **Key Vault** - Secrets must be available

### Dependency Chain:
```
Networking → AKS → Namespaces → Key Vault → JupyterHub
```

---

## Deployment Instructions

### 1. Prerequisites

Ensure values files exist:
```bash
ls -la kubernetes/jupyterhub/values-primary.yaml
ls -la kubernetes/jupyterhub/values-dr.yaml
```

### 2. Initialize Terraform

```bash
# Primary
cd terraform/environments/primary
terraform init -upgrade

# DR
cd ../dr
terraform init -upgrade
```

### 3. Plan Deployment

```bash
# Primary
cd terraform/environments/primary
terraform plan

# DR
cd ../dr
terraform plan
```

### 4. Apply Configuration

```bash
# Primary
cd terraform/environments/primary
terraform apply

# DR
cd ../dr
terraform apply
```

### 5. Verify Deployment

**Check Helm Release:**
```bash
# Primary
az aks get-credentials --resource-group azure-maen-primary-rg --name primary-aks-cluster
helm list -n jupyterhub

# DR
az aks get-credentials --resource-group azure-meun-dr-rg --name dr-aks-cluster
helm list -n jupyterhub
```

**Check Pods:**
```bash
kubectl get pods -n jupyterhub
kubectl get svc -n jupyterhub
kubectl get ingress -n jupyterhub
```

**Check Hub Status:**
```bash
kubectl logs -n jupyterhub -l component=hub --tail=50
```

---

## Values File Management

### Location:
- Primary: `kubernetes/jupyterhub/values-primary.yaml`
- DR: `kubernetes/jupyterhub/values-dr.yaml`

### Key Configurations:

#### Hub Configuration:
```yaml
hub:
  existingSecret: jupyterhub-secrets
  extraEnv:
    JUPYTERHUB_DB_URL:
      valueFrom:
        secretKeyRef:
          name: jupyterhub-secrets
          key: hub.db.url
```

#### Database Configuration:
```yaml
hub:
  db:
    type: postgres
    # URL provided via existingSecret from Key Vault
```

#### Storage Configuration:
```yaml
singleuser:
  storage:
    type: static
    static:
      pvcName: jupyterhub-users-pvc
      subPath: '{username}'
    capacity: 10Gi
```

### Updating Values:

1. Edit the values file:
```bash
vim kubernetes/jupyterhub/values-primary.yaml
```

2. Apply changes:
```bash
cd terraform/environments/primary
terraform apply
```

Terraform will detect changes and upgrade the Helm release.

---

## Outputs

### Module Outputs:
```hcl
output "release_name"      # jupyterhub
output "release_namespace" # jupyterhub
output "release_version"   # Chart version
output "release_status"    # deployed
output "chart_version"     # jupyterhub-3.3.7
```

### Usage:
```bash
terraform output -json | jq '.jupyterhub'
```

---

## Upgrade Process

### Upgrade JupyterHub Version:

1. Update version variable:
```hcl
# terraform/environments/primary/terraform.tfvars
jupyterhub_version = "3.3.8"
```

2. Apply changes:
```bash
terraform apply
```

### Upgrade with New Values:

1. Edit values file:
```bash
vim kubernetes/jupyterhub/values-primary.yaml
```

2. Apply:
```bash
terraform apply
```

Helm will perform a rolling upgrade.

---

## Rollback

### Rollback to Previous Version:

```bash
# Using Helm directly
helm rollback jupyterhub -n jupyterhub

# Or update Terraform to previous version
terraform apply -var="jupyterhub_version=3.3.6"
```

### Complete Removal:

```bash
# Remove JupyterHub module
terraform destroy -target=module.jupyterhub

# Or remove from configuration and apply
terraform apply
```

---

## Troubleshooting

### Issue: Helm release fails to install

**Check logs:**
```bash
kubectl logs -n jupyterhub -l component=hub
```

**Check Helm status:**
```bash
helm status jupyterhub -n jupyterhub
helm get values jupyterhub -n jupyterhub
```

**Solution:** Verify values file path and content
```bash
cat kubernetes/jupyterhub/values-primary.yaml
```

### Issue: Database connection fails

**Check secrets:**
```bash
kubectl get secret jupyterhub-secrets -n jupyterhub
kubectl describe secret jupyterhub-secrets -n jupyterhub
```

**Solution:** Ensure Key Vault secrets are synced
```bash
kubectl get secretproviderclass -n jupyterhub
kubectl describe secretproviderclass azure-keyvault-jupyterhub -n jupyterhub
```

### Issue: Pods not starting

**Check events:**
```bash
kubectl get events -n jupyterhub --sort-by='.lastTimestamp'
```

**Check pod status:**
```bash
kubectl describe pod -n jupyterhub -l component=hub
```

### Issue: Terraform can't connect to cluster

**Solution:** Ensure AKS credentials are valid
```bash
az aks get-credentials --resource-group azure-maen-primary-rg --name primary-aks-cluster --overwrite-existing
```

---

## Comparison: Manual vs Terraform

### Manual Helm Deployment:
```bash
helm repo add jupyterhub https://hub.jupyter.org/helm-chart/
helm repo update
helm install jupyterhub jupyterhub/jupyterhub \
  --namespace jupyterhub \
  --values values-primary.yaml \
  --version 3.3.7
```

**Pros:**
- Quick for testing
- Direct control

**Cons:**
- ❌ Not tracked in Terraform state
- ❌ Manual version management
- ❌ No dependency management
- ❌ Inconsistent across environments

### Terraform Helm Deployment:
```bash
terraform apply
```

**Pros:**
- ✅ Tracked in Terraform state
- ✅ Automated version management
- ✅ Dependency management
- ✅ Consistent across environments
- ✅ Infrastructure as Code
- ✅ Easy rollback

**Cons:**
- Requires Terraform knowledge
- Additional abstraction layer

---

## Best Practices

### 1. Version Pinning
Always pin the JupyterHub version:
```hcl
jupyterhub_version = "3.3.7"
```

### 2. Values File Management
- Keep values files in version control
- Use separate files for each environment
- Document all customizations

### 3. Secret Management
- Never commit secrets to values files
- Use Key Vault for all sensitive data
- Reference secrets via existingSecret

### 4. Testing
Test changes in DR before applying to Primary:
```bash
# Test in DR first
cd terraform/environments/dr
terraform apply

# Verify
kubectl get pods -n jupyterhub

# Then apply to Primary
cd ../primary
terraform apply
```

### 5. Monitoring
Monitor Helm releases:
```bash
helm list -A
kubectl get events -n jupyterhub --watch
```

---

## Integration with Other Components

### Key Vault Integration:
```yaml
hub:
  existingSecret: jupyterhub-secrets
  extraVolumes:
    - name: secrets-store
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: "azure-keyvault-jupyterhub"
```

### Application Gateway Integration:
```yaml
ingress:
  enabled: false  # Managed separately
```

Ingress is created separately via `kubernetes/application-gateway/jupyterhub-ingress.yaml`

### Storage Integration:
```yaml
singleuser:
  storage:
    type: static
    static:
      pvcName: jupyterhub-users-pvc  # Azure Files
```

---

## Cost Considerations

### Helm Release:
- No additional cost (uses existing AKS resources)

### JupyterHub Resources:
- Hub pod: ~0.2 CPU, 512Mi memory
- Proxy pod: ~0.2 CPU, 256Mi memory
- User pods: Configurable (default: 0.5 CPU, 1Gi memory per user)

### Estimated Monthly Cost:
- Base (hub + proxy): ~$15/month
- Per active user: ~$30/month (assuming 24/7 usage)

---

## Next Steps

1. ✅ Deploy JupyterHub via Terraform
2. ✅ Verify Helm release status
3. ✅ Test user login and notebook creation
4. ✅ Configure Ingress for external access
5. ✅ Set up monitoring and alerts
6. ✅ Configure autoscaling for user pods
7. ✅ Implement backup strategy for user data

---

## Additional Resources

- [JupyterHub Helm Chart](https://github.com/jupyterhub/zero-to-jupyterhub-k8s)
- [Terraform Helm Provider](https://registry.terraform.io/providers/hashicorp/helm/latest/docs)
- [JupyterHub Documentation](https://jupyterhub.readthedocs.io/)
- [Zero to JupyterHub Guide](https://z2jh.jupyter.org/)
