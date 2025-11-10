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

# Optional: Generate package-lock.json files for reproducible builds
if [ "$1" = "--with-locks" ]; then
    print_status "Generating package-lock.json files for reproducible builds..."
    ./scripts/generate-package-locks.sh
fi

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

# Build BankUI landing page
print_status "Building BankUI landing page..."
cd ../bankui-landing
docker build -t bankui-landing:latest .
print_success "BankUI landing page image built"

# Build Agreement Profile Service (Java Spring Boot)
print_status "Building Agreement Profile Service..."
cd ../agreement-profile-service
docker build -t agreement-profile-service:latest .
print_success "Agreement Profile Service image built"

# Go back to project root
cd "$PROJECT_ROOT"

# Load images into MicroK8s (if using MicroK8s)
if command -v microk8s &> /dev/null; then
    print_status "Cleaning up old MicroK8s images..."
    
    # Remove old images (optional - will fail silently if images don't exist)
    microk8s ctr images rm docker.io/library/aggregation-service:latest 2>/dev/null || true
    microk8s ctr images rm docker.io/library/customer-profile-service:latest 2>/dev/null || true
    microk8s ctr images rm docker.io/library/analytics-ui:latest 2>/dev/null || true
    microk8s ctr images rm docker.io/library/legacy-ui:latest 2>/dev/null || true
    microk8s ctr images rm docker.io/library/bankui-landing:latest 2>/dev/null || true
    microk8s ctr images rm docker.io/library/agreement-profile-service:latest 2>/dev/null || true
    
    # Also prune any other unused images
    microk8s ctr images prune 2>/dev/null || true
    
    print_status "Loading images into MicroK8s..."
    
    # Create temporary directory for image files
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT
    
    # Save images to temporary files and import them
    print_status "Saving aggregation service image..."
    docker save aggregation-service:latest > "$TEMP_DIR/aggregation-service.tar"
    microk8s ctr images import "$TEMP_DIR/aggregation-service.tar"
    
    print_status "Saving customer profile service image..."
    docker save customer-profile-service:latest > "$TEMP_DIR/customer-profile-service.tar"
    microk8s ctr images import "$TEMP_DIR/customer-profile-service.tar"
    
    print_status "Saving analytics UI image..."
    docker save analytics-ui:latest > "$TEMP_DIR/analytics-ui.tar"
    microk8s ctr images import "$TEMP_DIR/analytics-ui.tar"
    
    print_status "Saving legacy UI image..."
    docker save legacy-ui:latest > "$TEMP_DIR/legacy-ui.tar"
    microk8s ctr images import "$TEMP_DIR/legacy-ui.tar"
    
    print_status "Saving BankUI landing page image..."
    docker save bankui-landing:latest > "$TEMP_DIR/bankui-landing.tar"
    microk8s ctr images import "$TEMP_DIR/bankui-landing.tar"
    
    print_status "Saving Agreement Profile Service image..."
    docker save agreement-profile-service:latest > "$TEMP_DIR/agreement-profile-service.tar"
    microk8s ctr images import "$TEMP_DIR/agreement-profile-service.tar"
    
    print_success "Images loaded into MicroK8s"
else
    print_warning "MicroK8s not detected. Make sure your Kubernetes cluster can access the Docker images."
fi

print_success "All microservices built successfully!"
print_status "You can now deploy using: ./scripts/deploy-microservices.sh"
