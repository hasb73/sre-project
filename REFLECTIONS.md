## 🏗️ Architecture Decisions

### Why Active/Passive?

**Chosen over Active/Active because:**
-  Lower cost (DR region runs minimal capacity)
-  Simpler operations (single write master)
-  No data conflict resolution needed
-  Easier compliance and audit trails
-  Meets RTO/RPO requirements

**Trade-offs:**
- DR resources idle during normal operations
- Manual/scripted failover required
- Some data loss possible (< 5 minutes)

### Why PostgreSQL Streaming Replication?

**Chosen over backup/restore because:**
-  RPO < 5 minutes (vs hours with backup/restore)
-  Near real-time data synchronization
-  Hot standby can serve read queries
-  Fast failover (promote command)

**Chosen over distributed database because:**
-  Simpler to operate and maintain
-  No split-brain scenarios
-  Lower cost
-  Sufficient for requirements

### Why Azure Traffic Manager?

**Chosen over manual DNS because:**
-  Health-based routing
-  Automatic failover capability
-  Fast DNS propagation ( TTL 10s, probe frequency 10s)


**Chosen over Azure Front Door because:**
-  Lower cost for simple routing
-  Sufficient for requirements
-  Simpler configuration



### Future Enhancements


1. **Pod Security Standards**
   ```bash
   # Enable Pod Security Admission
   kubectl label namespace default pod-security.kubernetes.io/enforce=restricted
   ```
2. **Image Scanning**
   ```bash
   # Scan images with Trivy in CICD pipeline
   trivy image sreproject01.azurecr.io/frontend-api:1.0.0
   ```

3. **Certificate Management**
   ```bash
   # Install cert-manager for automatic TLS
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
   ```


## Production Readiness Checklist

### Before Going to Production


- [ ] **Security**
  - [ ] Azure AD integration enabled
  - [ ] RBAC policies configured and tested
  - [ ] Network policies implemented
  - [ ] Secrets rotated and stored in Key Vault
  - [ ] Security scanning enabled (Azure Defender, Trivy)
  - [ ] TLS/SSL certificates configured
  - [ ] Audit logging enabled

- [ ] **Monitoring and Alerting**
  - [ ] AppDynamics and Splunk collector is configured
  - [ ] Log Analytics workspaces set up
  - [ ] Critical and warning alerts defined (cluster down, replication lag)
  - [ ] Splunk/AppD Dashboards created for key metrics

- [ ] **Database**
  - [ ] Replication tested and verified
  - [ ] Backup strategy implemented
  - [ ] Database performance tuning completed
  - [ ] Replication monitoring alerts configured

- [ ] **Operations**
  - [ ] CI/CD pipeline configured
  - [ ] GitOps workflow implemented (optional)
  - [ ] Change management process defined
  - [ ] Incident response procedures documented
  - [ ] Escalation paths defined
  - [ ] Team training completed

- [ ] **Documentation**
  - [ ] Architecture diagrams updated
  - [ ] Deployment procedures documented
  - [ ] Troubleshooting guides created
  - [ ] API documentation published
  - [ ] Runbooks reviewed and approved


## Cost Optimization Strategies


1. **Scale Down DR Region**
   - Reduce DR deployments
   - Scale up only during testing or failover

2. **Optimize Storage**
   - Use Standard SSD instead of Premium for non-critical data
   - Implement lifecycle policies for old data
   - Use Azure Files Sync instead of duplicate storage
3. **Right-Size Resources**
   - Monitor actual usage and adjust VM sizes
   - Use smaller node pools if workload permits
   - Implement horizontal pod autoscaling
4. **Reduce Log Retention**
   - Decrease Log Analytics retention from 30 to 7 days
   - Export old logs to cheaper storage





