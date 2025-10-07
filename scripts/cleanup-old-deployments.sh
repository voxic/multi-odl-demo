#!/bin/bash

# Cleanup script to remove old ConfigMap-based deployments
# This script removes the old approach and prepares for Docker-based deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Change to project root
cd "$PROJECT_ROOT"

print_status "Cleaning up old ConfigMap-based deployments..."

# Check if namespace exists
if ! kubectl get namespace odl-demo > /dev/null 2>&1; then
    print_warning "Namespace 'odl-demo' does not exist. Nothing to clean up."
    exit 0
fi

print_status "Removing old microservice deployments..."

# Remove old deployments
services=("aggregation-service" "customer-profile-service" "analytics-ui" "legacy-ui")

for service in "${services[@]}"; do
    if kubectl get deployment $service -n odl-demo > /dev/null 2>&1; then
        print_status "Removing deployment: $service"
        kubectl delete deployment $service -n odl-demo --ignore-not-found=true
    fi
    
    if kubectl get service $service -n odl-demo > /dev/null 2>&1; then
        print_status "Removing service: $service"
        kubectl delete service $service -n odl-demo --ignore-not-found=true
    fi
done

print_status "Removing old ConfigMaps..."

# Remove old ConfigMaps
configmaps=("aggregation-source" "customer-profile-source" "analytics-ui-source")

for configmap in "${configmaps[@]}"; do
    if kubectl get configmap $configmap -n odl-demo > /dev/null 2>&1; then
        print_status "Removing ConfigMap: $configmap"
        kubectl delete configmap $configmap -n odl-demo --ignore-not-found=true
    fi
done

print_status "Cleaning up Docker images..."

# Remove old Docker images (optional)
if command -v docker &> /dev/null; then
    print_status "Removing old Docker images..."
    docker rmi aggregation-service:latest 2>/dev/null || true
    docker rmi customer-profile-service:latest 2>/dev/null || true
    docker rmi analytics-ui:latest 2>/dev/null || true
    docker rmi legacy-ui:latest 2>/dev/null || true
fi

print_success "Cleanup completed!"
echo ""
echo "✅ Old ConfigMap-based deployments removed"
echo "✅ Old Docker images cleaned up"
echo ""
echo "🚀 You can now deploy using the new Docker-based approach:"
echo "   ./scripts/deploy-complete.sh"
echo ""
echo "📝 Or step by step:"
echo "   1. ./scripts/build-microservices.sh"
echo "   2. ./scripts/deploy-microservices.sh"
