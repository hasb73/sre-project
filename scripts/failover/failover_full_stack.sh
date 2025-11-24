#!/bin/bash
# Complete Failover Script - Primary to DR
# This script performs a controlled failover of JupyterHub and Microservices from Primary to DR region

set -e

# Configuration
PRIMARY_RG="azure-maen-primary-rg"
PRIMARY_CLUSTER="primary-aks-cluster"
DR_RG="azure-meun-dr-rg"
DR_CLUSTER="dr-aks-cluster"

echo "========================================"
echo "  Complete Failover: Primary → DR"
echo "  (JupyterHub + Microservices)"
echo "========================================"
echo ""

# === STEP 1: Connect to Primary Cluster ===
echo "[1/8] Connecting to Primary cluster..."
az aks get-credentials --resource-group $PRIMARY_RG --name $PRIMARY_CLUSTER --overwrite-existing > /dev/null 2>&1
echo "Connected to Primary"
echo ""

# === STEP 2: Scale Down Applications in Primary ===
echo "[2/8] Scaling down applications in Primary..."

# Scale down JupyterHub
kubectl scale deployment hub -n jupyterhub --replicas=0
echo "JupyterHub hub scaled to 0"

# Scale down Microservices
kubectl scale deployment user-service -n microservices --replicas=0
kubectl scale deployment order-service -n microservices --replicas=0
kubectl scale deployment notification-service -n microservices --replicas=0
echo "Microservices scaled to 0"
echo ""

# === STEP 3: Trigger Delta Sync (Azure Files) ===
echo "[3/8] Starting delta sync (Azure Files)..."
kubectl create job --from=cronjob/azure-files-sync azure-files-sync-failover -n jupyterhub
echo "Waiting for sync job to complete..."
kubectl wait --for=condition=complete --timeout=300s job/azure-files-sync-failover -n jupyterhub
echo "Delta sync completed"
echo ""

# === STEP 4: Connect to DR Cluster ===
echo "[4/8] Connecting to DR cluster..."
az aks get-credentials --resource-group $DR_RG --name $DR_CLUSTER --overwrite-existing > /dev/null 2>&1
echo "Connected to DR"
echo ""

# === STEP 5: Check DR Database Pod Status ===
echo "[5/8] Checking DR database pod status..."
DB_POD=$(kubectl get pod -n database -l app=postgresql,role=secondary -o jsonpath='{.items[0].metadata.name}')
if [ -z "$DB_POD" ]; then
    echo "ERROR: No database pod found in DR"
    exit 1
fi
echo "Database pod: $DB_POD"

# Wait for pod to be ready
kubectl wait --for=condition=ready --timeout=60s pod/$DB_POD -n database
echo "Database pod is ready"
echo ""

# === STEP 6: Check Database Recovery Status ===
echo "[6/8] Checking database recovery status..."
RECOVERY_STATUS=$(kubectl exec -n database $DB_POD -- psql -U postgres -t -c "SELECT pg_is_in_recovery();")
echo "Recovery status: $RECOVERY_STATUS"

if [[ "$RECOVERY_STATUS" =~ "t" ]]; then
    echo "Database is in recovery mode (replica)"
else
    echo "WARNING: Database is already promoted (not in recovery)"
fi
echo ""

# === STEP 7: Promote DR Database to Primary ===
echo "[7/8] Promoting DR database to primary..."
if [[ "$RECOVERY_STATUS" =~ "t" ]]; then
    kubectl exec -n database $DB_POD -- psql -U postgres -c "SELECT pg_promote();"
    echo "Waiting for promotion to complete..."
    sleep 5
    
    # Verify promotion
    NEW_STATUS=$(kubectl exec -n database $DB_POD -- psql -U postgres -t -c "SELECT pg_is_in_recovery();")
    if [[ "$NEW_STATUS" =~ "f" ]]; then
        echo "Database promoted successfully"
    else
        echo "ERROR: Database promotion failed"
        exit 1
    fi
else
    echo "Database already in primary mode"
fi
echo ""

# === STEP 8: Scale Up Applications in DR ===
echo "[8/8] Scaling up applications in DR..."

# Scale up JupyterHub
kubectl scale deployment hub -n jupyterhub --replicas=1
echo "JupyterHub hub scaled to 1"

# Scale up Microservices
kubectl scale deployment user-service -n microservices --replicas=1
kubectl scale deployment order-service -n microservices --replicas=1
kubectl scale deployment notification-service -n microservices --replicas=1
echo "Microservices scaled to 1"

echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready --timeout=120s pod -l component=hub -n jupyterhub
kubectl wait --for=condition=ready --timeout=120s pod -l app=user-service -n microservices
kubectl wait --for=condition=ready --timeout=120s pod -l app=order-service -n microservices
kubectl wait --for=condition=ready --timeout=120s pod -l app=notification-service -n microservices

# Check JupyterHub pod health
HUB_POD=$(kubectl get pod -n jupyterhub -l component=hub -o jsonpath='{.items[0].metadata.name}')
POD_STATUS=$(kubectl get pod $HUB_POD -n jupyterhub -o jsonpath='{.status.phase}')
READY_STATUS=$(kubectl get pod $HUB_POD -n jupyterhub -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')

echo "Hub pod: $HUB_POD"
echo "Status: $POD_STATUS"
echo "Ready: $READY_STATUS"

if [[ "$POD_STATUS" == "Running" && "$READY_STATUS" == "True" ]]; then
    echo "JupyterHub hub is running and ready"
else
    echo "ERROR: JupyterHub hub is not ready"
    kubectl logs $HUB_POD -n jupyterhub --tail=20
    exit 1
fi

echo "All applications are running and ready"
echo ""

# === Summary ===
echo "========================================"
echo "  Failover Completed Successfully!"
echo "========================================"
echo ""
echo "Summary:"
echo "  - Primary applications: Scaled down"
echo "  - Azure Files: Synced to DR"
echo "  - DR Database: Promoted to primary"
echo "  - DR JupyterHub: Running and ready"
echo "  - DR Microservices: Running and ready"
echo ""
echo "Next Steps:"
echo "  1. Update Traffic Manager to point to DR"
echo "  2. Verify application access via DR endpoint"
echo "  3. Monitor DR cluster performance"
echo ""
echo "Current context:"
kubectl config current-context
