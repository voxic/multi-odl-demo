#!/bin/bash

# ODL Demo Deployment Script
# This script deploys the entire ODL demo infrastructure

set -e

echo "🚀 Starting ODL Demo Deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if MicroK8s is running
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster. Make sure MicroK8s is running."
    exit 1
fi

print_status "Kubernetes cluster is accessible"

# Create namespace
print_status "Creating namespace 'odl-demo'..."
kubectl create namespace odl-demo --dry-run=client -o yaml | kubectl apply -f -

# Deploy MySQL
print_status "Deploying MySQL..."
kubectl apply -f k8s/mysql/mysql-deployment.yaml -n odl-demo
kubectl apply -f k8s/mysql/mysql-init-scripts.yaml -n odl-demo

# Wait for MySQL to be ready
print_status "Waiting for MySQL to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/mysql -n odl-demo

# Deploy Kafka
print_status "Deploying Kafka cluster..."
kubectl apply -f k8s/kafka/kafka-all-in-one.yaml -n odl-demo

# Wait for Kafka to be ready
print_status "Waiting for Kafka to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/kafka -n odl-demo

# Deploy Kafka Connect
print_status "Deploying Kafka Connect..."
kubectl apply -f k8s/kafka/kafka-connect.yaml -n odl-demo

# Wait for Kafka Connect to be ready
print_status "Waiting for Kafka Connect to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/kafka-connect -n odl-demo

# Generate sample data
print_status "Generating sample data..."
kubectl run mysql-client --image=mysql:8.0 --rm -i --restart=Never -n odl-demo -- \
  mysql -h mysql-service -u odl_user -podl_password banking < k8s/mysql/mysql-init-scripts.yaml

# Deploy aggregation service
print_status "Deploying aggregation service..."
kubectl apply -f k8s/microservices/aggregation-service-deployment.yaml -n odl-demo

# Wait for aggregation service to be ready
print_status "Waiting for aggregation service to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/aggregation-service -n odl-demo

# Setup Kafka connectors
print_status "Setting up Kafka connectors..."

# Wait for Kafka Connect to be fully ready
sleep 30

# Deploy Debezium MySQL connector
print_status "Deploying Debezium MySQL connector..."
curl -X POST -H "Content-Type: application/json" \
  --data @k8s/connectors/debezium-mysql-connector.json \
  http://$(kubectl get service kafka-connect-service -n odl-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8083/connectors

# Deploy MongoDB Atlas connector
print_status "Deploying MongoDB Atlas connector..."
curl -X POST -H "Content-Type: application/json" \
  --data @k8s/connectors/mongodb-atlas-connector.json \
  http://$(kubectl get service kafka-connect-service -n odl-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8083/connectors

print_status "🎉 Deployment completed successfully!"

# Display service information
echo ""
print_status "Service Information:"
echo "MySQL: kubectl port-forward service/mysql-service 3306:3306 -n odl-demo"
echo "Kafka: kubectl port-forward service/kafka-service 9092:9092 -n odl-demo"
echo "Kafka Connect: kubectl port-forward service/kafka-connect-service 8083:8083 -n odl-demo"
echo "Aggregation Service: kubectl port-forward service/aggregation-service 3000:3000 -n odl-demo"

echo ""
print_status "To check the status of all pods:"
echo "kubectl get pods -n odl-demo"

echo ""
print_status "To view logs:"
echo "kubectl logs -f deployment/aggregation-service -n odl-demo"
