#!/bin/bash
# Test database connectivity and schema

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Database Connectivity Test ===${NC}"
echo ""

NAMESPACE="app"
DB_NAMESPACE="database"

# Get database details from configmap
echo "Fetching database configuration..."
DB_HOST=$(kubectl get configmap app-config -n $NAMESPACE -o jsonpath='{.data.db_host}' 2>/dev/null)
DB_PORT=$(kubectl get configmap app-config -n $NAMESPACE -o jsonpath='{.data.db_port}' 2>/dev/null)
DB_NAME=$(kubectl get configmap app-config -n $NAMESPACE -o jsonpath='{.data.db_name}' 2>/dev/null)
DB_USER=$(kubectl get configmap app-config -n $NAMESPACE -o jsonpath='{.data.db_user}' 2>/dev/null)

echo "Database Host: $DB_HOST"
echo "Database Port: $DB_PORT"
echo "Database Name: $DB_NAME"
echo "Database User: $DB_USER"
echo ""

# Test 1: Check if database pod exists
echo -e "${BLUE}1. Checking Database Pod${NC}"

# Try to find PostgreSQL pod
if echo "$DB_HOST" | grep -q "primary"; then
    DB_POD="postgresql-primary-0"
elif echo "$DB_HOST" | grep -q "secondary"; then
    DB_POD="postgresql-secondary-0"
else
    DB_POD="postgresql-0"
fi

if kubectl get pod $DB_POD -n $DB_NAMESPACE &>/dev/null; then
    echo -e "${GREEN}✓ Database pod $DB_POD exists${NC}"
    
    POD_STATUS=$(kubectl get pod $DB_POD -n $DB_NAMESPACE -o jsonpath='{.status.phase}')
    echo "Status: $POD_STATUS"
else
    echo -e "${RED}✗ Database pod $DB_POD not found${NC}"
    echo "Available pods in database namespace:"
    kubectl get pods -n $DB_NAMESPACE
    exit 1
fi
echo ""

# Test 2: Test connectivity from app pods
echo -e "${BLUE}2. Testing Connectivity from App Pods${NC}"

FRONTEND_POD=$(kubectl get pod -n $NAMESPACE -l app=frontend-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$FRONTEND_POD" ]; then
    echo "Using pod: $FRONTEND_POD"
    
    # Test DNS resolution
    echo -e "${YELLOW}Testing DNS resolution...${NC}"
    if kubectl exec -n $NAMESPACE $FRONTEND_POD -- nslookup $DB_HOST &>/dev/null; then
        echo -e "${GREEN}✓ DNS resolution successful${NC}"
        kubectl exec -n $NAMESPACE $FRONTEND_POD -- nslookup $DB_HOST 2>/dev/null | grep -A2 "Name:"
    else
        echo -e "${RED}✗ DNS resolution failed${NC}"
    fi
    
    # Test port connectivity
    echo -e "${YELLOW}Testing port connectivity...${NC}"
    if kubectl exec -n $NAMESPACE $FRONTEND_POD -- nc -zv $DB_HOST $DB_PORT 2>&1 | grep -q "succeeded"; then
        echo -e "${GREEN}✓ Port $DB_PORT is reachable${NC}"
    else
        echo -e "${RED}✗ Port $DB_PORT is not reachable${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No frontend-api pod found, skipping connectivity test${NC}"
fi
echo ""

# Test 3: Check database schema
echo -e "${BLUE}3. Checking Database Schema${NC}"

echo -e "${YELLOW}Checking if database and user exist...${NC}"

# Check if database exists
DB_EXISTS=$(kubectl exec -n $DB_NAMESPACE $DB_POD -- psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" 2>/dev/null)

if [ "$DB_EXISTS" = "1" ]; then
    echo -e "${GREEN}✓ Database '$DB_NAME' exists${NC}"
else
    echo -e "${RED}✗ Database '$DB_NAME' does not exist${NC}"
fi

# Check if user exists
USER_EXISTS=$(kubectl exec -n $DB_NAMESPACE $DB_POD -- psql -U postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" 2>/dev/null)

if [ "$USER_EXISTS" = "1" ]; then
    echo -e "${GREEN}✓ User '$DB_USER' exists${NC}"
else
    echo -e "${RED}✗ User '$DB_USER' does not exist${NC}"
fi

# List tables
echo -e "${YELLOW}Listing tables in $DB_NAME...${NC}"
TABLES=$(kubectl exec -n $DB_NAMESPACE $DB_POD -- psql -U postgres -d $DB_NAME -tAc "SELECT tablename FROM pg_tables WHERE schemaname='public'" 2>/dev/null)

if [ -n "$TABLES" ]; then
    echo -e "${GREEN}✓ Tables found:${NC}"
    echo "$TABLES"
else
    echo -e "${YELLOW}⚠ No tables found in database${NC}"
fi
echo ""

# Test 4: Check table schemas
echo -e "${BLUE}4. Checking Table Schemas${NC}"

for table in users orders ingested_data; do
    echo -e "${YELLOW}Checking table: $table${NC}"
    
    TABLE_EXISTS=$(kubectl exec -n $DB_NAMESPACE $DB_POD -- psql -U postgres -d $DB_NAME -tAc "SELECT 1 FROM information_schema.tables WHERE table_name='$table'" 2>/dev/null)
    
    if [ "$TABLE_EXISTS" = "1" ]; then
        echo -e "${GREEN}✓ Table '$table' exists${NC}"
        
        # Show table structure
        echo "Columns:"
        kubectl exec -n $DB_NAMESPACE $DB_POD -- psql -U postgres -d $DB_NAME -c "\d $table" 2>/dev/null | grep -v "^$"
        
        # Count rows
        ROW_COUNT=$(kubectl exec -n $DB_NAMESPACE $DB_POD -- psql -U postgres -d $DB_NAME -tAc "SELECT COUNT(*) FROM $table" 2>/dev/null)
        echo "Row count: $ROW_COUNT"
    else
        echo -e "${RED}✗ Table '$table' does not exist${NC}"
    fi
    echo ""
done

# Test 5: Test database permissions
echo -e "${BLUE}5. Testing Database Permissions${NC}"

echo -e "${YELLOW}Checking $DB_USER permissions on $DB_NAME...${NC}"

# Check database privileges
DB_PRIVS=$(kubectl exec -n $DB_NAMESPACE $DB_POD -- psql -U postgres -d $DB_NAME -tAc "SELECT string_agg(privilege_type, ', ') FROM information_schema.table_privileges WHERE grantee='$DB_USER' AND table_schema='public' LIMIT 1" 2>/dev/null)

if [ -n "$DB_PRIVS" ]; then
    echo -e "${GREEN}✓ User has privileges: $DB_PRIVS${NC}"
else
    echo -e "${YELLOW}⚠ No specific table privileges found (may have database-level access)${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}=== Test Summary ===${NC}"
echo ""
echo "Database: $DB_NAME"
echo "User: $DB_USER"
echo "Host: $DB_HOST"
echo ""
echo "To connect to database directly:"
echo "  kubectl exec -it -n $DB_NAMESPACE $DB_POD -- psql -U postgres -d $DB_NAME"
echo ""
echo "To run SQL queries:"
echo "  kubectl exec -n $DB_NAMESPACE $DB_POD -- psql -U postgres -d $DB_NAME -c 'SELECT * FROM users LIMIT 5;'"
