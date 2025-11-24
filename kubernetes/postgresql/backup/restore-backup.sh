#!/bin/bash
# Restore PostgreSQL from Backup
# WARNING: This will overwrite the current database!

set -e

echo "=== PostgreSQL Backup Restore ==="
echo ""
echo "⚠️  WARNING: This will OVERWRITE the current database!"
echo "⚠️  Make sure you have a recent backup before proceeding!"
echo ""

# Check which cluster we're connected to
CURRENT_CONTEXT=$(kubectl config current-context)
echo "Current cluster: $CURRENT_CONTEXT"
echo ""

read -p "Type 'RESTORE' to confirm you want to proceed: " -r
echo ""

if [ "$REPLY" != "RESTORE" ]; then
    echo "Restore cancelled"
    exit 0
fi

# Get storage details
echo "Restoring from Azure Blob Storage..."
echo ""

STORAGE_ACCOUNT=$(kubectl get secret postgresql-backup-azure-secret -n database -o jsonpath='{.data.storage-account}' 2>/dev/null | base64 -d || echo "")
CONTAINER_NAME=$(kubectl get secret postgresql-backup-azure-secret -n database -o jsonpath='{.data.container-name}' 2>/dev/null | base64 -d || echo "")
SAS_TOKEN=$(kubectl get secret postgresql-backup-azure-secret -n database -o jsonpath='{.data.sas-token}' 2>/dev/null | base64 -d || echo "")

if [ -z "$STORAGE_ACCOUNT" ]; then
    echo "ERROR: Azure backup secret not found"
    echo "Run: ./kubernetes/postgresql/setup-backup.sh"
    exit 1
fi

echo "Storage account: $STORAGE_ACCOUNT"
echo "Container: $CONTAINER_NAME"
echo ""

# List available backups
echo "Fetching list of available backups..."
CONTAINER_URL="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER_NAME}?${SAS_TOKEN}"

# Create temp pod to list backups
echo "Available backups in Azure:"
kubectl run azure-list --rm -i --restart=Never --image=ubuntu:22.04 -n database -- bash -c "
    apt-get update -qq && apt-get install -y -qq wget > /dev/null
    cd /tmp
    wget -q https://aka.ms/downloadazcopy-v10-linux -O azcopy.tar.gz
    tar -xzf azcopy.tar.gz
    cp azcopy_linux_amd64_*/azcopy /usr/local/bin/
    chmod +x /usr/local/bin/azcopy
    azcopy list '${CONTAINER_URL}' --properties LastModifiedTime | grep postgresql_backup
" 2>/dev/null || echo "No backups found"

echo ""
read -p "Enter backup filename to restore: " -r BACKUP_FILE
echo ""

# Stop applications
echo "Step 1: Stopping applications..."
kubectl scale deployment hub --replicas=0 -n jupyterhub 2>/dev/null || true
kubectl scale deployment proxy --replicas=0 -n jupyterhub 2>/dev/null || true
echo "✓ Applications stopped"
echo ""

# Download and restore
echo "Step 2: Downloading backup from Azure and restoring..."
kubectl exec -n database postgresql-primary-0 -- bash -c "
    apt-get update -qq && apt-get install -y -qq wget > /dev/null
    cd /tmp
    wget -q https://aka.ms/downloadazcopy-v10-linux -O azcopy.tar.gz
    tar -xzf azcopy.tar.gz
    cp azcopy_linux_amd64_*/azcopy /usr/local/bin/
    chmod +x /usr/local/bin/azcopy
    
    echo 'Downloading backup...'
    azcopy copy '${CONTAINER_URL}/${BACKUP_FILE}' '/tmp/${BACKUP_FILE}'
    
    echo 'Restoring database...'
    gunzip -c /tmp/${BACKUP_FILE} | psql -U postgres
    
    rm /tmp/${BACKUP_FILE}
"

echo "✓ Database restored from Azure"
echo ""

# Restart applications
echo "Step 3: Restarting applications..."
kubectl scale deployment hub --replicas=1 -n jupyterhub 2>/dev/null || true
kubectl scale deployment proxy --replicas=1 -n jupyterhub 2>/dev/null || true
echo "✓ Applications restarted"
echo ""

echo "=== Restore Complete ==="
echo ""
echo "Verify the restore:"
echo "  kubectl exec -n database postgresql-primary-0 -- psql -U postgres -c '\\l'"
echo "  kubectl exec -n database postgresql-primary-0 -- psql -U postgres -d jupyterhub -c 'SELECT COUNT(*) FROM users;'"
echo ""
