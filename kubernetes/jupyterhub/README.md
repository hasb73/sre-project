# JupyterHub Deployment

This directory contains Helm values files for deploying JupyterHub in both primary and DR regions.

## Overview

JupyterHub is deployed using the official `jupyterhub/jupyterhub` Helm chart (version 4.3.1). Each region has its own values file with region-specific configurations.

## Architecture

- **Hub**: Single pod managing user sessions and authentication
- **Proxy**: LoadBalancer service for external access
- **User Pods**: Dynamically spawned with persistent storage
- **Storage**: Azure Disk PVCs for each user (dynamically provisioned)

## Deployment

### Primary Region

```bash
# Add JupyterHub Helm repository
helm repo add jupyterhub https://hub.jupyter.org/helm-chart/
helm repo update

# Deploy to primary region
kubectl config use-context <primary-aks-context>
helm upgrade --install jupyterhub jupyterhub/jupyterhub \
  --namespace jupyterhub \
  --create-namespace \
  --values values-primary.yaml \
  --version 4.3.1
```

### DR Region

```bash
# Deploy to DR region
kubectl config use-context <dr-aks-context>
helm upgrade --install jupyterhub jupyterhub/jupyterhub \
  --namespace jupyterhub \
  --create-namespace \
  --values values-dr.yaml \
  --version 4.3.1
```

## Accessing JupyterHub

After deployment, get the LoadBalancer IP:

```bash
kubectl get service proxy-public -n jupyterhub
```

Access JupyterHub at: `http://<EXTERNAL-IP>`

## User Data Strategy

Each user gets a dedicated PersistentVolumeClaim (PVC) in their region:
- **Primary approach**: Users access their regional JupyterHub instance
- **During failover**: Users redirected to DR JupyterHub
- **Data sync**: Periodic backup with documented restore procedure

**Trade-off**: Users may lose recent work (up to backup interval) but solution remains simple and cost-effective.

## Configuration Details

### Storage
- Storage Class: `managed` (Azure Standard SSD)
- Access Mode: `ReadWriteOnce`
- Storage per user: 4Gi (configurable)

### Authentication
- DummyAuthenticator for demo/testing (replace with production auth)
- Supports Azure AD, OAuth, LDAP, etc.

### Resources
- Hub: 1 CPU, 1Gi memory
- User pods: 1 CPU, 2Gi memory (configurable per user)

## Upgrading

```bash
helm upgrade jupyterhub jupyterhub/jupyterhub \
  --namespace jupyterhub \
  --values values-primary.yaml \
  --version <new-version>
```

## Uninstalling

```bash
helm uninstall jupyterhub --namespace jupyterhub
kubectl delete namespace jupyterhub
```