#!/bin/bash
# Setup AzCopy Sync Secrets for Azure Files Replication
# This creates SAS tokens for both primary and DR storage accounts

set -e

echo "=== Setting up AzCopy Sync Secrets ==="
echo ""

# Generate expiry date (1 year from now)
# macOS compatible date command
EXPIRY=$(date -u -v+1y '+%Y-%m-%dT%H:%MZ')

# Generate SAS token for primary storage account (read/write for bidirectional sync)
echo "Generating SAS token for primary storage account (primaryst01)..."
PRIMARY_SAS=$(az storage share generate-sas \
  --account-name primaryst01 \
  --name jupyterhub-users \
  --permissions rwdl \
  --expiry "$EXPIRY" \
  --https-only \
  --output tsv)

echo "✓ Primary SAS token generated (read/write)"

# Generate SAS token for DR storage account (read/write for bidirectional sync)
echo "Generating SAS token for DR storage account (drst01)..."
DR_SAS=$(az storage share generate-sas \
  --account-name drst01 \
  --name jupyterhub-users \
  --permissions rwdl \
  --expiry "$EXPIRY" \
  --https-only \
  --output tsv)

echo "✓ DR SAS token generated"
echo ""

# Create Kubernetes secret
echo "Creating Kubernetes secret..."
kubectl create secret generic azcopy-sync-secrets \
  --from-literal=primary-sas="$PRIMARY_SAS" \
  --from-literal=dr-sas="$DR_SAS" \
  -n jupyterhub \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Secret created/updated"
echo ""
echo "=== Setup Complete ==="
echo ""
echo "The AzCopy sync cronjob will now be able to replicate files from primary to DR."
echo "SAS tokens are valid for 1 year and will need to be regenerated before expiry."
