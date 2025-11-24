#!/bin/bash
# Verify PostgreSQL Database Replication Health
# This script verifies database replication between primary and DR regions

set -e

# Output formatting removed for compatibility

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Kubernetes settings
PRIMARY_CONTEXT="primary-aks-cluster"
DR_CONTEXT="dr-aks-cluster"
NAMESPACE_DATABASE="database"      # PostgreSQL namespace
NAMESPACE_DEFAULT="default"        # Microservices namespace
PRIMARY_POD="postgresql-primary-0"
SECONDARY_POD="postgresql-secondary-0"
DB_USER="postgres"

# Thresholds (in seconds)
WARNING_THRESHOLD=10
CRITICAL_THRESHOLD=30

# Exit codes for monitoring integration
EXIT_OK=0
EXIT_WARNING=1
EXIT_CRITICAL=2

# Function to print output
print_info() {
    echo "[INFO] $1"
}

print_warning() {
    echo "[WARNING] $1"
}

print_error() {
    echo "[ERROR] $1"
}

print_success() {
    echo "[SUCCESS] $1"
}

print_critical() {
    echo "[CRITICAL] $1"
}

# Function to check prerequisites
check_prerequisites() {
    local missing_tools=()
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"
        exit $EXIT_CRITICAL
    fi
    
    # Check if contexts exist
    if ! kubectl config get-contexts "$PRIMARY_CONTEXT" &> /dev/null; then
        print_error "Primary context '$PRIMARY_CONTEXT' not found"
        echo ""
        echo "Please deploy primary region first: ./scripts/deploy_primary.sh"
        exit $EXIT_CRITICAL
    fi
    
    if ! kubectl config get-contexts "$DR_CONTEXT" &> /dev/null; then
        print_error "DR context '$DR_CONTEXT' not found"
        echo ""
        echo "Please deploy DR region first: ./scripts/deploy_dr.sh"
        exit $EXIT_CRITICAL
    fi
}

# Function to check if primary database is accessible
check_primary_database() {
    kubectl config use-context "$PRIMARY_CONTEXT" &> /dev/null
    
    if ! kubectl get pod "$PRIMARY_POD" --namespace="$NAMESPACE_DATABASE" &> /dev/null; then
        print_error "Primary database pod not found: $PRIMARY_POD"
        exit $EXIT_CRITICAL
    fi
    
    local pod_status=$(kubectl get pod "$PRIMARY_POD" --namespace="$NAMESPACE_DATABASE" -o jsonpath='{.status.phase}')
    if [ "$pod_status" != "Running" ]; then
        print_error "Primary database is not running (status: $pod_status)"
        exit $EXIT_CRITICAL
    fi
}

# Function to check if secondary database is accessible
check_secondary_database() {
    kubectl config use-context "$DR_CONTEXT" &> /dev/null
    
    if ! kubectl get pod "$SECONDARY_POD" --namespace="$NAMESPACE_DATABASE" &> /dev/null; then
        print_error "Secondary database pod not found: $SECONDARY_POD"
        exit $EXIT_CRITICAL
    fi
    
    local pod_status=$(kubectl get pod "$SECONDARY_POD" --namespace="$NAMESPACE_DATABASE" -o jsonpath='{.status.phase}')
    if [ "$pod_status" != "Running" ]; then
        print_error "Secondary database is not running (status: $pod_status)"
        exit $EXIT_CRITICAL
    fi
}

# Function to insert test record in primary
insert_test_record() {
    kubectl config use-context "$PRIMARY_CONTEXT" &> /dev/null
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Create test table if it doesn't exist
    kubectl exec "$PRIMARY_POD" --namespace="$NAMESPACE_DATABASE" -- psql -U "$DB_USER" -d postgres -c "
        CREATE TABLE IF NOT EXISTS replication_test (
            id SERIAL PRIMARY KEY,
            test_timestamp TIMESTAMP,
            test_data TEXT
        );
    " &> /dev/null
    
    # Insert test record
    kubectl exec "$PRIMARY_POD" --namespace="$NAMESPACE_DATABASE" -- psql -U "$DB_USER" -d postgres -c "
        INSERT INTO replication_test (test_timestamp, test_data) 
        VALUES ('$timestamp', 'replication_check');
    " &> /dev/null
    
    echo "$timestamp"
}

# Function to get replication status from primary
get_replication_status() {
    kubectl config use-context "$PRIMARY_CONTEXT" &> /dev/null
    
    local repl_info=$(kubectl exec "$PRIMARY_POD" --namespace="$NAMESPACE_DATABASE" -- psql -U "$DB_USER" -d postgres -t -A -F'|' -c "
        SELECT 
            application_name,
            state,
            sync_state,
            pg_current_wal_lsn() as current_lsn,
            sent_lsn,
            write_lsn,
            flush_lsn,
            replay_lsn,
            COALESCE(EXTRACT(EPOCH FROM (now() - reply_time)), 0) as lag_seconds
        FROM pg_stat_replication 
        WHERE application_name = 'secondary';
    " 2>/dev/null)
    
    echo "$repl_info"
}

# Function to verify secondary is in recovery mode
verify_secondary_recovery() {
    kubectl config use-context "$DR_CONTEXT" &> /dev/null
    
    local is_recovery=$(kubectl exec "$SECONDARY_POD" --namespace="$NAMESPACE_DATABASE" -- psql -U "$DB_USER" -d postgres -t -A -c "
        SELECT pg_is_in_recovery();
    " 2>/dev/null)
    
    echo "$is_recovery"
}

# Function to get secondary LSN positions
get_secondary_lsn() {
    kubectl config use-context "$DR_CONTEXT" &> /dev/null
    
    local lsn_info=$(kubectl exec "$SECONDARY_POD" --namespace="$NAMESPACE_DATABASE" -- psql -U "$DB_USER" -d postgres -t -A -F'|' -c "
        SELECT 
            pg_last_wal_receive_lsn() as receive_lsn,
            pg_last_wal_replay_lsn() as replay_lsn,
            EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) as replay_lag_seconds
        WHERE pg_is_in_recovery();
    " 2>/dev/null)
    
    echo "$lsn_info"
}

# Function to verify test record in secondary
verify_test_record() {
    local test_timestamp="$1"
    local max_wait=10
    local wait_count=0
    
    kubectl config use-context "$DR_CONTEXT" &> /dev/null
    
    while [ $wait_count -lt $max_wait ]; do
        local record_exists=$(kubectl exec "$SECONDARY_POD" --namespace="$NAMESPACE_DATABASE" -- psql -U "$DB_USER" -d postgres -t -A -c "
            SELECT COUNT(*) FROM replication_test WHERE test_timestamp = '$test_timestamp';
        " 2>/dev/null || echo "0")
        
        if [ "$record_exists" -ge "1" ]; then
            echo "true"
            return 0
        fi
        
        sleep 1
        wait_count=$((wait_count + 1))
    done
    
    echo "false"
}

# Function to calculate replication lag
calculate_replication_lag() {
    local primary_lsn="$1"
    local secondary_lsn="$2"
    
    kubectl config use-context "$PRIMARY_CONTEXT" &> /dev/null
    
    local lag_bytes=$(kubectl exec "$PRIMARY_POD" --namespace="$NAMESPACE_DATABASE" -- psql -U "$DB_USER" -d postgres -t -A -c "
        SELECT pg_wal_lsn_diff('$primary_lsn', '$secondary_lsn');
    " 2>/dev/null || echo "0")
    
    echo "$lag_bytes"
}

# Function to format bytes to human readable
format_bytes() {
    local bytes=$1
    
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes}B"
    elif [ "$bytes" -lt 1048576 ]; then
        echo "$((bytes / 1024))KB"
    else
        echo "$((bytes / 1048576))MB"
    fi
}

# Function to display manual verification queries
display_manual_verification() {
    echo ""
    echo "=========================================="
    echo "MANUAL VERIFICATION QUERIES"
    echo "=========================================="
    echo ""
    echo "On Primary Database:"
    echo "--------------------"
    echo "# Check replication status"
    echo "kubectl config use-context $PRIMARY_CONTEXT"
    echo "kubectl exec $PRIMARY_POD -- psql -U $DB_USER -c 'SELECT * FROM pg_stat_replication;'"
    echo ""
    echo "# Check current WAL LSN"
    echo "kubectl exec $PRIMARY_POD -- psql -U $DB_USER -c 'SELECT pg_current_wal_lsn();'"
    echo ""
    echo "# Check replication slots"
    echo "kubectl exec $PRIMARY_POD -- psql -U $DB_USER -c 'SELECT * FROM pg_replication_slots;'"
    echo ""
    echo "# View replication lag"
    echo "kubectl exec $PRIMARY_POD -- psql -U $DB_USER -c \\"
    echo "  \"SELECT application_name, state, sync_state,"
    echo "   pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) as lag"
    echo "   FROM pg_stat_replication;\""
    echo ""
    echo "On Secondary Database:"
    echo "---------------------"
    echo "# Check if in recovery mode (should return 't')"
    echo "kubectl config use-context $DR_CONTEXT"
    echo "kubectl exec $SECONDARY_POD -- psql -U $DB_USER -c 'SELECT pg_is_in_recovery();'"
    echo ""
    echo "# Check last received and replayed LSN"
    echo "kubectl exec $SECONDARY_POD -- psql -U $DB_USER -c \\"
    echo "  \"SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();\""
    echo ""
    echo "# Check replay lag"
    echo "kubectl exec $SECONDARY_POD -- psql -U $DB_USER -c \\"
    echo "  \"SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;\""
    echo ""
    echo "# View recovery status"
    echo "kubectl exec $SECONDARY_POD -- psql -U $DB_USER -c \\"
    echo "  \"SELECT pg_is_in_recovery(), pg_is_wal_replay_paused();\""
    echo ""
}

# Main verification function
main() {
    local exit_code=$EXIT_OK
    local status_message="OK"
    
    echo ""
    echo "=========================================="
    echo "POSTGRESQL REPLICATION VERIFICATION"
    echo "=========================================="
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # Check prerequisites
    print_info "Checking prerequisites..."
    check_prerequisites
    
    # Check database pods
    print_info "Checking database pods..."
    check_primary_database
    check_secondary_database
    print_success "Both database pods are running"
    echo ""
    
    # Verify secondary is in recovery mode
    print_info "Verifying secondary is in recovery mode..."
    local is_recovery=$(verify_secondary_recovery)
    
    if [ "$is_recovery" = "t" ]; then
        print_success "Secondary database is in recovery mode (standby)"
    else
        print_critical "Secondary database is NOT in recovery mode"
        print_error "Secondary may have been promoted or replication is broken"
        exit_code=$EXIT_CRITICAL
        status_message="CRITICAL"
    fi
    echo ""
    
    # Get replication status from primary
    print_info "Checking replication status on primary..."
    local repl_status=$(get_replication_status)
    
    if [ -z "$repl_status" ]; then
        print_critical "No replication connection found on primary"
        print_error "Replication is not established"
        echo ""
        echo "Troubleshooting steps:"
        echo "  1. Check secondary pod logs: kubectl logs $SECONDARY_POD"
        echo "  2. Verify network connectivity between regions"
        echo "  3. Check replication user exists on primary"
        echo "  4. Verify pg_hba.conf allows replication connections"
        exit_code=$EXIT_CRITICAL
        status_message="CRITICAL"
    else
        # Parse replication status
        IFS='|' read -r app_name state sync_state current_lsn sent_lsn write_lsn flush_lsn replay_lsn lag_seconds <<< "$repl_status"
        
        print_success "Replication connection established"
        echo "  Application: $app_name"
        echo "  State: $state"
        echo "  Sync State: $sync_state"
        echo ""
        
        # Get secondary LSN info
        print_info "Checking secondary LSN positions..."
        local secondary_info=$(get_secondary_lsn)
        
        if [ -n "$secondary_info" ]; then
            IFS='|' read -r receive_lsn replay_lsn_sec replay_lag_sec <<< "$secondary_info"
            
            echo "LSN Positions:"
            echo "  Primary Current LSN:    $current_lsn"
            echo "  Primary Sent LSN:       $sent_lsn"
            echo "  Secondary Receive LSN:  $receive_lsn"
            echo "  Secondary Replay LSN:   $replay_lsn"
            echo ""
            
            # Calculate lag
            local lag_bytes=$(calculate_replication_lag "$current_lsn" "$replay_lsn")
            local lag_formatted=$(format_bytes "$lag_bytes")
            
            echo "Replication Lag:"
            echo "  Byte Lag: $lag_formatted ($lag_bytes bytes)"
            
            # Use replay lag from secondary if available
            if [ -n "$replay_lag_sec" ] && [ "$replay_lag_sec" != "" ]; then
                local replay_lag_int=$(printf "%.0f" "$replay_lag_sec" 2>/dev/null || echo "0")
                echo "  Time Lag: ${replay_lag_int}s"
                
                # Determine status based on lag
                if [ "$replay_lag_int" -ge "$CRITICAL_THRESHOLD" ]; then
                    exit_code=$EXIT_CRITICAL
                    status_message="CRITICAL"
                    print_critical "Replication lag is CRITICAL (${replay_lag_int}s >= ${CRITICAL_THRESHOLD}s)"
                elif [ "$replay_lag_int" -ge "$WARNING_THRESHOLD" ]; then
                    if [ $exit_code -eq $EXIT_OK ]; then
                        exit_code=$EXIT_WARNING
                        status_message="WARNING"
                    fi
                    print_warning "Replication lag is elevated (${replay_lag_int}s >= ${WARNING_THRESHOLD}s)"
                else
                    print_success "Replication lag is acceptable (${replay_lag_int}s < ${WARNING_THRESHOLD}s)"
                fi
            else
                echo "  Time Lag: <1s"
                print_success "Replication lag is minimal"
            fi
        fi
        echo ""
        
        # Insert test record and verify replication
        print_info "Testing replication with test record..."
        local test_timestamp=$(insert_test_record)
        print_info "Inserted test record at: $test_timestamp"
        
        print_info "Waiting for test record to replicate (max 10 seconds)..."
        local record_replicated=$(verify_test_record "$test_timestamp")
        
        if [ "$record_replicated" = "true" ]; then
            print_success "Test record successfully replicated to secondary"
        else
            print_warning "Test record not found in secondary within timeout"
            print_warning "Replication may be slow or experiencing issues"
            if [ $exit_code -eq $EXIT_OK ]; then
                exit_code=$EXIT_WARNING
                status_message="WARNING"
            fi
        fi
    fi
    
    echo ""
    echo "=========================================="
    echo "REPLICATION STATUS: $status_message"
    echo "=========================================="
    echo ""
    
    # Display summary based on status
    case $exit_code in
        $EXIT_OK)
            print_success "Replication is healthy and functioning normally"
            echo "  - Secondary is in recovery mode"
            echo "  - Replication connection is active"
            echo "  - Replication lag is within acceptable limits"
            echo "  - Test data replicates successfully"
            ;;
        $EXIT_WARNING)
            print_warning "Replication is functioning but has warnings"
            echo "  - Replication lag may be elevated"
            echo "  - Monitor closely and investigate if lag increases"
            echo "  - Consider checking network performance between regions"
            ;;
        $EXIT_CRITICAL)
            print_critical "Replication has critical issues"
            echo "  - Immediate attention required"
            echo "  - Check logs and network connectivity"
            echo "  - Review troubleshooting steps above"
            ;;
    esac
    
    echo ""
    
    # Offer to display manual verification queries
    if [ "$1" = "--show-queries" ] || [ "$1" = "-q" ]; then
        display_manual_verification
    else
        echo "For manual verification queries, run: $0 --show-queries"
        echo ""
    fi
    
    exit $exit_code
}

# Run main function
main "$@"
