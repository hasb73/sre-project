#!/bin/bash
# Setup PostgreSQL Azure Blob Storage Backup
# This script configures automated backups to Azure Blob Storage

set -e

echo "=== PostgreSQL Azure Backup Setup ==="
echo ""

# Check which cluster we're connected to
CURRENT_CONTEXT=$(kubectl config current-context)
echo "Current cluster: $CURRENT_CONTEXT"
echo ""

# Determine cluster type
if [[ "$CURRENT_CONTEXT" == *"primary"* ]]; then
    CLUSTER="primary"
    STORAGE_ACCOUNT="primaryst01"
    RESOURCE_GROUP="azure-maen-primary-rg"
elif [[ "$CURRENT_CONTEXT" == *"dr"* ]]; then
    CLUSTER="dr"
    STORAGE_ACCOUNT="drst01"
    RESOURCE_GROUP="azure-meun-dr-rg"
else
    echo "ERROR: Cannot determine cluster type from context: $CURRENT_CONTEXT"
    exit 1
fi

echo "Setting up backups for: $CLUSTER cluster"
echo "Storage account: $STORAGE_ACCOUNT"
echo ""

# Check if database namespace exists
if ! kubectl get namespace database &>/dev/null; then
    echo "ERROR: database namespace not found"
    exit 1
fi

echo "✓ Database namespace found"
echo ""

echo "This will create daily backups to Azure Blob Storage."
echo "Backups are retained for 30 days (manual cleanup)."
echo "Schedule: Daily at 2 AM"
echo ""
read -p "Continue? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Setup cancelled"
    exit 0
fi
# Check if container exists
CONTAINER_NAME="postgresql-backups"

echo "Checking if storage container exists..."
if ! az storage container show \
    --account-name "$STORAGE_ACCOUNT" \
    --name "$CONTAINER_NAME" &>/dev/null; then
    
    echo "Container not found. Creating..."
    az storage container create \
        --account-name "$STORAGE_ACCOUNT" \
        --name "$CONTAINER_NAME" \
        --auth-mode login
    
    echo "✓ Container created: $CONTAINER_NAME"
else
    echo "✓ Container exists: $CONTAINER_NAME"
fi

echo ""

# Generate SAS token
echo "Generating SAS token for backup uploads..."
EXPIRY=$(date -u -v+1y '+%Y-%m-%dT%H:%MZ')

SAS_TOKEN=$(az storage container generate-sas \
    --account-name "$STORAGE_ACCOUNT" \
    --name "$CONTAINER_NAME" \
    --permissions rwdl \
    --expiry "$EXPIRY" \
    --https-only \
    --output tsv)

echo "✓ SAS token generated (valid for 1 year)"
echo ""

# Create secret
echo "Creating Kubernetes secret..."
kubectl create secret generic postgresql-backup-azure-secret \
    --from-literal=storage-account="$STORAGE_ACCOUNT" \
    --from-literal=container-name="$CONTAINER_NAME" \
    --from-literal=sas-token="$SAS_TOKEN" \
    -n database \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Secret created"
echo ""

# Deploy cronjob
echo "Deploying Azure Blob backup cronjob..."
kubectl apply -f kubernetes/postgresql/backup-to-azure-cronjob.yaml

echo "✓ Azure Blob backup cronjob deployed"
echo ""
echo "Backups will be uploaded to:"
echo "  https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER_NAME}/"
echo ""

# Summary
echo "=== Setup Complete ==="
echo ""
echo "Backup cronjob deployed:"
kubectl get cronjob -n database postgresql-backup-to-azure
echo ""

echo "Backup schedule: Daily at 2 AM"
echo "Retention: 30 days (manual cleanup required)"
echo ""

echo "To verify backups:"
echo "  kubectl get jobs -n database | grep backup"
echo "  kubectl logs -n database -l app=postgresql-backup-azure"
echo ""

echo "To manually trigger a backup:"
echo "  kubectl create job --from=cronjob/postgresql-backup-to-azure manual-backup-$(date +%Y%m%d-%H%M) -n database"
echo ""

echo "To view backups in Azure:"
echo "  az storage blob list --account-name $STORAGE_ACCOUNT --container-name $CONTAINER_NAME --output table"
echo ""

echo "To restore from backup:"
echo "  ./kubernetes/postgresql/restore-backup.sh"
echo ""

echo "Documentation: kubernetes/postgresql/BACKUP-RESTORE.md"
