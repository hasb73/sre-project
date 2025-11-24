# Storage Module

This Terraform module provisions Azure storage resources for persistent volumes and backup management in the multi-region DR setup.

## Features

- **Storage Account**: Creates an Azure Storage Account with configurable redundancy (LRS, ZRS, GRS, GZRS)
- **Blob Storage**: Configures blob versioning and soft delete for data protection
- **Backup Infrastructure**: Optional Recovery Services Vault with backup policies
- **Azure Disk Support**: Configurable storage tiers for Kubernetes persistent volumes

## Resources Created

- `azurerm_storage_account` - Storage account for backups and persistent data
- `azurerm_storage_container` - Container for backup storage
- `azurerm_recovery_services_vault` - Recovery vault for backup management (optional)
- `azurerm_backup_policy_file_share` - Backup policy with daily, weekly, and monthly retention (optional)
- `azurerm_backup_container_storage_account` - Links storage account to backup vault (optional)

## Usage

```hcl
module "storage" {
  source = "../../modules/storage"

  environment            = "primary"
  location               = "eastus"
  resource_group_name    = azurerm_resource_group.main.name
  storage_account_suffix = "stprimary001"
  
  # Storage configuration
  account_tier       = "Standard"
  replication_type   = "LRS"
  disk_storage_tier  = "Premium_LRS"
  
  # Backup configuration
  enable_backup           = true
  backup_retention_days   = 30
  blob_retention_days     = 7
  
  tags = {
    Environment = "primary"
    ManagedBy   = "Terraform"
  }
}
```

## Storage Redundancy Options

### For Storage Accounts
- **LRS** (Locally Redundant Storage): 3 copies within a single datacenter
- **ZRS** (Zone Redundant Storage): 3 copies across availability zones
- **GRS** (Geo-Redundant Storage): 6 copies across two regions
- **GZRS** (Geo-Zone-Redundant Storage): ZRS in primary + LRS in secondary region

### For Azure Disks (Kubernetes PVs)
- **Standard_LRS**: Standard HDD, locally redundant
- **StandardSSD_LRS**: Standard SSD, locally redundant
- **Premium_LRS**: Premium SSD, locally redundant (recommended for databases)
- **StandardSSD_ZRS**: Standard SSD, zone redundant
- **Premium_ZRS**: Premium SSD, zone redundant
- **UltraSSD_LRS**: Ultra SSD, locally redundant (highest performance)

## Backup Policy

When `enable_backup = true`, the module creates:
- Daily backups at 23:00 UTC
- Retention: 30 days (daily), 4 weeks (weekly), 12 months (monthly)
- Soft delete enabled on Recovery Vault

## Kubernetes Storage Classes

The module outputs a storage class name that can be used in Kubernetes manifests:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: database-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: managed-premium_lrs  # From module output
  resources:
    requests:
      storage: 100Gi
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| environment | Environment name (primary or dr) | string | - | yes |
| location | Azure region for resources | string | - | yes |
| resource_group_name | Name of the resource group | string | - | yes |
| storage_account_suffix | Suffix for storage account name (must be globally unique) | string | - | yes |
| account_tier | Storage account tier (Standard or Premium) | string | "Standard" | no |
| replication_type | Storage account replication type | string | "LRS" | no |
| disk_storage_tier | Storage tier for Azure Disk | string | "Premium_LRS" | no |
| blob_retention_days | Number of days to retain deleted blobs | number | 7 | no |
| enable_backup | Enable backup policy for storage | bool | false | no |
| backup_retention_days | Number of days to retain daily backups | number | 30 | no |
| tags | Tags to apply to resources | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| storage_account_id | ID of the storage account |
| storage_account_name | Name of the storage account |
| storage_account_primary_access_key | Primary access key (sensitive) |
| storage_account_primary_blob_endpoint | Primary blob endpoint |
| backups_container_name | Name of the backups container |
| recovery_vault_id | ID of the recovery services vault |
| recovery_vault_name | Name of the recovery services vault |
| backup_policy_id | ID of the backup policy |
| storage_class_name | Name of the storage class for Kubernetes PVs |
| disk_storage_tier | Azure Disk storage tier |

## Design Considerations

### Primary Region
- Use **Premium_LRS** for database persistent volumes (low latency, high IOPS)
- Use **LRS** or **ZRS** for storage account (cost vs. availability trade-off)
- Enable backups for production data protection

### DR Region
- Use same disk tier as primary for consistent performance during failover
- Use **LRS** for storage account (cost optimization for standby region)
- Enable backups to protect against data corruption

### Cost Optimization
- DR region can use lower-tier storage if acceptable during failover
- Adjust backup retention based on compliance requirements
- Use lifecycle policies to move old backups to cool/archive tiers

## Requirements

- Terraform >= 1.5
- Azure Provider >= 3.0
- Appropriate Azure permissions to create storage and backup resources
