#!/bin/bash

# Build and deploy microservices using Docker images
# This script builds proper Docker images instead of using ConfigMaps

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

print_status "Building microservices Docker images..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

# Create namespace if it doesn't exist
print_status "Creating namespace..."
kubectl create namespace odl-demo --dry-run=client -o yaml | kubectl apply -f -

# Build aggregation service
print_status "Building aggregation service..."
cd microservices/aggregation-service
docker build -t aggregation-service:latest .
print_success "Aggregation service image built"

# Build customer profile service
print_status "Building customer profile service..."
cd ../customer-profile-service
docker build -t customer-profile-service:latest .
print_success "Customer profile service image built"

# Build analytics UI
print_status "Building analytics UI..."
cd ../analytics-ui
docker build -t analytics-ui:latest .
print_success "Analytics UI image built"

# Build legacy UI
print_status "Building legacy UI..."
cd ../legacy-ui
docker build -t legacy-ui:latest .
print_success "Legacy UI image built"

# Go back to project root
cd "$PROJECT_ROOT"

# Load images into MicroK8s (if using MicroK8s)
if command -v microk8s &> /dev/null; then
    print_status "Loading images into MicroK8s..."
    microk8s ctr images import <(docker save aggregation-service:latest)
    microk8s ctr images import <(docker save customer-profile-service:latest)
    microk8s ctr images import <(docker save analytics-ui:latest)
    microk8s ctr images import <(docker save legacy-ui:latest)
    print_success "Images loaded into MicroK8s"
else
    print_warning "MicroK8s not detected. Make sure your Kubernetes cluster can access the Docker images."
fi

print_success "All microservices built successfully!"
print_status "You can now deploy using: ./scripts/deploy-microservices.sh"
