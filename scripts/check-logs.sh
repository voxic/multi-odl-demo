#!/bin/bash

# ODL Demo Log Checker
# This script helps diagnose issues by showing logs from all components

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

print_status() {
    echo -e "${GREEN}[$(get_timestamp)] [INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[$(get_timestamp)] [WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[$(get_timestamp)] [ERROR]${NC} $1"
}

NAMESPACE="odl-demo"

echo "[$(get_timestamp)] 🔍 ODL Demo Log Checker"
echo "[$(get_timestamp)] ======================="

# Check if namespace exists
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    print_error "Namespace '$NAMESPACE' not found"
    exit 1
fi

# Show pod status
print_status "Current pod status:"
kubectl get pods -n $NAMESPACE

echo ""

# Check each component
COMPONENTS=("mysql" "kafka" "kafka-connect" "aggregation-service")

for component in "${COMPONENTS[@]}"; do
    echo "=========================================="
    print_status "Checking $component logs..."
    echo "=========================================="
    
    # Get pods for this component
    PODS=$(kubectl get pods -n $NAMESPACE -l app=$component -o jsonpath='{.items[*].metadata.name}')
    
    if [ -z "$PODS" ]; then
        print_warning "No pods found for $component"
        continue
    fi
    
    for pod in $PODS; do
        echo ""
        print_status "Pod: $pod"
        echo "----------------------------------------"
        
        # Check if pod is running
        STATUS=$(kubectl get pod $pod -n $NAMESPACE -o jsonpath='{.status.phase}')
        echo "Status: $STATUS"
        
        if [ "$STATUS" != "Running" ]; then
            print_warning "Pod $pod is not running (Status: $STATUS)"
            echo "Events:"
            kubectl describe pod $pod -n $NAMESPACE | grep -A 10 "Events:"
        fi
        
        # Show recent logs
        echo ""
        echo "Recent logs (last 20 lines):"
        echo "----------------------------------------"
        kubectl logs $pod -n $NAMESPACE --tail=20 --timestamps || print_warning "Could not get logs for $pod"
        
        # If pod crashed, show previous logs
        if [ "$STATUS" != "Running" ]; then
            echo ""
            echo "Previous container logs (if available):"
            echo "----------------------------------------"
            kubectl logs $pod -n $NAMESPACE --previous --tail=20 --timestamps 2>/dev/null || print_warning "No previous logs available for $pod"
        fi
    done
done

echo ""
print_status "Log check complete!"
echo ""
print_status "To follow logs in real-time, use:"
echo "kubectl logs -f <pod-name> -n $NAMESPACE"
echo ""
print_status "To get detailed pod information:"
echo "kubectl describe pod <pod-name> -n $NAMESPACE"
