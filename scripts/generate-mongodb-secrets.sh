#!/bin/bash

# Generate Kubernetes Secrets from MongoDB Configuration
# This script reads the MongoDB configuration and creates Kubernetes secrets

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration files
CONFIG_DIR="config"
LOCAL_CONFIG_FILE="$CONFIG_DIR/mongodb-config.local.env"
NAMESPACE="odl-demo"

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if local config exists
if [ ! -f "$LOCAL_CONFIG_FILE" ]; then
    print_error "Local configuration file not found: $LOCAL_CONFIG_FILE"
    print_status "Please run './scripts/configure-mongodb.sh' first to set up your MongoDB configuration."
    exit 1
fi

# Source the configuration
print_status "Loading MongoDB configuration from $LOCAL_CONFIG_FILE"
source "$LOCAL_CONFIG_FILE"

# Validate required variables
required_vars=("MONGO_CLUSTER1_URI" "MONGO_CLUSTER2_URI" "MONGO_PASSWORD")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        print_error "Required variable $var is not set in $LOCAL_CONFIG_FILE"
        exit 1
    fi
done

print_status "Creating Kubernetes secrets for MongoDB Atlas connections..."

# Create namespace if it doesn't exist
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Delete existing secret if it exists
kubectl delete secret mongodb-secrets -n "$NAMESPACE" --ignore-not-found=true

# Create the secret
kubectl create secret generic mongodb-secrets \
    --from-literal=cluster1-uri="$MONGO_CLUSTER1_URI" \
    --from-literal=cluster2-uri="$MONGO_CLUSTER2_URI" \
    --from-literal=mongo-password="$MONGO_PASSWORD" \
    -n "$NAMESPACE"

print_success "Kubernetes secret 'mongodb-secrets' created successfully in namespace '$NAMESPACE'"

# Verify the secret
print_status "Verifying secret creation..."
kubectl get secret mongodb-secrets -n "$NAMESPACE" -o yaml | grep -E "(cluster1-uri|cluster2-uri|mongo-password)" | head -3

print_success "MongoDB secrets are ready for deployment!"
echo ""
print_status "You can now deploy the ODL demo with:"
echo "  ./scripts/deploy-hostnetwork.sh"
echo "  or"
echo "  ./scripts/deploy.sh"
