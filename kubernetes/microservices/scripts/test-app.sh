#!/bin/bash
# Test microservices application and database connectivity

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Microservices Application Test ===${NC}"
echo ""

# Configuration
NAMESPACE="app"
REGION="${REGION:-unknown}"

# Function to print test result
print_result() {
    local test_name=$1
    local result=$2
    
    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✓ $test_name${NC}"
    else
        echo -e "${RED}✗ $test_name${NC}"
    fi
}

# Function to run test
run_test() {
    local test_name=$1
    local command=$2
    
    echo -e "${YELLOW}Testing: $test_name${NC}"
    
    if eval "$command" &>/dev/null; then
        print_result "$test_name" "PASS"
        return 0
    else
        print_result "$test_name" "FAIL"
        return 1
    fi
}

# Test 1: Check if namespace exists
echo -e "${BLUE}1. Checking Namespace${NC}"
if kubectl get namespace $NAMESPACE &>/dev/null; then
    print_result "Namespace '$NAMESPACE' exists" "PASS"
else
    print_result "Namespace '$NAMESPACE' exists" "FAIL"
    echo "Please create namespace first"
    exit 1
fi
echo ""

# Test 2: Check if all pods are running
echo -e "${BLUE}2. Checking Pod Status${NC}"
PODS=$(kubectl get pods -n $NAMESPACE -o json)

for service in frontend-api business-logic data-ingest; do
    POD_STATUS=$(echo $PODS | jq -r ".items[] | select(.metadata.labels.app==\"$service\") | .status.phase" | head -1)
    
    if [ "$POD_STATUS" = "Running" ]; then
        print_result "$service pod is running" "PASS"
    else
        print_result "$service pod is running (Status: $POD_STATUS)" "FAIL"
    fi
done
echo ""

# Test 3: Check if all services exist
echo -e "${BLUE}3. Checking Services${NC}"
for service in frontend-api business-logic data-ingest; do
    if kubectl get svc $service -n $NAMESPACE &>/dev/null; then
        print_result "$service service exists" "PASS"
    else
        print_result "$service service exists" "FAIL"
    fi
done
echo ""

# Test 4: Check database connectivity from pods
echo -e "${BLUE}4. Testing Database Connectivity${NC}"

# Get database host from configmap
DB_HOST=$(kubectl get configmap app-config -n $NAMESPACE -o jsonpath='{.data.db_host}')
echo "Database Host: $DB_HOST"

for service in frontend-api business-logic data-ingest; do
    POD=$(kubectl get pod -n $NAMESPACE -l app=$service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -n "$POD" ]; then
        echo -e "${YELLOW}Testing from $service pod...${NC}"
        
        # Test DNS resolution
        if kubectl exec -n $NAMESPACE $POD -- nslookup $DB_HOST &>/dev/null; then
            print_result "$service: DNS resolution for $DB_HOST" "PASS"
        else
            print_result "$service: DNS resolution for $DB_HOST" "FAIL"
        fi
        
        # Test port connectivity
        if kubectl exec -n $NAMESPACE $POD -- nc -zv $DB_HOST 5432 &>/dev/null; then
            print_result "$service: Port 5432 connectivity to $DB_HOST" "PASS"
        else
            print_result "$service: Port 5432 connectivity to $DB_HOST" "FAIL"
        fi
    fi
done
echo ""

# Test 5: Check health endpoints
echo -e "${BLUE}5. Testing Health Endpoints${NC}"

for service in frontend-api business-logic data-ingest; do
    POD=$(kubectl get pod -n $NAMESPACE -l app=$service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -n "$POD" ]; then
        # Get port from service
        case $service in
            frontend-api) PORT=8080 ;;
            business-logic) PORT=8081 ;;
            data-ingest) PORT=8082 ;;
        esac
        
        # Test liveness endpoint
        if kubectl exec -n $NAMESPACE $POD -- curl -sf http://localhost:$PORT/health/live &>/dev/null; then
            print_result "$service: /health/live endpoint" "PASS"
        else
            print_result "$service: /health/live endpoint" "FAIL"
        fi
        
        # Test readiness endpoint
        if kubectl exec -n $NAMESPACE $POD -- curl -sf http://localhost:$PORT/health/ready &>/dev/null; then
            print_result "$service: /health/ready endpoint" "PASS"
        else
            print_result "$service: /health/ready endpoint" "FAIL"
        fi
    fi
done
echo ""

# Test 6: Test API endpoints
echo -e "${BLUE}6. Testing API Endpoints${NC}"

FRONTEND_POD=$(kubectl get pod -n $NAMESPACE -l app=frontend-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$FRONTEND_POD" ]; then
    # Test /api/v1/info endpoint
    echo -e "${YELLOW}Testing /api/v1/info endpoint...${NC}"
    INFO_RESPONSE=$(kubectl exec -n $NAMESPACE $FRONTEND_POD -- curl -sf http://localhost:8080/api/v1/info 2>/dev/null)
    
    if [ -n "$INFO_RESPONSE" ]; then
        print_result "GET /api/v1/info" "PASS"
        echo "Response: $INFO_RESPONSE" | jq '.' 2>/dev/null || echo "$INFO_RESPONSE"
    else
        print_result "GET /api/v1/info" "FAIL"
    fi
    
    # Test /api/v1/users endpoint
    echo -e "${YELLOW}Testing /api/v1/users endpoint...${NC}"
    USERS_RESPONSE=$(kubectl exec -n $NAMESPACE $FRONTEND_POD -- curl -sf http://localhost:8080/api/v1/users 2>/dev/null)
    
    if [ -n "$USERS_RESPONSE" ]; then
        print_result "GET /api/v1/users" "PASS"
        echo "Response: $USERS_RESPONSE" | jq '.' 2>/dev/null || echo "$USERS_RESPONSE"
    else
        print_result "GET /api/v1/users" "FAIL"
    fi
fi
echo ""

# Test 7: Test database operations
echo -e "${BLUE}7. Testing Database Operations${NC}"

if [ -n "$FRONTEND_POD" ]; then
    # Create a test user
    echo -e "${YELLOW}Creating test user...${NC}"
    TIMESTAMP=$(date +%s)
    TEST_USER="testuser_${TIMESTAMP}"
    TEST_EMAIL="test_${TIMESTAMP}@example.com"
    
    CREATE_RESPONSE=$(kubectl exec -n $NAMESPACE $FRONTEND_POD -- curl -sf -X POST http://localhost:8080/api/v1/users \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$TEST_USER\",\"email\":\"$TEST_EMAIL\"}" 2>/dev/null)
    
    if [ -n "$CREATE_RESPONSE" ]; then
        print_result "Create user via API" "PASS"
        echo "Created user: $CREATE_RESPONSE" | jq '.' 2>/dev/null || echo "$CREATE_RESPONSE"
        
        # Verify user was created
        echo -e "${YELLOW}Verifying user in database...${NC}"
        USERS_RESPONSE=$(kubectl exec -n $NAMESPACE $FRONTEND_POD -- curl -sf http://localhost:8080/api/v1/users 2>/dev/null)
        
        if echo "$USERS_RESPONSE" | grep -q "$TEST_USER"; then
            print_result "User exists in database" "PASS"
        else
            print_result "User exists in database" "FAIL"
        fi
    else
        print_result "Create user via API" "FAIL"
    fi
fi
echo ""

# Test 8: Test service-to-service communication
echo -e "${BLUE}8. Testing Service-to-Service Communication${NC}"

BUSINESS_LOGIC_POD=$(kubectl get pod -n $NAMESPACE -l app=business-logic -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$BUSINESS_LOGIC_POD" ]; then
    # Test business-logic /api/v1/info endpoint
    echo -e "${YELLOW}Testing business-logic service...${NC}"
    BL_RESPONSE=$(kubectl exec -n $NAMESPACE $BUSINESS_LOGIC_POD -- curl -sf http://localhost:8081/api/v1/info 2>/dev/null)
    
    if [ -n "$BL_RESPONSE" ]; then
        print_result "business-logic /api/v1/info" "PASS"
    else
        print_result "business-logic /api/v1/info" "FAIL"
    fi
    
    # Test analytics endpoint
    echo -e "${YELLOW}Testing analytics endpoint...${NC}"
    ANALYTICS_RESPONSE=$(kubectl exec -n $NAMESPACE $BUSINESS_LOGIC_POD -- curl -sf http://localhost:8081/api/v1/analytics/summary 2>/dev/null)
    
    if [ -n "$ANALYTICS_RESPONSE" ]; then
        print_result "GET /api/v1/analytics/summary" "PASS"
        echo "Analytics: $ANALYTICS_RESPONSE" | jq '.' 2>/dev/null || echo "$ANALYTICS_RESPONSE"
    else
        print_result "GET /api/v1/analytics/summary" "FAIL"
    fi
fi
echo ""

# Test 9: Test data-ingest service
echo -e "${BLUE}9. Testing Data Ingest Service${NC}"

DATA_INGEST_POD=$(kubectl get pod -n $NAMESPACE -l app=data-ingest -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$DATA_INGEST_POD" ]; then
    # Test data-ingest /api/v1/info endpoint
    echo -e "${YELLOW}Testing data-ingest service...${NC}"
    DI_RESPONSE=$(kubectl exec -n $NAMESPACE $DATA_INGEST_POD -- curl -sf http://localhost:8082/api/v1/info 2>/dev/null)
    
    if [ -n "$DI_RESPONSE" ]; then
        print_result "data-ingest /api/v1/info" "PASS"
    else
        print_result "data-ingest /api/v1/info" "FAIL"
    fi
    
    # Test ingest endpoint
    echo -e "${YELLOW}Testing data ingestion...${NC}"
    INGEST_RESPONSE=$(kubectl exec -n $NAMESPACE $DATA_INGEST_POD -- curl -sf -X POST http://localhost:8082/api/v1/ingest \
        -H "Content-Type: application/json" \
        -d "{\"type\":\"test\",\"data\":{\"value\":123},\"source\":\"test-script\"}" 2>/dev/null)
    
    if [ -n "$INGEST_RESPONSE" ]; then
        print_result "POST /api/v1/ingest" "PASS"
        echo "Ingested: $INGEST_RESPONSE" | jq '.' 2>/dev/null || echo "$INGEST_RESPONSE"
    else
        print_result "POST /api/v1/ingest" "FAIL"
    fi
    
    # Test ingest stats
    echo -e "${YELLOW}Testing ingest stats...${NC}"
    STATS_RESPONSE=$(kubectl exec -n $NAMESPACE $DATA_INGEST_POD -- curl -sf http://localhost:8082/api/v1/ingest/stats 2>/dev/null)
    
    if [ -n "$STATS_RESPONSE" ]; then
        print_result "GET /api/v1/ingest/stats" "PASS"
        echo "Stats: $STATS_RESPONSE" | jq '.' 2>/dev/null || echo "$STATS_RESPONSE"
    else
        print_result "GET /api/v1/ingest/stats" "FAIL"
    fi
fi
echo ""

# Test 10: Check logs for errors
echo -e "${BLUE}10. Checking Logs for Errors${NC}"

for service in frontend-api business-logic data-ingest; do
    echo -e "${YELLOW}Checking $service logs...${NC}"
    ERROR_COUNT=$(kubectl logs -n $NAMESPACE -l app=$service --tail=100 2>/dev/null | grep -i "error\|exception\|failed" | wc -l)
    
    if [ "$ERROR_COUNT" -eq 0 ]; then
        print_result "$service: No errors in recent logs" "PASS"
    else
        print_result "$service: Found $ERROR_COUNT error(s) in recent logs" "FAIL"
        echo "Recent errors:"
        kubectl logs -n $NAMESPACE -l app=$service --tail=100 2>/dev/null | grep -i "error\|exception\|failed" | tail -5
    fi
done
echo ""

# Summary
echo -e "${BLUE}=== Test Summary ===${NC}"
echo ""
echo "Cluster: $(kubectl config current-context)"
echo "Namespace: $NAMESPACE"
echo "Region: $REGION"
echo ""
echo "To view detailed logs:"
echo "  kubectl logs -n $NAMESPACE -l app=frontend-api --tail=50"
echo "  kubectl logs -n $NAMESPACE -l app=business-logic --tail=50"
echo "  kubectl logs -n $NAMESPACE -l app=data-ingest --tail=50"
echo ""
echo "To access frontend API:"
echo "  kubectl port-forward -n $NAMESPACE svc/frontend-api 8080:8080"
echo "  curl http://localhost:8080/api/v1/info"
