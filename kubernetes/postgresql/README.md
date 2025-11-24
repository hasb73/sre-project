# PostgreSQL Multi-Region Deployment

This directory contains Kubernetes manifests for deploying PostgreSQL in an active/passive multi-region disaster recovery configuration.

## Architecture

- **Primary Region**: PostgreSQL primary database accepting read/write operations
- **DR Region**: PostgreSQL secondary database in hot standby mode with streaming replication

## Directory Structure

```
postgresql/
├── primary/              # Primary region manifests
│   ├── configmap.yaml    # PostgreSQL configuration
│   ├── init-configmap.yaml  # Initialization scripts
│   ├── service.yaml      # Service definitions
│   ├── statefulset.yaml  # Primary StatefulSet
│   └── secret.yaml       # Database credentials
└── secondary/            # DR region manifests
    ├── configmap.yaml    # PostgreSQL configuration
    ├── service.yaml      # Service definitions
    └── statefulset.yaml  # Secondary StatefulSet with replication
```

## Prerequisites

1. Kubernetes clusters in both primary and DR regions
2. Storage class `managed-premium` available in both clusters
3. Network connectivity between regions (VNet peering)
4. kubectl configured with contexts for both clusters

## Deployment Instructions

### Step 1: Deploy Primary Database

Deploy to the primary region cluster:

```bash
# Switch to primary cluster context
kubectl config use-context <primary-cluster-context>

# Create namespace (if not exists)
kubectl create namespace default

# Deploy secret (update passwords before deploying!)
kubectl apply -f primary/secret.yaml

# Deploy ConfigMaps
kubectl apply -f primary/configmap.yaml
kubectl apply -f primary/init-configmap.yaml

# Deploy Service
kubectl apply -f primary/service.yaml

# Deploy StatefulSet
kubectl apply -f primary/statefulset.yaml

# Wait for pod to be ready
kubectl wait --for=condition=ready pod/postgresql-primary-0 --timeout=300s
```

### Step 2: Verify Primary Database

```bash
# Check pod status
kubectl get pods -l app=postgresql,role=primary

# Check logs
kubectl logs postgresql-primary-0

# Connect to database
kubectl exec -it postgresql-primary-0 -- psql -U postgres -d appdb

# Verify replication configuration
kubectl exec -it postgresql-primary-0 -- psql -U postgres -c "SELECT * FROM pg_replication_slots;"
```

### Step 3: Deploy Secondary Database

Deploy to the DR region cluster:

```bash
# Switch to DR cluster context
kubectl config use-context <dr-cluster-context>

# Create namespace (if not exists)
kubectl create namespace default

# Deploy secret (must match primary!)
kubectl apply -f primary/secret.yaml

# Deploy ConfigMap
kubectl apply -f secondary/configmap.yaml

# Deploy Service
kubectl apply -f secondary/service.yaml

# Deploy StatefulSet
kubectl apply -f secondary/statefulset.yaml

# Wait for pod to be ready
kubectl wait --for=condition=ready pod/postgresql-secondary-0 --timeout=600s
```

### Step 4: Verify Replication

On the primary database:

```bash
kubectl config use-context <primary-cluster-context>

kubectl exec -it postgresql-primary-0 -- psql -U postgres -c "
SELECT 
  application_name,
  client_addr,
  state,
  sync_state,
  sent_lsn,
  write_lsn,
  flush_lsn,
  replay_lsn,
  sync_priority
FROM pg_stat_replication;
"
```

On the secondary database:

```bash
kubectl config use-context <dr-cluster-context>

kubectl exec -it postgresql-secondary-0 -- psql -U postgres -c "
SELECT 
  pg_is_in_recovery() as is_standby,
  pg_last_wal_receive_lsn() as receive_lsn,
  pg_last_wal_replay_lsn() as replay_lsn,
  pg_last_xact_replay_timestamp() as last_replay_time;
"
```

## Configuration Details

### Storage

- **Storage Class**: `managed-premium` (Azure Premium SSD)
- **Storage Size**: 100Gi per database
- **Access Mode**: ReadWriteOnce
- **Reclaim Policy**: Retain (default for StatefulSet PVCs)

### Resource Limits

Each PostgreSQL pod is configured with:
- **CPU Request**: 500m
- **CPU Limit**: 2000m (2 cores)
- **Memory Request**: 512Mi
- **Memory Limit**: 2Gi

### Replication Configuration

- **Replication Method**: Streaming replication
- **Replication User**: `replicator`
- **Replication Slot**: `replication_slot_1`
- **WAL Level**: `replica`
- **Max WAL Senders**: 10
- **WAL Keep Size**: 1GB

### Network Configuration

- **Primary Service**: `postgresql.default.svc.cluster.local` (port 5432)
- **Secondary Service**: `postgresql-readonly.default.svc.cluster.local` (port 5432)
- **Headless Services**: For StatefulSet pod discovery

## Operations

### Testing Replication

Insert test data on primary:

```bash
kubectl exec -it postgresql-primary-0 -- psql -U postgres -d appdb -c "
CREATE TABLE IF NOT EXISTS replication_test (
  id SERIAL PRIMARY KEY,
  test_data TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO replication_test (test_data) VALUES ('Test at ' || NOW());
"
```

Verify on secondary:

```bash
kubectl exec -it postgresql-secondary-0 -- psql -U postgres -d appdb -c "
SELECT * FROM replication_test ORDER BY created_at DESC LIMIT 5;
"
```

### Monitoring Replication Lag

```bash
# On primary
kubectl exec -it postgresql-primary-0 -- psql -U postgres -c "
SELECT 
  application_name,
  EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp())) as lag_seconds
FROM pg_stat_replication;
"
```

### Promoting Secondary to Primary (Failover)

In case of primary region failure:

```bash
# Switch to DR cluster
kubectl config use-context <dr-cluster-context>

# Promote secondary to primary
kubectl exec -it postgresql-secondary-0 -- pg_ctl promote -D /var/lib/postgresql/data/pgdata

# Or use SQL command
kubectl exec -it postgresql-secondary-0 -- psql -U postgres -c "SELECT pg_promote();"

# Verify promotion
kubectl exec -it postgresql-secondary-0 -- psql -U postgres -c "SELECT pg_is_in_recovery();"
# Should return 'f' (false) indicating it's now primary
```

### Updating Database Passwords

1. Update the secret in both clusters:

```bash
kubectl create secret generic postgresql-secret \
  --from-literal=postgres-password='new-password' \
  --from-literal=replication-password='new-replication-password' \
  --dry-run=client -o yaml | kubectl apply -f -
```

2. Restart the pods to pick up new credentials:

```bash
kubectl rollout restart statefulset/postgresql-primary
kubectl rollout restart statefulset/postgresql-secondary
```

## Troubleshooting

### Secondary Not Connecting to Primary

1. Check network connectivity:

```bash
kubectl exec -it postgresql-secondary-0 -- nc -zv postgresql-primary-0.postgresql-primary.default.svc.cluster.local 5432
```

2. Check replication user credentials:

```bash
kubectl exec -it postgresql-secondary-0 -- psql -h postgresql-primary-0.postgresql-primary.default.svc.cluster.local -U replicator -d postgres -c "SELECT 1;"
```

3. Check primary logs for connection attempts:

```bash
kubectl logs postgresql-primary-0 | grep replicator
```

### Replication Lag Too High

1. Check network bandwidth between regions
2. Verify primary database load
3. Check secondary database resources
4. Review WAL settings (increase `wal_keep_size` if needed)

### Pod Stuck in Pending State

1. Check PVC status:

```bash
kubectl get pvc
```

2. Check storage class availability:

```bash
kubectl get storageclass
```

3. Check node resources:

```bash
kubectl describe node
```
