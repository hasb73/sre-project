# JupyterHub Failover Scripts

Automated scripts for performing controlled failover and failback operations for JupyterHub between Primary and DR regions.

## Scripts

### 1. `jupyterhub_failover.sh` - Primary → DR
Performs a controlled failover from Primary to DR region.

**Usage:**
```bash
./scripts/failover/failover_full_stack.sh
```

**What it does:**
1. Connects to Primary cluster
2. Scales down JupyterHub hub (stops accepting new users)
3. Triggers Azure Files delta sync (Primary → DR)
4. Connects to DR cluster
5. Checks DR database pod status
6. Verifies database recovery status
7. Promotes DR database to primary
8. Scales up JupyterHub hub and application in DR
9. Verifies pod health and readiness

**RTO:** ~2-5 minutes for the promote and pods to scale
**RPO:** ~15 minutes at the most due to the scheduled cron job,immediate if the file sync runs as part of the script

---

### 2. `jupyterhub_failback.sh` - DR → Primary
Performs a controlled failback from DR to Primary region.

**Usage:**
```bash
./scripts/failover/failback_full_stack.sh
```

**What it does:**
1. Connects to DR cluster
2. Scales down JupyterHub hub in DR
3. Triggers Azure Files delta sync (DR → Primary)
4. Demotes DR database back to replica
5. Connects to Primary cluster
6. Checks Primary database pod status
7. Verifies Primary database is in primary mode
8. Verifies replication from Primary to DR
9. Scales up JupyterHub hub in Primary
10. Verifies pod health and readiness

**Duration:** ~2-5 minutes




## Troubleshooting

### Failover Issues

**Database promotion fails:**
```bash
# Check database logs
kubectl logs -n database postgresql-secondary-0 --tail=50

# Manually promote if needed
kubectl exec -n database postgresql-secondary-0 -- psql -U postgres -c "SELECT pg_promote();"
```

**JupyterHub hub won't start:**
```bash
# Check hub logs
kubectl logs -n jupyterhub -l component=hub --tail=100

# Check database connectivity
kubectl exec -n jupyterhub -l component=hub -- \
  psql "postgresql://jupyterhub:PASSWORD@postgresql-secondary.database.svc.cluster.local:5432/jupyterhub" -c "SELECT 1;"
```

### Failback Issues

**Replication not working:**
```bash
# Check DR database logs
kubectl logs -n database postgresql-secondary-0 --tail=50

# Verify replication configuration
kubectl exec -n database postgresql-secondary-0 -- \
  cat /var/lib/postgresql/data/pgdata/postgresql.auto.conf

# Check if standby.signal exists
kubectl exec -n database postgresql-secondary-0 -- \
  ls -la /var/lib/postgresql/data/pgdata/standby.signal
```


## Monitoring

Key metrics to monitor during failover:

- Database replication lag
- Pod readiness status
- Application Gateway health probes
- User session count
- Error rates in logs

