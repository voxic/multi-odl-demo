#!/bin/bash

# Deploy microservices using Docker images
# This script deploys microservices that were built with proper Docker images

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

print_status "Deploying microservices using Docker images..."

# Check if required files exist
REQUIRED_FILES=(
    "k8s/microservices/aggregation-service-deployment-docker.yaml"
    "k8s/microservices/customer-profile-service-deployment-docker.yaml"
    "k8s/microservices/analytics-ui-deployment-docker.yaml"
    "k8s/microservices/legacy-ui-deployment-docker.yaml"
    "k8s/microservices/bankui-landing-deployment-docker.yaml"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        print_error "Required file not found: $file"
        exit 1
    fi
done

print_status "All required files found"

# Create namespace
print_status "Creating namespace 'odl-demo'..."
kubectl create namespace odl-demo --dry-run=client -o yaml | kubectl apply -f -

# Check if MongoDB secrets exist
if ! kubectl get secret mongodb-secrets -n odl-demo > /dev/null 2>&1; then
    print_error "MongoDB secrets not found. Please run './scripts/generate-mongodb-secrets.sh' first."
    exit 1
fi

print_status "MongoDB secrets found"

# Deploy aggregation service
print_status "Deploying aggregation service..."
kubectl apply -f k8s/microservices/aggregation-service-deployment-docker.yaml -n odl-demo

# Deploy customer profile service
print_status "Deploying customer profile service..."
kubectl apply -f k8s/microservices/customer-profile-service-deployment-docker.yaml -n odl-demo

# Deploy analytics UI
print_status "Deploying analytics UI..."
kubectl apply -f k8s/microservices/analytics-ui-deployment-docker.yaml -n odl-demo

# Deploy legacy UI
print_status "Deploying legacy UI..."
kubectl apply -f k8s/microservices/legacy-ui-deployment-docker.yaml -n odl-demo

# Deploy BankUI landing page
print_status "Deploying BankUI landing page..."
kubectl apply -f k8s/microservices/bankui-landing-deployment-docker.yaml -n odl-demo

# Wait for deployments to be ready
print_status "Waiting for deployments to be ready..."

services=("aggregation-service" "customer-profile-service" "analytics-ui" "legacy-ui" "bankui-landing")

for service in "${services[@]}"; do
    print_status "Waiting for $service..."
    if kubectl wait --for=condition=available --timeout=300s deployment/$service -n odl-demo; then
        print_success "$service is ready"
    else
        print_error "$service deployment failed"
        print_status "$service pod status:"
        kubectl get pods -n odl-demo -l app=$service
        print_status "$service pod logs:"
        kubectl logs -n odl-demo -l app=$service --tail=50
        exit 1
    fi
done

# Get service information
print_success "All microservices deployed successfully!"
echo ""
echo "📊 Service Status:"
kubectl get pods -n odl-demo -l 'app in (aggregation-service,customer-profile-service,analytics-ui,legacy-ui,bankui-landing)'
echo ""
echo "🌐 Services:"
kubectl get services -n odl-demo -l 'app in (aggregation-service,customer-profile-service,analytics-ui,legacy-ui,bankui-landing)'
echo ""
echo "🔧 To check logs:"
echo "   kubectl logs -f deployment/aggregation-service -n odl-demo"
echo "   kubectl logs -f deployment/customer-profile-service -n odl-demo"
echo "   kubectl logs -f deployment/analytics-ui -n odl-demo"
echo "   kubectl logs -f deployment/legacy-ui -n odl-demo"
echo "   kubectl logs -f deployment/bankui-landing -n odl-demo"
echo ""
echo "🔄 To update services:"
echo "   1. ./scripts/build-microservices.sh"
echo "   2. ./scripts/deploy-microservices.sh"
