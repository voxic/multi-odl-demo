#!/bin/bash

# ODL Demo Cleanup Script
# This script removes all deployed resources and MongoDB Atlas collections
#
# Usage: ./scripts/cleanup.sh
#
# Features:
# - Removes all Kubernetes resources (deployments, services, PVCs, secrets, configmaps)
# - Optionally cleans up MongoDB Atlas collections (customers, accounts, transactions, agreements, customer_analytics)
# - Requires MongoDB configuration file: config/mongodb-config.local.env
# - Requires mongosh (MongoDB Shell) for MongoDB Atlas cleanup
#
# Prerequisites:
# - kubectl installed and configured
# - MongoDB configuration: ./scripts/configure-mongodb.sh
# - mongosh installed (for MongoDB Atlas cleanup): https://docs.mongodb.com/mongodb-shell/install/

set -e

echo "[$(get_timestamp)] 🧹 Starting ODL Demo Cleanup..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_info() {
    echo -e "${BLUE}[$(get_timestamp)] [INFO]${NC} $1"
}

# MongoDB Atlas cleanup functions
cleanup_mongodb_atlas() {
    local config_file="config/mongodb-config.local.env"
    
    # Check if MongoDB configuration exists
    if [ ! -f "$config_file" ]; then
        print_warning "MongoDB configuration file not found: $config_file"
        print_info "Skipping MongoDB Atlas cleanup. Run './scripts/configure-mongodb.sh' to set up MongoDB configuration."
        return 0
    fi
    
    print_info "Found MongoDB configuration file: $config_file"
    
    # Source the configuration file
    source "$config_file"
    
    # Check if required variables are set
    if [ -z "$MONGO_CLUSTER1_URI" ] || [ -z "$MONGO_CLUSTER2_URI" ]; then
        print_error "MongoDB connection strings not found in configuration file"
        return 1
    fi
    
    print_warning "⚠️  MongoDB Atlas Collection Cleanup"
    echo "This will delete ALL data from the following MongoDB Atlas collections:"
    echo ""
    echo "Cluster 1 (Banking Database):"
    echo "  - customers"
    echo "  - accounts" 
    echo "  - transactions"
    echo "  - agreements"
    echo ""
    echo "Cluster 2 (Analytics Database):"
    echo "  - customer_analytics"
    echo ""
    echo "⚠️  WARNING: This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to delete all MongoDB Atlas collections? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "MongoDB Atlas cleanup cancelled by user"
        return 0
    fi
    
    # Check if mongosh is available
    if ! command -v mongosh &> /dev/null; then
        print_error "mongosh (MongoDB Shell) is not installed or not in PATH"
        print_info "Please install MongoDB Shell to enable MongoDB Atlas cleanup"
        print_info "Visit: https://docs.mongodb.com/mongodb-shell/install/"
        return 1
    fi
    
    print_status "Starting MongoDB Atlas collection cleanup..."
    
    # Cleanup Cluster 1 (Banking Database)
    print_info "Cleaning up Cluster 1 (Banking Database)..."
    cleanup_cluster_collections "$MONGO_CLUSTER1_URI" "banking" "customers accounts transactions agreements"
    
    # Cleanup Cluster 2 (Analytics Database)  
    print_info "Cleaning up Cluster 2 (Analytics Database)..."
    cleanup_cluster_collections "$MONGO_CLUSTER2_URI" "analytics" "customer_analytics"
    
    print_success "MongoDB Atlas collection cleanup completed!"
}

cleanup_cluster_collections() {
    local uri="$1"
    local database="$2"
    local collections="$3"
    
    print_info "Connecting to database: $database"
    
    for collection in $collections; do
        print_info "Dropping collection: $collection"
        
        # Use mongosh to drop the collection
        if mongosh "$uri" --eval "use $database; db.$collection.drop()" --quiet; then
            print_status "✓ Dropped collection: $collection"
        else
            print_warning "⚠ Failed to drop collection: $collection (may not exist)"
        fi
    done
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Ask user if they want to clean up MongoDB Atlas collections
echo ""
print_info "MongoDB Atlas Collection Cleanup"
echo "====================================="
echo "This script can also clean up MongoDB Atlas collections used by the ODL demo."
echo "This includes all data in the banking and analytics databases."
echo ""
read -p "Do you want to clean up MongoDB Atlas collections? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cleanup_mongodb_atlas
fi

# Delete all resources in odl-demo namespace
print_status "Deleting all resources in odl-demo namespace..."

# Delete deployments
kubectl delete deployment mysql kafka zookeeper kafka-connect aggregation-service customer-profile-service analytics-ui legacy-ui -n odl-demo --ignore-not-found=true

# Delete services
kubectl delete service mysql-service kafka-service zookeeper-service kafka-connect-service aggregation-service customer-profile-service analytics-ui-service legacy-ui-service -n odl-demo --ignore-not-found=true

# Delete load balancer services (both in default and odl-demo namespaces)
kubectl delete service mysql-loadbalancer kafka-ui-loadbalancer --ignore-not-found=true
kubectl delete service mysql-loadbalancer kafka-ui-loadbalancer -n odl-demo --ignore-not-found=true

# Delete PVCs
kubectl delete pvc mysql-pvc kafka-pvc zookeeper-pvc -n odl-demo --ignore-not-found=true

# Delete secrets
kubectl delete secret mysql-secret mongodb-secrets -n odl-demo --ignore-not-found=true

# Delete configmaps
kubectl delete configmap mysql-config mysql-init-scripts kafka-config zookeeper-config aggregation-source customer-profile-source -n odl-demo --ignore-not-found=true

# Delete namespace
print_status "Deleting odl-demo namespace..."
kubectl delete namespace odl-demo --ignore-not-found=true

print_status "🎉 Cleanup completed successfully!"

echo ""
print_status "All ODL demo resources have been removed."
print_status "To verify, run: kubectl get all -A | grep odl-demo"
