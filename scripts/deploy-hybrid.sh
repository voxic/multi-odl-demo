#!/bin/bash

# Hybrid deployment script - Build locally, deploy remotely
# This script builds Docker images locally and transfers them to remote machine

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

print_status "Hybrid deployment: Build locally, deploy remotely"

# Check if remote host is provided
if [ -z "$1" ]; then
    print_error "Usage: $0 <remote-host> [remote-user]"
    print_status "Example: $0 192.168.1.100 ubuntu"
    exit 1
fi

REMOTE_HOST="$1"
REMOTE_USER="${2:-ubuntu}"

print_status "Remote host: $REMOTE_HOST"
print_status "Remote user: $REMOTE_USER"

# Check prerequisites
print_status "Checking prerequisites..."

# Check if Docker is running locally
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running locally. Please start Docker and try again."
    exit 1
fi

# Check if SSH access to remote host
if ! ssh -o ConnectTimeout=5 "$REMOTE_USER@$REMOTE_HOST" "echo 'SSH connection successful'" > /dev/null 2>&1; then
    print_error "Cannot connect to remote host $REMOTE_HOST as $REMOTE_USER"
    print_status "Please ensure:"
    print_status "1. SSH key is set up for passwordless access"
    print_status "2. Remote host is accessible"
    print_status "3. User has sudo privileges on remote host"
    exit 1
fi

print_success "Prerequisites check passed"

# Build Docker images locally
print_status "Building Docker images locally..."
./scripts/build-microservices.sh

# Save Docker images to tar files
print_status "Saving Docker images..."
docker save aggregation-service:latest -o /tmp/aggregation-service.tar
docker save customer-profile-service:latest -o /tmp/customer-profile-service.tar
docker save analytics-ui:latest -o /tmp/analytics-ui.tar
docker save legacy-ui:latest -o /tmp/legacy-ui.tar

print_success "Docker images saved"

# Transfer images to remote host
print_status "Transferring Docker images to remote host..."
scp /tmp/*.tar "$REMOTE_USER@$REMOTE_HOST:/tmp/"

# Transfer project files to remote host
print_status "Transferring project files to remote host..."
rsync -av --exclude='.git' --exclude='node_modules' --exclude='*.tar' \
    "$PROJECT_ROOT/" "$REMOTE_USER@$REMOTE_HOST:~/odl-demo/"

# Execute deployment on remote host
print_status "Executing deployment on remote host..."
ssh "$REMOTE_USER@$REMOTE_HOST" << 'EOF'
cd ~/odl-demo

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    echo "Installing Docker on remote host..."
    sudo apt update
    sudo apt install -y docker.io
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER
    newgrp docker
fi

# Load Docker images
echo "Loading Docker images..."
docker load -i /tmp/aggregation-service.tar
docker load -i /tmp/customer-profile-service.tar
docker load -i /tmp/analytics-ui.tar
docker load -i /tmp/legacy-ui.tar

# Load images into MicroK8s (if using MicroK8s)
if command -v microk8s &> /dev/null; then
    echo "Loading images into MicroK8s..."
    microk8s ctr images import <(docker save aggregation-service:latest)
    microk8s ctr images import <(docker save customer-profile-service:latest)
    microk8s ctr images import <(docker save analytics-ui:latest)
    microk8s ctr images import <(docker save legacy-ui:latest)
fi

# Deploy the application
echo "Deploying ODL demo..."
./scripts/deploy-hostnetwork.sh

# Clean up
rm -f /tmp/*.tar
EOF

# Clean up local tar files
rm -f /tmp/*.tar

print_success "Hybrid deployment completed!"
print_status "Remote deployment is now running on $REMOTE_HOST"
print_status "Access services at:"
print_status "  - Legacy UI: http://$REMOTE_HOST:3003"
print_status "  - Analytics UI: http://$REMOTE_HOST:3002"
print_status "  - Kafka UI: http://$REMOTE_HOST:8080"
print_status "  - MySQL: mysql://odl_user:odl_password@$REMOTE_HOST:3306/banking"
