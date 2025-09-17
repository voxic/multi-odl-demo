#!/bin/bash

# ODL Demo Fix Script
# This script cleans up failed pods and redeploys with fixed configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

print_status() {
    echo -e "${GREEN}[$(get_timestamp)] [INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[$(get_timestamp)] [WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[$(get_timestamp)] [ERROR]${NC} $1"
}

NAMESPACE="odl-demo"

echo "[$(get_timestamp)] 🔧 ODL Demo Fix Script"
echo "[$(get_timestamp)] ======================"

# Check if namespace exists
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    print_error "Namespace '$NAMESPACE' not found"
    exit 1
fi

print_status "Current pod status before cleanup:"
kubectl get pods -n $NAMESPACE

echo ""

# Clean up failed deployments
print_status "Cleaning up failed deployments..."

# Delete failed pods and deployments
kubectl delete deployment kafka -n $NAMESPACE --force --grace-period=0 || true
kubectl delete deployment zookeeper -n $NAMESPACE --force --grace-period=0 || true
kubectl delete deployment kafka-connect -n $NAMESPACE --force --grace-period=0 || true

# Wait for cleanup
sleep 10

print_status "Redeploying with fixed configuration..."

# Redeploy Kafka with fixed configuration
print_status "Redeploying Kafka cluster..."
kubectl apply -f k8s/kafka/kafka-all-in-one.yaml -n $NAMESPACE

# Wait for Zookeeper to be ready
print_status "Waiting for Zookeeper to be ready..."
if ! kubectl wait --for=condition=available --timeout=300s deployment/zookeeper -n $NAMESPACE; then
    print_error "Zookeeper deployment failed"
    kubectl logs -n $NAMESPACE -l app=zookeeper --tail=20
    exit 1
fi

# Wait for Kafka to be ready
print_status "Waiting for Kafka to be ready..."
if ! kubectl wait --for=condition=available --timeout=300s deployment/kafka -n $NAMESPACE; then
    print_error "Kafka deployment failed"
    kubectl logs -n $NAMESPACE -l app=kafka --tail=20
    exit 1
fi

# Redeploy Kafka Connect
print_status "Redeploying Kafka Connect..."
kubectl apply -f k8s/kafka/kafka-connect.yaml -n $NAMESPACE

# Wait for Kafka Connect to be ready
print_status "Waiting for Kafka Connect to be ready..."
if ! kubectl wait --for=condition=available --timeout=300s deployment/kafka-connect -n $NAMESPACE; then
    print_error "Kafka Connect deployment failed"
    kubectl logs -n $NAMESPACE -l app=kafka-connect --tail=20
    exit 1
fi

# Deploy aggregation service
print_status "Deploying aggregation service..."
kubectl apply -f k8s/microservices/aggregation-service-deployment.yaml -n $NAMESPACE

# Wait for aggregation service to be ready
print_status "Waiting for aggregation service to be ready..."
if ! kubectl wait --for=condition=available --timeout=300s deployment/aggregation-service -n $NAMESPACE; then
    print_error "Aggregation service deployment failed"
    kubectl logs -n $NAMESPACE -l app=aggregation-service --tail=20
    exit 1
fi

print_status "🎉 Fix completed successfully!"

# Show final status
echo ""
print_status "Final pod status:"
kubectl get pods -n $NAMESPACE

echo ""
print_status "All services should now be running properly!"
