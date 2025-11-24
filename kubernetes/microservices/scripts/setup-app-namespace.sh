#!/bin/bash
# Setup Infrastructure for Microservices
# This script creates namespaces, ACRs, and database setup

set -e

echo "=== Microservices Infrastructure Setup ==="
echo ""

# Configuration
PRIMARY_CLUSTER="primary-aks-cluster"
DR_CLUSTER="dr-aks-cluster"
PRIMARY_RG="azure-maen-primary-rg"
DR_RG="azure-meun-dr-rg"
PRIMARY_ACR="sreproject01"
PRIMARY_LOCATION="uaenorth"

# Step 1: Create ACR
echo "Step 1: Creating Azure Container Registry in UAE North..."
echo ""

# Create single ACR in UAE North
echo "Creating ACR: $PRIMARY_ACR in $PRIMARY_LOCATION..."
az acr create \
  --resource-group $PRIMARY_RG \
  --name $PRIMARY_ACR \
  --sku Standard \
  --location $PRIMARY_LOCATION \
  --admin-enabled true

echo "✓ ACR created: $PRIMARY_ACR.azurecr.io"
echo ""

# Step 2: Attach ACR to both AKS clusters
echo "Step 2: Attaching ACR to both AKS clusters..."
echo ""

echo "Attaching ACR to Primary AKS cluster..."
az aks update \
  --resource-group $PRIMARY_RG \
  --name $PRIMARY_CLUSTER \
  --attach-acr $PRIMARY_ACR

echo "✓ ACR attached to Primary AKS"
echo ""

echo "Attaching ACR to DR AKS cluster..."
az aks update \
  --resource-group $DR_RG \
  --name $DR_CLUSTER \
  --attach-acr $PRIMARY_ACR

echo "✓ ACR attached to DR AKS"
echo ""

# Step 4: Get AKS credentials and create app namespace
echo "Step 3: Getting AKS credentials and creating app namespace..."
echo ""

# Get Primary cluster credentials
echo "Getting Primary AKS credentials..."
az aks get-credentials \
  --resource-group $PRIMARY_RG \
  --name $PRIMARY_CLUSTER \
  --overwrite-existing

echo "✓ Primary AKS credentials configured"
echo ""

# Create app namespace in Primary
echo "Creating app namespace in Primary cluster..."
kubectl create namespace app --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace app name=app environment=production team=sre --overwrite

echo "✓ App namespace created in Primary cluster"
echo ""

# Step 5: Update network policies in Primary
echo "Step 4: Updating database network policies in Primary..."
kubectl apply -f kubernetes/postgresql/network-policy.yaml

echo "✓ Network policies updated in Primary"
echo ""

# Get DR cluster credentials
echo "Getting DR AKS credentials..."
az aks get-credentials \
  --resource-group $DR_RG \
  --name $DR_CLUSTER \
  --overwrite-existing

echo "✓ DR AKS credentials configured"
echo ""

# Create app namespace in DR
echo "Creating app namespace in DR cluster..."
kubectl create namespace app --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace app name=app environment=production team=sre --overwrite

echo "✓ App namespace created in DR cluster"
echo ""

# Update network policies in DR
echo "Updating database network policies in DR..."
kubectl apply -f kubernetes/postgresql/network-policy.yaml

echo "✓ Network policies updated in DR"
echo ""

# Step 6: Create database user and schema
echo "Step 5: Setting up database..."
echo ""

read -p "Do you want to initialize the database schema? (yes/no): " -r
if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Initializing database in Primary cluster..."
    
    # Get Primary cluster credentials again
    az aks get-credentials \
      --resource-group $PRIMARY_RG \
      --name $PRIMARY_CLUSTER \
      --overwrite-existing
    
    # Copy init script to PostgreSQL pod
    kubectl cp microservices/init-db.sql database/postgresql-primary-0:/tmp/init-db.sql
    
    # Create appuser and appdb using separate commands
    echo "Creating database user and database..."
    # kubectl exec -n database postgresql-primary-0 -- psql -U postgres -c "CREATE USER appuser WITH PASSWORD 'changeme-use-azure-keyvault';"
    # kubectl exec -n database postgresql-primary-0 -- psql -U postgres -c "CREATE DATABASE appdb OWNER appuser;"
    kubectl exec -n database postgresql-primary-0 -- psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE appdb TO appuser;"
    
    # Run init script
    echo "Running database initialization script..."
    kubectl exec -n database postgresql-primary-0 -- psql -U postgres -d appdb -f /tmp/init-db.sql
    
    # Grant permissions using separate commands
    echo "Granting permissions..."
    kubectl exec -n database postgresql-primary-0 -- psql -U postgres -d appdb -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO appuser;"
    kubectl exec -n database postgresql-primary-0 -- psql -U postgres -d appdb -c "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO appuser;"
    kubectl exec -n database postgresql-primary-0 -- psql -U postgres -d appdb -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO appuser;"
    kubectl exec -n database postgresql-primary-0 -- psql -U postgres -d appdb -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO appuser;"
    
    echo "✓ Database initialized in Primary cluster"
    echo ""
    
    echo "Note: DR database will be synchronized via replication"
fi

# Step 7: Create secrets
echo "Step 6: Creating Kubernetes secrets..."
echo ""

echo "⚠️  IMPORTANT: Update the password in kubernetes/microservices/primary/secrets.yaml and kubernetes/microservices/dr/secrets.yaml"
echo "   Current password is a placeholder and should be changed!"
echo ""

read -p "Have you updated the passwords in secrets.yaml files? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Please update the secrets files and run this script again"
    exit 1
fi

# Apply secrets to Primary
echo "Applying PostgreSQL secrets to Primary cluster..."
az aks get-credentials \
  --resource-group $PRIMARY_RG \
  --name $PRIMARY_CLUSTER \
  --overwrite-existing

kubectl apply -f kubernetes/microservices/primary/secrets.yaml

echo "✓ PostgreSQL secrets created in Primary cluster"
echo ""

# Create ACR image pull secret in Primary
echo "Creating ACR image pull secret in Primary cluster..."
ACR_NAME=$PRIMARY_ACR NAMESPACE=app ./kubernetes/microservices/create-acr-secret.sh

echo "✓ ACR secret created in Primary cluster"
echo ""

# Apply secrets to DR
echo "Applying PostgreSQL secrets to DR cluster..."
az aks get-credentials \
  --resource-group $DR_RG \
  --name $DR_CLUSTER \
  --overwrite-existing

kubectl apply -f kubernetes/microservices/dr/secrets.yaml

echo "✓ PostgreSQL secrets created in DR cluster"
echo ""

# Create ACR image pull secret in DR
echo "Creating ACR image pull secret in DR cluster..."
ACR_NAME=$PRIMARY_ACR NAMESPACE=app ./kubernetes/microservices/create-acr-secret.sh

echo "✓ ACR secret created in DR cluster"
echo ""

# Summary
echo "=== Setup Complete ==="
echo ""
echo "ACR Created:"
echo "  $PRIMARY_ACR.azurecr.io (UAE North)"
echo "  - Attached to both Primary and DR AKS clusters"
echo ""
echo "Namespace:"
echo "  - app namespace created in both clusters"
echo "  - Labels: name=app, environment=production, team=sre"
echo ""
echo "Database:"
echo "  - appuser created"
echo "  - appdb created"
echo "  - Schema initialized"
echo ""
echo "Secrets:"
echo "  - postgresql-secret created in both clusters"
echo ""
echo "Next Steps:"
echo "  1. Build and push container images:"
echo "     cd microservices"
echo "     ./build-and-push.sh $PRIMARY_ACR.azurecr.io"
echo ""
echo "  2. Deploy to Primary cluster:"
echo "     az aks get-credentials --resource-group $PRIMARY_RG --name $PRIMARY_CLUSTER --overwrite-existing"
echo "     export REGION=primary"
echo "     ./kubernetes/microservices/deploy.sh"
echo ""
echo "  3. Deploy to DR cluster:"
echo "     az aks get-credentials --resource-group $DR_RG --name $DR_CLUSTER --overwrite-existing"
echo "     export REGION=dr"
echo "     ./kubernetes/microservices/deploy.sh"
echo ""
echo "  4. Verify deployment:"
echo "     kubectl get pods"
echo "     kubectl get svc"
