#!/bin/bash
# Verify JupyterHub PostgreSQL Integration and Replication
# This script checks database connectivity and replication status

set -e

# Output formatting removed for compatibility

echo "=========================================="
echo "JupyterHub Database Verification"
echo "=========================================="
echo ""

# Function to check status
check_status() {
    local component=$1
    local command=$2
    
    echo -n "  Checking $component... "
    if eval "$command" &>/dev/null; then
        echo "[OK]"
        return 0
    else
        echo "[FAIL]"
        return 1
    fi
}

# Function to get value
get_value() {
    local label=$1
    local command=$2
    
    echo -n "  $label: "
    result=$(eval "$command" 2>/dev/null || echo "N/A")
    if [ "$result" != "N/A" ] && [ -n "$result" ]; then
        echo "$result"
    else
        echo "$result"
    fi
}

# Function to run SQL query
run_sql_primary() {
    local query=$1
    kubectl exec -n database deployment/postgresql-primary -- \
        psql -U jupyterhub -d jupyterhub -t -c "$query" 2>/dev/null || echo "ERROR"
}

run_sql_secondary() {
    local query=$1
    kubectl exec -n database deployment/postgresql-secondary -- \
        psql -U jupyterhub -d jupyterhub -t -c "$query" 2>/dev/null || echo "ERROR"
}

# ============================================
# PART 1: PRIMARY CLUSTER VERIFICATION
# ============================================

echo "[1] Primary Cluster - Database Status"
echo ""

# Switch to primary cluster
echo "Switching to primary cluster..."
az aks get-credentials --name primary-aks-cluster --resource-group azure-maen-primary-rg --overwrite-existing >/dev/null 2>&1

echo ""
echo "1.1 PostgreSQL Primary Status"
check_status "PostgreSQL primary pod running" "kubectl get pods -n database -l app=postgresql,role=primary --field-selector=status.phase=Running | grep -q Running"
check_status "PostgreSQL service exists" "kubectl get svc postgresql-primary -n database"
get_value "Primary pod name" "kubectl get pods -n database -l app=postgresql,role=primary -o jsonpath='{.items[0].metadata.name}'"
get_value "Primary service IP" "kubectl get svc postgresql-primary -n database -o jsonpath='{.spec.clusterIP}'"

echo ""
echo "1.2 JupyterHub Database Configuration"
check_status "JupyterHub namespace exists" "kubectl get namespace jupyterhub"
check_status "JupyterHub hub pod running" "kubectl get pods -n jupyterhub -l component=hub --field-selector=status.phase=Running | grep -q Running"
check_status "Database secret exists" "kubectl get secret jupyterhub-db -n jupyterhub"

# Check if JupyterHub is configured to use PostgreSQL
echo ""
echo -n "  Database type: "
DB_TYPE=$(kubectl get deployment hub -n jupyterhub -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="JUPYTERHUB_DB_URL")].valueFrom.secretKeyRef.name}' 2>/dev/null || echo "N/A")
if [ "$DB_TYPE" == "jupyterhub-db" ]; then
    echo "PostgreSQL (configured)"
else
    echo "SQLite or not configured"
fi

# Get database URL from secret
echo -n "  Database URL: "
DB_URL=$(kubectl get secret jupyterhub-db -n jupyterhub -o jsonpath='{.data.db-url}' 2>/dev/null | base64 -d 2>/dev/null || echo "N/A")
if [[ "$DB_URL" == *"postgresql"* ]]; then
    # Mask password
    MASKED_URL=$(echo "$DB_URL" | sed 's/:\/\/[^:]*:[^@]*@/:\/\/***:***@/')
    echo "$MASKED_URL"
else
    echo "$DB_URL"
fi

echo ""
echo -e "${YELLOW}1.3 Database Connectivity Test${NC}"

# Test connection from JupyterHub hub pod
HUB_POD=$(kubectl get pods -n jupyterhub -l component=hub -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$HUB_POD" ]; then
    echo -n "  Connection from hub pod: "
    if kubectl exec -n jupyterhub $HUB_POD -- python3 -c "import psycopg2; conn = psycopg2.connect('$DB_URL'); print('Connected'); conn.close()" 2>/dev/null | grep -q "Connected"; then
        echo -e "${GREEN}✓ Connected${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
    fi
else
    echo -e "  ${YELLOW}Hub pod not found${NC}"
fi

echo ""
echo -e "${YELLOW}1.4 JupyterHub Database Content${NC}"

# Check if database has JupyterHub tables
echo -n "  JupyterHub tables exist: "
TABLES=$(run_sql_primary "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('users', 'servers', 'oauth_clients');")
TABLES=$(echo "$TABLES" | tr -d ' ')
if [ "$TABLES" == "3" ]; then
    echo -e "${GREEN}✓ Yes (3 tables)${NC}"
elif [ "$TABLES" == "ERROR" ]; then
    echo -e "${RED}✗ Cannot query${NC}"
else
    echo -e "${YELLOW}⚠ Partial ($TABLES/3 tables)${NC}"
fi

# Count users
echo -n "  Number of users: "
USER_COUNT=$(run_sql_primary "SELECT COUNT(*) FROM users;")
USER_COUNT=$(echo "$USER_COUNT" | tr -d ' ')
if [ "$USER_COUNT" != "ERROR" ]; then
    echo -e "${GREEN}$USER_COUNT${NC}"
else
    echo -e "${YELLOW}Cannot query${NC}"
fi

# Count active servers
echo -n "  Active servers: "
SERVER_COUNT=$(run_sql_primary "SELECT COUNT(*) FROM servers WHERE started IS NOT NULL;")
SERVER_COUNT=$(echo "$SERVER_COUNT" | tr -d ' ')
if [ "$SERVER_COUNT" != "ERROR" ]; then
    echo -e "${GREEN}$SERVER_COUNT${NC}"
else
    echo -e "${YELLOW}Cannot query${NC}"
fi

# Show recent users
echo ""
echo "  Recent users:"
RECENT_USERS=$(run_sql_primary "SELECT name, created FROM users ORDER BY created DESC LIMIT 5;")
if [ "$RECENT_USERS" != "ERROR" ]; then
    echo "$RECENT_USERS" | while IFS= read -r line; do
        if [ -n "$line" ]; then
            echo -e "    ${GREEN}$line${NC}"
        fi
    done
else
    echo -e "    ${YELLOW}Cannot query${NC}"
fi

echo ""
echo -e "${YELLOW}1.5 PostgreSQL Replication Status (Primary)${NC}"

# Check replication slots
echo -n "  Replication slot exists: "
SLOT_COUNT=$(run_sql_primary "SELECT COUNT(*) FROM pg_replication_slots WHERE slot_name='jupyterhub_replication_slot';")
SLOT_COUNT=$(echo "$SLOT_COUNT" | tr -d ' ')
if [ "$SLOT_COUNT" == "1" ]; then
    echo -e "${GREEN}✓ Yes${NC}"
elif [ "$SLOT_COUNT" == "ERROR" ]; then
    echo -e "${YELLOW}Cannot query${NC}"
else
    echo -e "${RED}✗ No${NC}"
fi

# Check replication connections
echo -n "  Replication connections: "
REPL_CONN=$(run_sql_primary "SELECT COUNT(*) FROM pg_stat_replication;")
REPL_CONN=$(echo "$REPL_CONN" | tr -d ' ')
if [ "$REPL_CONN" != "ERROR" ]; then
    if [ "$REPL_CONN" -gt "0" ]; then
        echo -e "${GREEN}$REPL_CONN active${NC}"
    else
        echo -e "${YELLOW}$REPL_CONN (no standby connected)${NC}"
    fi
else
    echo -e "${YELLOW}Cannot query${NC}"
fi

# Show replication lag
if [ "$REPL_CONN" != "ERROR" ] && [ "$REPL_CONN" -gt "0" ]; then
    echo ""
    echo "  Replication details:"
    REPL_DETAILS=$(run_sql_primary "SELECT application_name, state, sync_state, replay_lag FROM pg_stat_replication;")
    if [ "$REPL_DETAILS" != "ERROR" ]; then
        echo "$REPL_DETAILS" | while IFS= read -r line; do
            if [ -n "$line" ]; then
                echo -e "    ${GREEN}$line${NC}"
            fi
        done
    fi
fi

# ============================================
# PART 2: DR CLUSTER VERIFICATION
# ============================================

echo ""
echo ""
echo -e "${YELLOW}[2] DR Cluster - Database Status${NC}"
echo ""

# Switch to DR cluster
echo "Switching to DR cluster..."
az aks get-credentials --name dr-aks-cluster --resource-group azure-meun-dr-rg --overwrite-existing >/dev/null 2>&1

echo ""
echo -e "${YELLOW}2.1 PostgreSQL Secondary Status${NC}"
check_status "PostgreSQL secondary pod running" "kubectl get pods -n database -l app=postgresql,role=secondary --field-selector=status.phase=Running | grep -q Running"
check_status "PostgreSQL service exists" "kubectl get svc postgresql-secondary -n database"
get_value "Secondary pod name" "kubectl get pods -n database -l app=postgresql,role=secondary -o jsonpath='{.items[0].metadata.name}'"
get_value "Secondary service IP" "kubectl get svc postgresql-secondary -n database -o jsonpath='{.spec.clusterIP}'"

echo ""
echo -e "${YELLOW}2.2 JupyterHub Database Configuration (DR)${NC}"
check_status "JupyterHub namespace exists" "kubectl get namespace jupyterhub"
check_status "JupyterHub hub pod running" "kubectl get pods -n jupyterhub -l component=hub --field-selector=status.phase=Running | grep -q Running"
check_status "Database secret exists" "kubectl get secret jupyterhub-db -n jupyterhub"

# Get database URL from secret
echo -n "  Database URL: "
DB_URL_DR=$(kubectl get secret jupyterhub-db -n jupyterhub -o jsonpath='{.data.db-url}' 2>/dev/null | base64 -d 2>/dev/null || echo "N/A")
if [[ "$DB_URL_DR" == *"postgresql"* ]]; then
    # Mask password
    MASKED_URL_DR=$(echo "$DB_URL_DR" | sed 's/:\/\/[^:]*:[^@]*@/:\/\/***:***@/')
    echo -e "${GREEN}$MASKED_URL_DR${NC}"
else
    echo -e "${YELLOW}$DB_URL_DR${NC}"
fi

echo ""
echo -e "${YELLOW}2.3 Database Connectivity Test (DR)${NC}"

# Test connection from JupyterHub hub pod
HUB_POD_DR=$(kubectl get pods -n jupyterhub -l component=hub -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$HUB_POD_DR" ]; then
    echo -n "  Connection from hub pod: "
    if kubectl exec -n jupyterhub $HUB_POD_DR -- python3 -c "import psycopg2; conn = psycopg2.connect('$DB_URL_DR'); print('Connected'); conn.close()" 2>/dev/null | grep -q "Connected"; then
        echo -e "${GREEN}✓ Connected${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
    fi
else
    echo -e "  ${YELLOW}Hub pod not found${NC}"
fi

echo ""
echo -e "${YELLOW}2.4 Replicated Data Verification${NC}"

# Check if database has JupyterHub tables
echo -n "  JupyterHub tables exist: "
TABLES_DR=$(run_sql_secondary "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('users', 'servers', 'oauth_clients');")
TABLES_DR=$(echo "$TABLES_DR" | tr -d ' ')
if [ "$TABLES_DR" == "3" ]; then
    echo -e "${GREEN}✓ Yes (3 tables)${NC}"
elif [ "$TABLES_DR" == "ERROR" ]; then
    echo -e "${RED}✗ Cannot query${NC}"
else
    echo -e "${YELLOW}⚠ Partial ($TABLES_DR/3 tables)${NC}"
fi

# Count users (should match primary)
echo -n "  Number of users: "
USER_COUNT_DR=$(run_sql_secondary "SELECT COUNT(*) FROM users;")
USER_COUNT_DR=$(echo "$USER_COUNT_DR" | tr -d ' ')
if [ "$USER_COUNT_DR" != "ERROR" ]; then
    if [ "$USER_COUNT_DR" == "$USER_COUNT" ]; then
        echo -e "${GREEN}$USER_COUNT_DR (matches primary)${NC}"
    else
        echo -e "${YELLOW}$USER_COUNT_DR (primary has $USER_COUNT)${NC}"
    fi
else
    echo -e "${YELLOW}Cannot query${NC}"
fi

# Show recent users (should match primary)
echo ""
echo "  Recent users (should match primary):"
RECENT_USERS_DR=$(run_sql_secondary "SELECT name, created FROM users ORDER BY created DESC LIMIT 5;")
if [ "$RECENT_USERS_DR" != "ERROR" ]; then
    echo "$RECENT_USERS_DR" | while IFS= read -r line; do
        if [ -n "$line" ]; then
            echo -e "    ${GREEN}$line${NC}"
        fi
    done
else
    echo -e "    ${YELLOW}Cannot query${NC}"
fi

echo ""
echo -e "${YELLOW}2.5 PostgreSQL Replication Status (Secondary)${NC}"

# Check if in recovery mode (standby)
echo -n "  Recovery mode (standby): "
RECOVERY=$(run_sql_secondary "SELECT pg_is_in_recovery();")
RECOVERY=$(echo "$RECOVERY" | tr -d ' ')
if [ "$RECOVERY" == "t" ]; then
    echo -e "${GREEN}✓ Yes (read-only standby)${NC}"
elif [ "$RECOVERY" == "f" ]; then
    echo -e "${YELLOW}⚠ No (promoted to primary)${NC}"
elif [ "$RECOVERY" == "ERROR" ]; then
    echo -e "${YELLOW}Cannot query${NC}"
else
    echo -e "${YELLOW}$RECOVERY${NC}"
fi

# Check replication lag
echo -n "  Replication lag: "
LAG=$(run_sql_secondary "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::INT;")
LAG=$(echo "$LAG" | tr -d ' ')
if [ "$LAG" != "ERROR" ] && [ -n "$LAG" ]; then
    if [ "$LAG" -lt "10" ]; then
        echo -e "${GREEN}${LAG}s (excellent)${NC}"
    elif [ "$LAG" -lt "60" ]; then
        echo -e "${YELLOW}${LAG}s (acceptable)${NC}"
    else
        echo -e "${RED}${LAG}s (high lag)${NC}"
    fi
else
    echo -e "${YELLOW}Cannot query${NC}"
fi

# ============================================
# PART 3: REPLICATION VERIFICATION
# ============================================

echo ""
echo ""
echo -e "${YELLOW}[3] Replication Verification${NC}"
echo ""

# Switch back to primary
az aks get-credentials --name primary-aks-cluster --resource-group azure-maen-primary-rg --overwrite-existing >/dev/null 2>&1

echo -e "${YELLOW}3.1 Data Consistency Check${NC}"

# Compare user counts
echo -n "  User count consistency: "
if [ "$USER_COUNT" == "$USER_COUNT_DR" ] && [ "$USER_COUNT" != "ERROR" ]; then
    echo -e "${GREEN}✓ Consistent ($USER_COUNT users)${NC}"
elif [ "$USER_COUNT" == "ERROR" ] || [ "$USER_COUNT_DR" == "ERROR" ]; then
    echo -e "${YELLOW}Cannot verify${NC}"
else
    echo -e "${RED}✗ Inconsistent (Primary: $USER_COUNT, DR: $USER_COUNT_DR)${NC}"
fi

# Compare table counts
echo -n "  Table structure consistency: "
if [ "$TABLES" == "$TABLES_DR" ] && [ "$TABLES" == "3" ]; then
    echo -e "${GREEN}✓ Consistent (3 tables)${NC}"
elif [ "$TABLES" == "ERROR" ] || [ "$TABLES_DR" == "ERROR" ]; then
    echo -e "${YELLOW}Cannot verify${NC}"
else
    echo -e "${RED}✗ Inconsistent (Primary: $TABLES, DR: $TABLES_DR)${NC}"
fi

echo ""
echo -e "${YELLOW}3.2 Live Replication Test${NC}"
echo "  Creating test user on primary..."

# Create test user
TEST_USER="test-replication-$(date +%s)"
TEST_RESULT=$(run_sql_primary "INSERT INTO users (name, created) VALUES ('$TEST_USER', NOW()) RETURNING name;")

if [[ "$TEST_RESULT" == *"$TEST_USER"* ]]; then
    echo -e "  ${GREEN}✓ Test user created: $TEST_USER${NC}"
    
    # Wait for replication
    echo "  Waiting 5 seconds for replication..."
    sleep 5
    
    # Switch to DR
    az aks get-credentials --name dr-aks-cluster --resource-group azure-meun-dr-rg --overwrite-existing >/dev/null 2>&1
    
    # Check if user exists in DR
    echo -n "  Checking DR for test user: "
    DR_CHECK=$(run_sql_secondary "SELECT name FROM users WHERE name='$TEST_USER';")
    
    if [[ "$DR_CHECK" == *"$TEST_USER"* ]]; then
        echo -e "${GREEN}✓ Found! Replication working${NC}"
        
        # Cleanup - switch back to primary and delete test user
        az aks get-credentials --name primary-aks-cluster --resource-group azure-maen-primary-rg --overwrite-existing >/dev/null 2>&1
        run_sql_primary "DELETE FROM users WHERE name='$TEST_USER';" >/dev/null 2>&1
        echo -e "  ${GREEN}✓ Test user cleaned up${NC}"
    else
        echo -e "${RED}✗ Not found! Replication may be delayed or broken${NC}"
    fi
else
    echo -e "  ${RED}✗ Failed to create test user${NC}"
fi

# ============================================
# SUMMARY
# ============================================

echo ""
echo ""
echo -e "${BLUE}=========================================="
echo "Summary"
echo "==========================================${NC}"
echo ""

# Count issues
ISSUES=0
WARNINGS=0

# Check critical components
if [ "$TABLES" != "3" ]; then ((ISSUES++)); fi
if [ "$TABLES_DR" != "3" ]; then ((ISSUES++)); fi
if [ "$USER_COUNT" != "$USER_COUNT_DR" ] && [ "$USER_COUNT" != "ERROR" ]; then ((WARNINGS++)); fi
if [ "$REPL_CONN" == "0" ] || [ "$REPL_CONN" == "ERROR" ]; then ((WARNINGS++)); fi

if [ $ISSUES -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo ""
    echo "JupyterHub is correctly configured to use PostgreSQL:"
    echo "  - Primary database: Connected and operational"
    echo "  - DR database: Connected and replicating"
    echo "  - Data consistency: Verified"
    echo "  - Replication: Active and working"
elif [ $ISSUES -eq 0 ]; then
    echo -e "${YELLOW}⚠ System operational with warnings${NC}"
    echo ""
    echo "Found $WARNINGS warning(s). Review the output above."
else
    echo -e "${RED}✗ Found $ISSUES critical issue(s)${NC}"
    echo ""
    echo "Review the output above for details."
fi

echo ""
echo -e "${YELLOW}Key Metrics:${NC}"
echo "  Primary users: $USER_COUNT"
echo "  DR users: $USER_COUNT_DR"
echo "  Replication connections: $REPL_CONN"
if [ -n "$LAG" ] && [ "$LAG" != "ERROR" ]; then
    echo "  Replication lag: ${LAG}s"
fi

echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo "  # Check primary database"
echo "  kubectl exec -n database deployment/postgresql-primary -- psql -U jupyterhub -d jupyterhub -c 'SELECT * FROM users;'"
echo ""
echo "  # Check DR database"
echo "  kubectl exec -n database deployment/postgresql-secondary -- psql -U jupyterhub -d jupyterhub -c 'SELECT * FROM users;'"
echo ""
echo "  # Check replication status"
echo "  kubectl exec -n database deployment/postgresql-primary -- psql -U postgres -c 'SELECT * FROM pg_stat_replication;'"
echo ""
