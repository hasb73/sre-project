# PostgreSQL Backup and Restore Strategy

## Overview

This document describes the backup and restore strategy for PostgreSQL databases in both Primary and DR regions.

## Backup Strategy

### Two-Tier Backup Approach

1. **Local Backups (PVC)**
   - Stored on persistent volume in the cluster
   - Fast backup and restore
   - Retained for 7 days
   - Schedule: Daily at 2 AM

2. **Off-Cluster Backups (Azure Blob Storage)**
   - Stored in Azure Blob Storage
   - Protection against cluster-level failures
   - Retained for 30 days (manual cleanup)
   - Schedule: Daily at 3 AM

### What Gets Backed Up

- All databases (`pg_dumpall`)
- All users and roles
- All permissions and grants
- Database schemas and data
- JupyterHub database
- Application databases

### What Doesn't Get Backed Up

- PostgreSQL configuration files (managed by Kubernetes)
- WAL files (use replication for point-in-time recovery)
- Temporary tables
- Unlogged tables

## Setup

### Prerequisites

- Azure CLI installed and authenticated
- kubectl configured for target cluster
- Sufficient storage quota in Azure Storage Account

### Initial Setup

```bash
# Switch to the cluster you want to backup
kubectl config use-context primary-aks-cluster  # or dr-aks-cluster

# Run setup script
./kubernetes/postgresql/setup-backup.sh
```

The script will:
1. Create PVC for local backups (50GB)
2. Deploy local backup cronjob
3. Create Azure Blob Storage container
4. Generate SAS token
5. Deploy Azure backup cronjob

### Manual Setup (Alternative)

```bash
# 1. Deploy local backup
kubectl apply -f kubernetes/postgresql/backup-cronjob.yaml

# 2. Create Azure container
az storage container create \
  --account-name primaryst01 \
  --name postgresql-backups \
  --auth-mode login

# 3. Generate SAS token
SAS_TOKEN=$(az storage container generate-sas \
  --account-name primaryst01 \
  --name postgresql-backups \
  --permissions rwdl \
  --expiry $(date -u -v+1y '+%Y-%m-%dT%H:%MZ') \
  --https-only \
  --output tsv)

# 4. Create secret
kubectl create secret generic postgresql-backup-azure-secret \
  --from-literal=storage-account="primaryst01" \
  --from-literal=container-name="postgresql-backups" \
  --from-literal=sas-token="$SAS_TOKEN" \
  -n database

# 5. Deploy Azure backup
kubectl apply -f kubernetes/postgresql/backup-to-azure-cronjob.yaml
```

## Usage

### Verify Backups are Running

```bash
# Check cronjobs
kubectl get cronjob -n database

# Check recent backup jobs
kubectl get jobs -n database | grep backup

# View backup logs
kubectl logs -n database -l app=postgresql-backup --tail=50
kubectl logs -n database -l app=postgresql-backup-azure --tail=50
```

### Manual Backup

```bash
# Trigger local backup
kubectl create job --from=cronjob/postgresql-backup manual-backup-$(date +%Y%m%d-%H%M) -n database

# Trigger Azure backup
kubectl create job --from=cronjob/postgresql-backup-to-azure manual-backup-azure-$(date +%Y%m%d-%H%M) -n database

# Monitor the backup
kubectl logs -n database -f <backup-job-pod-name>
```

### List Available Backups

**Local Backups:**
```bash
kubectl exec -n database postgresql-primary-0 -- ls -lh /backups/
```

**Azure Backups:**
```bash
# Using Azure Portal
# Navigate to: Storage Account > Containers > postgresql-backups

# Using Azure CLI
az storage blob list \
  --account-name primaryst01 \
  --container-name postgresql-backups \
  --output table
```

## Restore

### ⚠️ Important Warnings

- **Restore will overwrite the current database**
- **Stop all applications before restore**
- **Verify backup integrity before restore**
- **Test restore in non-production first**
- **Have a recent backup before attempting restore**

### Restore from Local Backup

```bash
# Use the restore script (recommended)
./kubernetes/postgresql/restore-backup.sh

# Or manual restore
kubectl exec -n database postgresql-primary-0 -- bash -c "
  gunzip -c /backups/postgresql_backup_20251123_020000.sql.gz | psql -U postgres
"
```

### Restore from Azure Backup

```bash
# Use the restore script (recommended)
./kubernetes/postgresql/restore-backup.sh

# Or manual restore
# 1. Download backup
az storage blob download \
  --account-name primaryst01 \
  --container-name postgresql-backups \
  --name postgresql_backup_20251123_030000.sql.gz \
  --file /tmp/backup.sql.gz

# 2. Copy to pod
kubectl cp /tmp/backup.sql.gz database/postgresql-primary-0:/tmp/backup.sql.gz

# 3. Restore
kubectl exec -n database postgresql-primary-0 -- bash -c "
  gunzip -c /tmp/backup.sql.gz | psql -U postgres
  rm /tmp/backup.sql.gz
"
```

### Restore Specific Database

```bash
# If you only need to restore a specific database (e.g., jupyterhub)
kubectl exec -n database postgresql-primary-0 -- bash -c "
  gunzip -c /backups/postgresql_backup_20251123_020000.sql.gz | \
  psql -U postgres -d jupyterhub
"
```

### Point-in-Time Recovery

For point-in-time recovery, you need WAL archiving enabled. Current setup uses streaming replication only.

To enable WAL archiving:
1. Configure `archive_mode = on` in postgresql.conf
2. Set `archive_command` to copy WAL files to Azure Blob Storage
3. Use `pg_basebackup` + WAL replay for PITR

## Backup Verification

### Test Backup Integrity

```bash
# Verify backup file is not corrupted
kubectl exec -n database postgresql-primary-0 -- bash -c "
  gunzip -t /backups/postgresql_backup_20251123_020000.sql.gz && echo 'Backup file is valid'
"

# Check backup size (should be > 0)
kubectl exec -n database postgresql-primary-0 -- ls -lh /backups/
```

### Test Restore (Non-Production)

```bash
# Create a test database and restore to it
kubectl exec -n database postgresql-primary-0 -- bash -c "
  createdb -U postgres test_restore
  gunzip -c /backups/postgresql_backup_20251123_020000.sql.gz | psql -U postgres -d test_restore
  psql -U postgres -d test_restore -c '\\dt'
  dropdb -U postgres test_restore
"
```

## Monitoring and Alerts

### Recommended Alerts

1. **Backup Job Failures**
   - Alert if backup job fails 2 times in a row
   - Check logs and disk space

2. **Backup Age**
   - Alert if latest backup is > 36 hours old
   - Indicates cronjob may not be running

3. **Backup Size**
   - Alert if backup size changes dramatically (>50%)
   - May indicate data loss or corruption

4. **Storage Quota**
   - Alert if backup storage is > 80% full
   - Need to cleanup old backups or increase quota

### Monitoring Commands

```bash
# Check last backup time
kubectl get jobs -n database -l app=postgresql-backup --sort-by=.status.startTime

# Check backup sizes
kubectl exec -n database postgresql-primary-0 -- du -sh /backups/*

# Check PVC usage
kubectl exec -n database postgresql-primary-0 -- df -h /backups
```

## Maintenance

### Cleanup Old Backups

**Local backups** are automatically cleaned up (7 day retention).

**Azure backups** require manual cleanup:

```bash
# List old backups
az storage blob list \
  --account-name primaryst01 \
  --container-name postgresql-backups \
  --query "[?properties.creationTime<'2024-10-23'].name" \
  --output table

# Delete backups older than 30 days
az storage blob delete-batch \
  --account-name primaryst01 \
  --source postgresql-backups \
  --pattern "postgresql_backup_202410*.sql.gz"
```

### Rotate SAS Tokens

SAS tokens expire after 1 year. Regenerate before expiry:

```bash
# Generate new SAS token
./kubernetes/postgresql/setup-backup.sh

# Or manually
SAS_TOKEN=$(az storage container generate-sas \
  --account-name primaryst01 \
  --name postgresql-backups \
  --permissions rwdl \
  --expiry $(date -u -v+1y '+%Y-%m-%dT%H:%MZ') \
  --https-only \
  --output tsv)

# Update secret
kubectl create secret generic postgresql-backup-azure-secret \
  --from-literal=storage-account="primaryst01" \
  --from-literal=container-name="postgresql-backups" \
  --from-literal=sas-token="$SAS_TOKEN" \
  -n database \
  --dry-run=client -o yaml | kubectl apply -f -
```

## Disaster Recovery Scenarios

### Scenario 1: Accidental Data Deletion

1. Stop applications
2. Restore from most recent backup
3. Verify data integrity
4. Restart applications

### Scenario 2: Database Corruption

1. Stop applications
2. Attempt to repair with `pg_resetwal` (if possible)
3. If repair fails, restore from backup
4. Restart applications

### Scenario 3: Complete Cluster Loss

1. Provision new cluster
2. Deploy PostgreSQL
3. Restore from Azure Blob Storage backup
4. Reconfigure replication
5. Deploy applications

### Scenario 4: Ransomware/Security Breach

1. Isolate affected systems
2. Restore from backup BEFORE the breach
3. Investigate and patch vulnerabilities
4. Restore applications with updated security

## Best Practices

1. **Test Restores Regularly**
   - Monthly restore test in non-production
   - Verify data integrity after restore
   - Document restore time (RTO)

2. **Monitor Backup Health**
   - Set up alerts for backup failures
   - Check backup logs weekly
   - Verify backup sizes are consistent

3. **Secure Backups**
   - Use SAS tokens with minimal permissions
   - Rotate tokens annually
   - Enable Azure Blob Storage encryption
   - Restrict network access to storage account

4. **Document Procedures**
   - Keep this document updated
   - Document any custom restore procedures
   - Train team on restore process

5. **Backup Before Major Changes**
   - Always backup before schema changes
   - Backup before major upgrades
   - Backup before failover/failback

## Troubleshooting

### Backup Job Fails

```bash
# Check job status
kubectl describe job <backup-job-name> -n database

# Check pod logs
kubectl logs -n database <backup-pod-name>

# Common issues:
# - Insufficient disk space
# - Database connection issues
# - Permission problems
```

### Restore Fails

```bash
# Check PostgreSQL logs
kubectl logs -n database postgresql-primary-0

# Common issues:
# - Database still has active connections
# - Insufficient disk space
# - Corrupted backup file
# - Version mismatch
```

### Cannot Access Backups

```bash
# Check PVC is mounted
kubectl describe pod postgresql-primary-0 -n database | grep -A 5 Mounts

# Check PVC status
kubectl get pvc -n database

# Check Azure connectivity
kubectl run test-azure --rm -i --restart=Never --image=ubuntu:22.04 -- \
  curl -I https://primaryst01.blob.core.windows.net/
```

## Related Documentation

- [Super Troubleshooting Guide](../../docs/super-troubleshooting-failover.md)
- [PostgreSQL Replication](./README.md)
- [Failover Procedures](../../scripts/failover_app.sh)
- [Failback Procedures](../../scripts/failback_app.sh)

---

**Last Updated:** 2025-11-23  
**Backup Retention:** Local: 7 days, Azure: 30 days  
**Backup Schedule:** Daily at 2 AM (local), 3 AM (Azure)
