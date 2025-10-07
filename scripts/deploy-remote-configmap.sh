#!/bin/bash

# Remote deployment script - No Docker required on remote machine
# This script uses ConfigMaps for remote deployment without Docker

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

print_status "Remote deployment without Docker (ConfigMap approach)"

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

# Check SSH access to remote host
if ! ssh -o ConnectTimeout=5 "$REMOTE_USER@$REMOTE_HOST" "echo 'SSH connection successful'" > /dev/null 2>&1; then
    print_error "Cannot connect to remote host $REMOTE_HOST as $REMOTE_USER"
    print_status "Please ensure:"
    print_status "1. SSH key is set up for passwordless access"
    print_status "2. Remote host is accessible"
    print_status "3. User has sudo privileges on remote host"
    exit 1
fi

print_success "SSH connection successful"

# Transfer project files to remote host
print_status "Transferring project files to remote host..."
rsync -av --exclude='.git' --exclude='node_modules' \
    "$PROJECT_ROOT/" "$REMOTE_USER@$REMOTE_HOST:~/odl-demo/"

# Execute deployment on remote host using ConfigMap approach
print_status "Executing ConfigMap-based deployment on remote host..."
ssh "$REMOTE_USER@$REMOTE_HOST" << 'EOF'
cd ~/odl-demo

# Check if MicroK8s is running
if ! kubectl cluster-info &> /dev/null; then
    echo "MicroK8s is not running. Starting MicroK8s..."
    sudo microk8s start
    microk8s enable dns storage ingress
fi

# Use the old ConfigMap-based deployment
echo "Deploying using ConfigMap approach (no Docker required)..."

# Create namespace
kubectl create namespace odl-demo --dry-run=client -o yaml | kubectl apply -f -

# Deploy infrastructure
kubectl apply -f k8s/mysql/mysql-hostnetwork.yaml -n odl-demo
kubectl apply -f k8s/mysql/mysql-init-scripts.yaml -n odl-demo

# Wait for MySQL
kubectl wait --for=condition=available --timeout=300s deployment/mysql -n odl-demo

# Deploy Kafka
kubectl apply -f k8s/kafka/kafka-hostnetwork.yaml -n odl-demo
kubectl wait --for=condition=available --timeout=300s deployment/kafka -n odl-demo

# Deploy Kafka Connect
kubectl apply -f k8s/kafka/kafka-connect-hostnetwork.yaml -n odl-demo
kubectl wait --for=condition=available --timeout=300s deployment/kafka-connect -n odl-demo

# Deploy microservices using ConfigMaps
kubectl apply -f k8s/microservices/aggregation-source-configmap.yaml -n odl-demo
kubectl apply -f k8s/microservices/customer-profile-source-configmap.yaml -n odl-demo
kubectl apply -f k8s/microservices/aggregation-service-deployment.yaml -n odl-demo
kubectl apply -f k8s/microservices/customer-profile-service-deployment.yaml -n odl-demo

# Wait for services
kubectl wait --for=condition=available --timeout=300s deployment/aggregation-service -n odl-demo
kubectl wait --for=condition=available --timeout=300s deployment/customer-profile-service -n odl-demo

# Deploy UIs using ConfigMaps
if [ -f "microservices/legacy-ui/package.json" ]; then
    kubectl create configmap legacy-ui-source \
      --from-file=package.json=microservices/legacy-ui/package.json \
      --from-file=server.js=microservices/legacy-ui/server.js \
      --from-file=index.html=microservices/legacy-ui/public/index.html \
      --from-file=script.js=microservices/legacy-ui/public/script.js \
      --from-file=styles.css=microservices/legacy-ui/public/styles.css \
      -n odl-demo \
      --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl apply -f k8s/microservices/legacy-ui-deployment.yaml -n odl-demo
fi

if [ -f "microservices/analytics-ui/package.json" ]; then
    kubectl create configmap analytics-ui-source \
      --from-file=package.json=microservices/analytics-ui/package.json \
      --from-file=server.js=microservices/analytics-ui/server.js \
      --from-file=index.html=microservices/analytics-ui/public/index.html \
      --from-file=script.js=microservices/analytics-ui/public/script.js \
      --from-file=styles.css=microservices/analytics-ui/public/styles.css \
      -n odl-demo \
      --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl apply -f k8s/microservices/analytics-ui-deployment.yaml -n odl-demo
fi

echo "ConfigMap-based deployment completed!"
EOF

print_success "Remote deployment completed!"
print_status "Services are now running on $REMOTE_HOST"
print_status "Access services at:"
print_status "  - Legacy UI: http://$REMOTE_HOST:3001"
print_status "  - Analytics UI: http://$REMOTE_HOST:3002"
print_status "  - Kafka UI: http://$REMOTE_HOST:8080"
print_status "  - MySQL: mysql://odl_user:odl_password@$REMOTE_HOST:3306/banking"
