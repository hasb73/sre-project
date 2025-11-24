#!/bin/bash
# Complete Failback Script - JupyterHub and Microservices from DR to Primary region

set -e

# Configuration
PRIMARY_RG="azure-maen-primary-rg"
PRIMARY_CLUSTER="primary-aks-cluster"
DR_RG="azure-meun-dr-rg"
DR_CLUSTER="dr-aks-cluster"
PRIMARY_DB_IP="10.1.0.62"

echo "="
echo "  Complete Failback: DR → Primary"
echo "  (JupyterHub + Microservices)"
echo "="
echo ""


# STEP 1: Connect to DR Cluster 
echo "[1/9] Connecting to DR cluster..."
az aks get-credentials --resource-group $DR_RG --name $DR_CLUSTER --overwrite-existing > /dev/null 2>&1
echo "Connected to DR"
echo ""

#  STEP 2: Scale Down Applications in DR 
echo "[2/9] Scaling down applications in DR..."

# Scale down JupyterHub
kubectl scale deployment hub -n jupyterhub --replicas=0
echo "JupyterHub hub scaled to 0"

# Scale down Microservices
kubectl scale deployment user-service -n microservices --replicas=0
kubectl scale deployment order-service -n microservices --replicas=0
kubectl scale deployment notification-service -n microservices --replicas=0
echo "Microservices scaled to 0"
echo ""

# STEP 3: Trigger Delta Sync (Azure Files DR to Primary) 
echo "[3/9] Starting delta sync (Azure Files DR to Primary)..."

# Remove any older sync jobs
kubectl delete job azure-files-sync-dr-to-primary -n jupyterhub --ignore-not-found=true

# Apply the sync job
kubectl apply -f kubernetes/jupyterhub/azcopy-dr-to-primary-job.yaml

echo "Waiting for sync job to complete..."
kubectl wait --for=condition=complete --timeout=300s job/azure-files-sync-dr-to-primary -n jupyterhub
echo "Delta sync completed"
echo ""

# STEP 4: Demote DR Database to Replica 
echo "[4/9] Demoting DR database to replica..."
DR_DB_POD=$(kubectl get pod -n database -l app=postgresql,role=secondary -o jsonpath='{.items[0].metadata.name}')

# Stop PostgreSQL
echo "Stopping PostgreSQL..."
kubectl scale statefulset postgresql-secondary -n database --replicas=0
sleep 5

# Delete PVC to solve timeline issue (forces fresh pg_basebackup from primary)
echo "Deleting PVC to rebuild from primary (solves timeline mismatch)..."
kubectl delete pvc data-postgresql-secondary-0 -n database
echo "PVC deleted"

# Scale back up (init container will rebuild from primary with correct configuration)
echo "Scaling up StatefulSet (init container will rebuild from primary)..."
kubectl scale statefulset postgresql-secondary -n database --replicas=1

# Wait for init container to complete pg_basebackup and pod to be ready
echo "Waiting for pg_basebackup to complete and pod to be ready (this may take a few minutes)..."
kubectl wait --for=condition=ready --timeout=300s pod -l app=postgresql,role=secondary -n database

# Verify database is in recovery mode
DR_DB_POD=$(kubectl get pod -n database -l app=postgresql,role=secondary -o jsonpath='{.items[0].metadata.name}')
echo "Verifying database is in recovery mode..."
DR_RECOVERY_STATUS=$(kubectl exec -n database $DR_DB_POD -- psql -U postgres -t -c "SELECT pg_is_in_recovery();")
echo "DR Recovery status: $DR_RECOVERY_STATUS"

if [[ "$DR_RECOVERY_STATUS" =~ "t" ]]; then
    echo "DR database successfully demoted to replica"
else
    echo "ERROR: DR database is not in recovery mode"
    exit 1
fi
echo ""

# Verify replication status from secondary
echo "Verifying replication connection from DR secondary..."
kubectl exec -n database $DR_DB_POD -- psql -U postgres -c "SELECT status, sender_host, sender_port, slot_name, conninfo FROM pg_stat_wal_receiver;"
echo ""

# STEP 5: Connect to Primary Cluster 
echo "[5/9] Connecting to Primary cluster..."
az aks get-credentials --resource-group $PRIMARY_RG --name $PRIMARY_CLUSTER --overwrite-existing > /dev/null 2>&1
echo "Connected to Primary"
echo ""

# STEP 6: Check Primary Database Pod Status 
echo "[6/9] Checking Primary database pod status..."
PRIMARY_DB_POD=$(kubectl get pod -n database -l app=postgresql,role=primary -o jsonpath='{.items[0].metadata.name}')
if [ -z "$PRIMARY_DB_POD" ]; then
    echo "ERROR: No database pod found in Primary"
    exit 1
fi
echo "Database pod: $PRIMARY_DB_POD"

kubectl wait --for=condition=ready --timeout=60s pod/$PRIMARY_DB_POD -n database
echo "Database pod is ready"
echo ""

# STEP 7: Verify Primary Database Status 
echo "[7/9] Verifying Primary database status..."
RECOVERY_STATUS=$(kubectl exec -n database $PRIMARY_DB_POD -- psql -U postgres -t -c "SELECT pg_is_in_recovery();")
echo "Recovery status: $RECOVERY_STATUS"

if [[ "$RECOVERY_STATUS" =~ "f" ]]; then
    echo "Primary database is in primary mode"
else
    echo "ERROR: Primary database is in recovery mode (unexpected)"
    exit 1
fi
echo ""

# STEP 8: Verify Replication from Primary to DR 
echo "[8/9] Verifying replication status..."
REPLICATION_STATUS=$(kubectl exec -n database $PRIMARY_DB_POD -- psql -U postgres -t -c "SELECT application_name, state FROM pg_stat_replication WHERE application_name='dr-secondary';")
echo "Replication: $REPLICATION_STATUS"

if [[ "$REPLICATION_STATUS" =~ "streaming" ]]; then
    echo "Replication to DR is active"
else
    echo "WARNING: Replication not yet established (may take a moment)"
fi
echo ""

#  STEP 9: Scale Up Applications in Primary 
echo "[9/9] Scaling up applications in Primary..."

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

#  Summary 
echo "Failback Completed Successfully"
