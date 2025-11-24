# Microservices Application

This directory contains three stateless microservices built with Python Flask:

1. **Frontend API** (Port 8080) - User-facing API gateway
2. **Business Logic Service** (Port 8081) - Core business operations
3. **Data Ingest Service** (Port 8082) - Data ingestion and processing

## Architecture

```
┌─────────────────┐
│   Frontend API  │ :8080
│  (API Gateway)  │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
┌───▼──────┐  │
│ Business │  │
│  Logic   │  │
│ Service  │  │
└──────────┘  │
    :8081     │
              │
         ┌────▼────────┐
         │ Data Ingest │
         │   Service   │
         └─────────────┘
              :8082
              
         All connect to
              │
         ┌────▼────────┐
         │ PostgreSQL  │
         │  Database   │
         └─────────────┘
```

## Services Overview

### Frontend API
- **Purpose**: API gateway for user requests
- **Endpoints**:
  - `GET /health/live` - Liveness probe
  - `GET /health/ready` - Readiness probe
  - `GET /api/v1/users` - List users
  - `POST /api/v1/users` - Create user
  - `POST /api/v1/data/ingest` - Proxy to data ingest
  - `GET /api/v1/info` - Service information
- **Dependencies**: Business Logic Service, Data Ingest Service, PostgreSQL

### Business Logic Service
- **Purpose**: Core business operations and validations
- **Endpoints**:
  - `GET /health/live` - Liveness probe
  - `GET /health/ready` - Readiness probe
  - `POST /api/v1/validate/user` - Validate user data
  - `POST /api/v1/process/order` - Process orders
  - `GET /api/v1/analytics/summary` - Analytics summary
  - `GET /api/v1/info` - Service information
- **Dependencies**: PostgreSQL

### Data Ingest Service
- **Purpose**: Data ingestion and batch processing
- **Endpoints**:
  - `GET /health/live` - Liveness probe
  - `GET /health/ready` - Readiness probe
  - `POST /api/v1/ingest` - Ingest single or multiple records
  - `POST /api/v1/ingest/batch` - Batch ingestion
  - `GET /api/v1/ingest/stats` - Ingestion statistics
  - `GET /api/v1/ingest/recent` - Recent ingestions
  - `GET /api/v1/info` - Service information
- **Dependencies**: PostgreSQL

## Database Schema

The application uses PostgreSQL with the following tables:

- **users**: User accounts
- **orders**: Order records
- **ingested_data**: Ingested data records

See `init-db.sql` for the complete schema.

## Building Container Images

### Prerequisites
- Docker installed
- Access to a container registry (Azure ACR, Docker Hub, etc.)

### Build and Push

```bash
# Set your registry
export CONTAINER_REGISTRY="myregistry.azurecr.io"
export VERSION="1.0.0"

# Login to registry
az acr login --name myregistry  # For Azure ACR
# OR
docker login  # For Docker Hub

# Build and push all services
cd microservices
./build-and-push.sh
```

This will build and push:
- `myregistry.azurecr.io/frontend-api:1.0.0`
- `myregistry.azurecr.io/business-logic:1.0.0`
- `myregistry.azurecr.io/data-ingest:1.0.0`

### Build Individual Services

```bash
# Frontend API
cd frontend-api
docker build -t myregistry.azurecr.io/frontend-api:1.0.0 .
docker push myregistry.azurecr.io/frontend-api:1.0.0

# Business Logic
cd ../business-logic
docker build -t myregistry.azurecr.io/business-logic:1.0.0 .
docker push myregistry.azurecr.io/business-logic:1.0.0

# Data Ingest
cd ../data-ingest
docker build -t myregistry.azurecr.io/data-ingest:1.0.0 .
docker push myregistry.azurecr.io/data-ingest:1.0.0
```

## Deploying to Kubernetes

### Update Image References

Before deploying, update the image references in the Kubernetes manifests:

```bash
# Update kubernetes/microservices/primary/*.yaml
# Update kubernetes/microservices/dr/*.yaml

# Replace <your-registry> with your actual registry
sed -i 's|<your-registry>|myregistry.azurecr.io|g' kubernetes/microservices/primary/*.yaml
sed -i 's|<your-registry>|myregistry.azurecr.io|g' kubernetes/microservices/dr/*.yaml
```

### Initialize Database

```bash
# Copy init script to PostgreSQL pod
kubectl cp init-db.sql postgresql-0:/tmp/init-db.sql

# Execute initialization
kubectl exec -it postgresql-0 -- psql -U postgres -d appdb -f /tmp/init-db.sql
```

### Deploy to Primary Region

```bash
# Switch to primary cluster
kubectl config use-context primary-aks-cluster

# Create PostgreSQL secret
kubectl create secret generic postgresql-secret \
  --from-literal=password='your-secure-password' \
  --namespace=default

# Deploy microservices
kubectl apply -k kubernetes/microservices/primary/

# Verify deployment
kubectl get pods -n default
kubectl get svc -n default
```

### Deploy to DR Region

```bash
# Switch to DR cluster
kubectl config use-context dr-aks-cluster

# Create PostgreSQL secret
kubectl create secret generic postgresql-secret \
  --from-literal=password='your-secure-password' \
  --namespace=default

# Deploy microservices
kubectl apply -k kubernetes/microservices/dr/

# Verify deployment
kubectl get pods -n default
kubectl get svc -n default
```

## Testing the Application

### Test Health Endpoints

```bash
# Get a pod name
FRONTEND_POD=$(kubectl get pod -l app=frontend-api -o jsonpath='{.items[0].metadata.name}')

# Test liveness
kubectl exec $FRONTEND_POD -- curl -s http://localhost:8080/health/live

# Test readiness
kubectl exec $FRONTEND_POD -- curl -s http://localhost:8080/health/ready
```

### Test API Endpoints

```bash
# Get service info
kubectl exec $FRONTEND_POD -- curl -s http://localhost:8080/api/v1/info

# List users
kubectl exec $FRONTEND_POD -- curl -s http://localhost:8080/api/v1/users

# Create a user
kubectl exec $FRONTEND_POD -- curl -s -X POST http://localhost:8080/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser123","email":"test@example.com"}'

# Ingest data
kubectl exec $FRONTEND_POD -- curl -s -X POST http://localhost:8080/api/v1/data/ingest \
  -H "Content-Type: application/json" \
  -d '{"type":"sensor","data":{"temperature":25.5,"humidity":60},"source":"api"}'
```

### Test Business Logic Service

```bash
BUSINESS_POD=$(kubectl get pod -l app=business-logic -o jsonpath='{.items[0].metadata.name}')

# Get analytics summary
kubectl exec $BUSINESS_POD -- curl -s http://localhost:8081/api/v1/analytics/summary

# Process an order
kubectl exec $BUSINESS_POD -- curl -s -X POST http://localhost:8081/api/v1/process/order \
  -H "Content-Type: application/json" \
  -d '{"user_id":1,"amount":99.99}'
```

### Test Data Ingest Service

```bash
DATA_INGEST_POD=$(kubectl get pod -l app=data-ingest -o jsonpath='{.items[0].metadata.name}')

# Get ingestion stats
kubectl exec $DATA_INGEST_POD -- curl -s http://localhost:8082/api/v1/ingest/stats

# Get recent ingestions
kubectl exec $DATA_INGEST_POD -- curl -s http://localhost:8082/api/v1/ingest/recent?limit=10
```

## Failover Operations

### Automated Failover

Use the provided failover script to perform a complete failover:

```bash
# Set environment variables
export PRIMARY_CLUSTER="primary-aks-cluster"
export DR_CLUSTER="dr-aks-cluster"
export DNS_ZONE="example.com"
export APP_HOSTNAME="app.example.com"

# Execute failover
../scripts/failover-microservices.sh
```

The script performs:
1. Scales up DR microservices (1 → 3 replicas)
2. Promotes DR database to primary
3. Updates microservices configuration
4. Updates DNS to point to DR cluster
5. Scales down primary microservices
6. Verifies failover success

### Manual Failover Steps

If you need to perform failover manually:

```bash
# 1. Scale up DR services
kubectl config use-context dr-aks-cluster
kubectl scale deployment frontend-api --replicas=3
kubectl scale deployment business-logic --replicas=3
kubectl scale deployment data-ingest --replicas=3

# 2. Promote DR database
kubectl exec -it statefulset/postgresql -- psql -U postgres -c "SELECT pg_promote();"

# 3. Update ConfigMap
kubectl patch configmap app-config --type merge -p '{"data":{"region":"primary-failover"}}'

# 4. Restart services
kubectl rollout restart deployment/frontend-api
kubectl rollout restart deployment/business-logic
kubectl rollout restart deployment/data-ingest

# 5. Update DNS (manual or via Azure CLI)
# Point app.example.com to DR cluster ingress IP

# 6. Scale down primary (if accessible)
kubectl config use-context primary-aks-cluster
kubectl scale deployment frontend-api --replicas=0
kubectl scale deployment business-logic --replicas=0
kubectl scale deployment data-ingest --replicas=0
```

### Failback to Primary

```bash
# Execute failback script
../scripts/failback-microservices.sh
```

## Monitoring

### View Logs

```bash
# Frontend API logs
kubectl logs -l app=frontend-api --tail=100 -f

# Business Logic logs
kubectl logs -l app=business-logic --tail=100 -f

# Data Ingest logs
kubectl logs -l app=data-ingest --tail=100 -f
```

### Check Resource Usage

```bash
# Pod resource usage
kubectl top pods -n default

# Node resource usage
kubectl top nodes
```

## Troubleshooting

### Pods Not Starting

```bash
# Describe pod
kubectl describe pod <pod-name>

# Check events
kubectl get events --sort-by='.lastTimestamp'

# Check logs
kubectl logs <pod-name>
```

### Database Connection Issues

```bash
# Test database connectivity
kubectl exec -it <pod-name> -- nc -zv postgresql 5432

# Check database logs
kubectl logs postgresql-0

# Verify secret exists
kubectl get secret postgresql-secret
```

### Service Communication Issues

```bash
# Test service DNS resolution
kubectl exec -it <pod-name> -- nslookup business-logic.default.svc.cluster.local

# Test service connectivity
kubectl exec -it <pod-name> -- curl -v http://business-logic:8081/health/live
```

## Development

### Local Development

```bash
# Install dependencies
cd frontend-api
pip install -r requirements.txt

# Set environment variables
export DATABASE_HOST=localhost
export DATABASE_PORT=5432
export DATABASE_NAME=appdb
export DATABASE_USER=appuser
export DATABASE_PASSWORD=password
export REGION=local
export BUSINESS_LOGIC_URL=http://localhost:8081
export DATA_INGEST_URL=http://localhost:8082

# Run service
python app.py
```

### Running with Docker Compose

Create a `docker-compose.yml` for local testing:

```yaml
version: '3.8'
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: appdb
      POSTGRES_USER: appuser
      POSTGRES_PASSWORD: password
    ports:
      - "5432:5432"
  
  frontend-api:
    build: ./frontend-api
    ports:
      - "8080:8080"
    environment:
      DATABASE_HOST: postgres
      BUSINESS_LOGIC_URL: http://business-logic:8081
      DATA_INGEST_URL: http://data-ingest:8082
    depends_on:
      - postgres
      - business-logic
      - data-ingest
  
  business-logic:
    build: ./business-logic
    ports:
      - "8081:8081"
    environment:
      DATABASE_HOST: postgres
    depends_on:
      - postgres
  
  data-ingest:
    build: ./data-ingest
    ports:
      - "8082:8082"
    environment:
      DATABASE_HOST: postgres
    depends_on:
      - postgres
```

Run with:
```bash
docker-compose up
```

## Security Considerations

1. **Secrets Management**: Use Azure Key Vault with CSI driver instead of Kubernetes secrets
2. **Network Policies**: Implement network policies to restrict pod-to-pod communication
3. **RBAC**: Configure proper RBAC for service accounts
4. **Image Scanning**: Scan container images for vulnerabilities
5. **TLS**: Enable TLS for all service-to-service communication

## Performance Tuning

- Adjust replica counts based on load
- Configure horizontal pod autoscaling
- Optimize database queries and add indexes
- Implement caching where appropriate
- Use connection pooling for database connections

## Next Steps

1. Set up CI/CD pipeline for automated builds and deployments
2. Implement comprehensive monitoring with Prometheus and Grafana
3. Add distributed tracing with Jaeger or OpenTelemetry
4. Implement API rate limiting and authentication
5. Add comprehensive integration tests
