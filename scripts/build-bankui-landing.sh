#!/bin/bash

# Build script for BankUI Landing Page
# This script follows the same pattern as other microservices

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

print_status "Building BankUI Landing Page..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

# Build BankUI landing page
print_status "Building BankUI landing page..."
cd microservices/bankui-landing
docker build -t bankui-landing:latest .
print_success "BankUI landing page image built"

# Go back to project root
cd "$PROJECT_ROOT"

# Load image into MicroK8s (if using MicroK8s)
if command -v microk8s &> /dev/null; then
    print_status "Loading BankUI landing page image into MicroK8s..."
    
    # Create temporary directory for image files
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT
    
    # Save image to temporary file and import it
    print_status "Saving BankUI landing page image..."
    docker save bankui-landing:latest > "$TEMP_DIR/bankui-landing.tar"
    microk8s ctr images import "$TEMP_DIR/bankui-landing.tar"
    
    print_success "BankUI landing page image loaded into MicroK8s"
else
    print_warning "MicroK8s not detected. Make sure your Kubernetes cluster can access the Docker image."
fi

print_success "BankUI Landing Page built successfully!"
print_status "You can now deploy using: ./scripts/deploy-microservices.sh"
