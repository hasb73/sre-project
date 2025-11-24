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


```bash
# Setup the namespace
sh scripts/setup-app-namespace.sh
```

## Building Container Images

### Prerequisites
- Docker installed
- Access to a container registry (Azure ACR, Docker Hub, etc.)

### Build and Push

```bash
# Set your registry
export CONTAINER_REGISTRY="sreproject01.azurecr.io"
export VERSION="1.0.0"

# Login to registry
az acr login --name sreproject01  # For Azure ACR
# OR
docker login  # For Docker Hub

# Build and push all services
cd microservices
./build-and-push.sh
```

This will build and push:
- `sreproject01.azurecr.io/frontend-api:1.0.0`
- `sreproject01.azurecr.io/business-logic:1.0.0`
- `sreproject01.azurecr.io/data-ingest:1.0.0`



### Initialize Database

```bash
# Copy init script to PostgreSQL pod
kubectl cp init-db.sql postgresql-0:/tmp/init-db.sql

# Execute initialization
kubectl exec -it postgresql-0 -- psql -U postgres -d appdb -f /tmp/init-db.sql
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

