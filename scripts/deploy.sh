#!/bin/bash

# ODL Demo Deployment Script
# This script deploys the entire ODL demo infrastructure

set -e

echo "[$(get_timestamp)] 🚀 Starting ODL Demo Deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to print colored output with timestamps
print_status() {
    echo -e "${GREEN}[$(get_timestamp)] [INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[$(get_timestamp)] [WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[$(get_timestamp)] [ERROR]${NC} $1"
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

# Check if required files exist
REQUIRED_FILES=(
    "k8s/mysql/mysql-deployment.yaml"
    "k8s/mysql/mysql-init-scripts.yaml"
    "k8s/kafka/kafka-all-in-one.yaml"
    "k8s/kafka/kafka-connect.yaml"
    "k8s/microservices/aggregation-service-deployment.yaml"
    "k8s/connectors/debezium-mysql-connector.json"
    "k8s/connectors/mongodb-atlas-connector.json"
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

# Deploy MySQL
print_status "Deploying MySQL..."
kubectl apply -f k8s/mysql/mysql-deployment.yaml -n odl-demo
kubectl apply -f k8s/mysql/mysql-init-scripts.yaml -n odl-demo

# Wait for MySQL to be ready
print_status "Waiting for MySQL to be ready..."
if ! kubectl wait --for=condition=available --timeout=300s deployment/mysql -n odl-demo; then
    print_error "MySQL deployment failed to become available"
    print_status "MySQL pod status:"
    kubectl get pods -n odl-demo -l app=mysql
    print_status "MySQL pod logs:"
    kubectl logs -n odl-demo -l app=mysql --tail=50
    exit 1
fi

# Deploy Kafka
print_status "Deploying Kafka cluster..."
kubectl apply -f k8s/kafka/kafka-all-in-one.yaml -n odl-demo

# Wait for Kafka to be ready
print_status "Waiting for Kafka to be ready..."
if ! kubectl wait --for=condition=available --timeout=300s deployment/kafka -n odl-demo; then
    print_error "Kafka deployment failed to become available"
    print_status "Kafka pod status:"
    kubectl get pods -n odl-demo -l app=kafka
    print_status "Kafka pod logs:"
    kubectl logs -n odl-demo -l app=kafka --tail=50
    exit 1
fi

# Wait additional time for Kafka to be fully ready
print_status "Waiting for Kafka to be fully ready..."
sleep 30

# Deploy Kafka Connect
print_status "Deploying Kafka Connect..."
kubectl apply -f k8s/kafka/kafka-connect.yaml -n odl-demo

# Wait for Kafka Connect to be ready
print_status "Waiting for Kafka Connect to be ready..."
if ! kubectl wait --for=condition=available --timeout=300s deployment/kafka-connect -n odl-demo; then
    print_error "Kafka Connect deployment failed to become available"
    print_status "Kafka Connect pod status:"
    kubectl get pods -n odl-demo -l app=kafka-connect
    print_status "Kafka Connect pod logs:"
    kubectl logs -n odl-demo -l app=kafka-connect --tail=50
    exit 1
fi

# Generate sample data
print_status "Generating sample data..."
if ! kubectl run mysql-client --image=mysql:8.0 --rm -i --restart=Never -n odl-demo -- \
  mysql -h mysql-service -u odl_user -p odl_password banking -e "$(kubectl get configmap mysql-init-scripts -n odl-demo -o jsonpath='{.data.01-create-schema\.sql}')"; then
    print_warning "Failed to generate sample data (this may be expected if data already exists)"
fi

# Create configmap with source code
print_status "Creating source code configmap..."
kubectl create configmap aggregation-source -n odl-demo \
  --from-file=package.json=microservices/aggregation-service/package.json \
  --from-file=index.js=microservices/aggregation-service/index.js \
  --dry-run=client -o yaml | kubectl apply -f -

print_status "Deploying aggregation service..."
kubectl apply -f k8s/microservices/aggregation-service-deployment.yaml -n odl-demo

# Wait for aggregation service to be ready
print_status "Waiting for aggregation service to be ready..."
if ! kubectl wait --for=condition=available --timeout=300s deployment/aggregation-service -n odl-demo; then
    print_error "Aggregation service deployment failed to become available"
    print_status "Aggregation service pod status:"
    kubectl get pods -n odl-demo -l app=aggregation-service
    print_status "Aggregation service pod logs:"
    kubectl logs -n odl-demo -l app=aggregation-service --tail=50
    exit 1
fi

# Setup Kafka connectors
print_status "Setting up Kafka connectors..."

# Wait for Kafka Connect to be fully ready
sleep 30

# Get Kafka Connect service details
KAFKA_CONNECT_POD=$(kubectl get pods -n odl-demo -l app=kafka-connect -o jsonpath='{.items[0].metadata.name}')
if [ -z "$KAFKA_CONNECT_POD" ]; then
    print_error "Kafka Connect pod not found"
    exit 1
fi

print_status "Kafka Connect pod: $KAFKA_CONNECT_POD"

# Deploy Debezium MySQL connector
print_status "Deploying Debezium MySQL connector..."
kubectl cp k8s/connectors/debezium-mysql-connector.json odl-demo/$KAFKA_CONNECT_POD:/tmp/debezium-mysql-connector.json
kubectl exec -n odl-demo $KAFKA_CONNECT_POD -- curl -X POST -H "Content-Type: application/json" \
  --data @/tmp/debezium-mysql-connector.json \
  http://localhost:8083/connectors || print_warning "Failed to deploy Debezium connector (may already exist)"

# Deploy MongoDB Atlas connector
print_status "Deploying MongoDB Atlas connector..."
kubectl cp k8s/connectors/mongodb-atlas-connector.json odl-demo/$KAFKA_CONNECT_POD:/tmp/mongodb-atlas-connector.json
kubectl exec -n odl-demo $KAFKA_CONNECT_POD -- curl -X POST -H "Content-Type: application/json" \
  --data @/tmp/mongodb-atlas-connector.json \
  http://localhost:8083/connectors || print_warning "Failed to deploy MongoDB Atlas connector (may already exist)"

print_status "🎉 Deployment completed successfully!"

# Setup NodePort Services (Default behavior)
if [ "$1" != "--no-loadbalancer" ] && [ "$1" != "--port-forward" ]; then
    echo ""
    print_status "🌐 Setting up NodePort services..."
    
    # Clean up any existing load balancer services
    print_status "Cleaning up any existing load balancer services..."
    kubectl delete service mysql-loadbalancer kafka-ui-loadbalancer --ignore-not-found=true
    kubectl delete service mysql-loadbalancer kafka-ui-loadbalancer -n odl-demo --ignore-not-found=true
    
    # Apply NodePort services
    print_status "Creating NodePort services..."
    kubectl apply -f k8s/loadbalancer/mysql-nodeport.yaml
    kubectl apply -f k8s/loadbalancer/kafka-ui-nodeport.yaml
    
    print_status "✅ NodePort services setup completed!"
fi

# Display service information
echo ""
print_status "Service Information:"
echo "[$(get_timestamp)] MySQL: kubectl port-forward service/mysql-service 3306:3306 -n odl-demo"
echo "[$(get_timestamp)] Kafka: kubectl port-forward service/kafka-service 9092:9092 -n odl-demo"
echo "[$(get_timestamp)] Kafka Connect: kubectl port-forward service/kafka-connect-service 8083:8083 -n odl-demo"
echo "[$(get_timestamp)] Aggregation Service: kubectl port-forward service/aggregation-service 3000:3000 -n odl-demo"

# Show NodePort information if enabled
if [ "$1" != "--no-loadbalancer" ] && [ "$1" != "--port-forward" ]; then
    echo ""
    print_status "NodePort Services:"
    echo "[$(get_timestamp)] MySQL NodePort: kubectl get service mysql-nodeport -n odl-demo"
    echo "[$(get_timestamp)] Kafka UI NodePort: kubectl get service kafka-ui-nodeport -n odl-demo"
    
    # Get node IP
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null)
    if [ -z "$NODE_IP" ]; then
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
    fi
    
    echo ""
    print_status "External Access URLs:"
    if [ -n "$NODE_IP" ]; then
        echo "[$(get_timestamp)] MySQL: mysql://odl_user:odl_password@$NODE_IP:3306/banking"
        echo "[$(get_timestamp)] Kafka UI: http://$NODE_IP:8080"
    else
        echo "[$(get_timestamp)] Node IP not found. Check with: kubectl get nodes -o wide"
        echo "[$(get_timestamp)] MySQL: mysql://odl_user:odl_password@<NODE_IP>:3306/banking"
        echo "[$(get_timestamp)] Kafka UI: http://<NODE_IP>:8080"
    fi
else
    echo ""
    print_status "Port Forwarding Mode:"
    echo "[$(get_timestamp)] NodePort services disabled. Using port forwarding for service access."
    echo "[$(get_timestamp)] To enable NodePort services: ./scripts/deploy.sh"
fi

echo ""
print_status "To check the status of all pods:"
echo "[$(get_timestamp)] kubectl get pods -n odl-demo"

echo ""
print_status "To view logs:"
echo "[$(get_timestamp)] kubectl logs -f deployment/aggregation-service -n odl-demo"
