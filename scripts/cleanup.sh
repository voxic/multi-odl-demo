#!/bin/bash

# ODL Demo Cleanup Script
# This script removes all deployed resources

set -e

echo "[$(get_timestamp)] 🧹 Starting ODL Demo Cleanup..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to print colored output with timestamps
print_status() {
    echo -e "${GREEN}[$(get_timestamp)] [INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[$(get_timestamp)] [WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[$(get_timestamp)] [ERROR]${NC} $1"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Delete all resources in odl-demo namespace
print_status "Deleting all resources in odl-demo namespace..."

# Delete deployments
kubectl delete deployment mysql kafka zookeeper kafka-connect aggregation-service -n odl-demo --ignore-not-found=true

# Delete services
kubectl delete service mysql-service kafka-service zookeeper-service kafka-connect-service aggregation-service -n odl-demo --ignore-not-found=true

# Delete load balancer services (both in default and odl-demo namespaces)
kubectl delete service mysql-loadbalancer kafka-ui-loadbalancer --ignore-not-found=true
kubectl delete service mysql-loadbalancer kafka-ui-loadbalancer -n odl-demo --ignore-not-found=true

# Delete PVCs
kubectl delete pvc mysql-pvc kafka-pvc zookeeper-pvc -n odl-demo --ignore-not-found=true

# Delete secrets
kubectl delete secret mysql-secret mongodb-secrets -n odl-demo --ignore-not-found=true

# Delete configmaps
kubectl delete configmap mysql-config mysql-init-scripts kafka-config zookeeper-config aggregation-source -n odl-demo --ignore-not-found=true

# Delete namespace
print_status "Deleting odl-demo namespace..."
kubectl delete namespace odl-demo --ignore-not-found=true

print_status "🎉 Cleanup completed successfully!"

echo ""
print_status "All ODL demo resources have been removed."
print_status "To verify, run: kubectl get all -A | grep odl-demo"
