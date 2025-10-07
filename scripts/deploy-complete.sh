#!/bin/bash

# Complete deployment script with Docker image building
# This script builds Docker images and deploys the entire ODL demo

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

print_status "Starting complete ODL demo deployment with Docker images..."

# Check prerequisites
print_status "Checking prerequisites..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if MongoDB configuration exists
if [ ! -f "config/mongodb-config.local.env" ]; then
    print_error "MongoDB configuration not found. Please run './scripts/configure-mongodb.sh' first."
    exit 1
fi

print_success "Prerequisites check passed"

# Build microservices
print_status "Building microservices Docker images..."
./scripts/build-microservices.sh

# Deploy infrastructure (MySQL, Kafka, etc.)
print_status "Deploying infrastructure..."
./scripts/deploy.sh

# Wait for infrastructure to be ready
print_status "Waiting for infrastructure to be ready..."
sleep 30

# Deploy microservices
print_status "Deploying microservices..."
./scripts/deploy-microservices.sh

# Deploy connectors
print_status "Deploying Kafka connectors..."
sleep 60  # Wait for Kafka Connect to be fully ready

# Check if we're using host networking
if kubectl get deployment kafka-connect -n odl-demo -o jsonpath='{.spec.template.spec.hostNetwork}' | grep -q "true"; then
    print_status "Using host networking - connectors will be deployed automatically"
    # Connectors are deployed by the main deploy script in host networking mode
else
    print_status "Deploying connectors via port-forward..."
    # Port-forward Kafka Connect and deploy connectors
    kubectl port-forward service/kafka-connect-service 8083:8083 -n odl-demo &
    PF_PID=$!
    
    # Wait for port-forward to be ready
    sleep 10
    
    # Deploy connectors
    curl -X POST -H "Content-Type: application/json" \
        --data @k8s/connectors/debezium-mysql-connector.json \
        http://localhost:8083/connectors
    
    curl -X POST -H "Content-Type: application/json" \
        --data @k8s/connectors/mongodb-atlas-connector.json \
        http://localhost:8083/connectors
    
    # Stop port-forward
    kill $PF_PID
fi

print_success "ODL demo deployment completed!"
echo ""
echo "🎉 All services are now running!"
echo ""
echo "📊 Service Status:"
kubectl get pods -n odl-demo
echo ""
echo "🌐 Access Points:"
echo "   - Legacy UI: http://localhost:3003 (or VM_IP:3003)"
echo "   - Analytics UI: http://localhost:3002 (or VM_IP:3002)"
echo "   - Kafka UI: http://localhost:8080 (or VM_IP:8080)"
echo "   - MySQL: localhost:3306 (or VM_IP:3306)"
echo ""
echo "🔧 Useful Commands:"
echo "   kubectl get pods -n odl-demo"
echo "   kubectl logs -f deployment/aggregation-service -n odl-demo"
echo "   kubectl logs -f deployment/customer-profile-service -n odl-demo"
echo ""
echo "🔄 To update microservices:"
echo "   ./scripts/build-microservices.sh && ./scripts/deploy-microservices.sh"
