#!/bin/bash

# ODL Demo Deployment Script - Host Networking Version
# This script deploys the entire ODL demo infrastructure using host networking

set -e

echo "[$(get_timestamp)] 🚀 Starting ODL Demo Deployment (Host Networking)..."

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

# Check MongoDB configuration
CONFIG_DIR="config"
LOCAL_CONFIG_FILE="$CONFIG_DIR/mongodb-config.local.env"

if [ ! -f "$LOCAL_CONFIG_FILE" ]; then
    print_warning "MongoDB configuration not found: $LOCAL_CONFIG_FILE"
    print_status "Please run './scripts/configure-mongodb.sh' first to set up your MongoDB Atlas configuration."
    print_status "Alternatively, you can manually create the configuration file with your MongoDB Atlas credentials."
    exit 1
fi

print_status "MongoDB configuration found: $LOCAL_CONFIG_FILE"

# Generate MongoDB secrets from configuration
print_status "Generating MongoDB secrets from configuration..."
if ! ./scripts/generate-mongodb-secrets.sh; then
    print_error "Failed to generate MongoDB secrets"
    exit 1
fi

# Check if required files exist
REQUIRED_FILES=(
    "k8s/mysql/mysql-hostnetwork.yaml"
    "k8s/mysql/mysql-init-scripts.yaml"
    "k8s/kafka/kafka-hostnetwork.yaml"
    "k8s/kafka/kafka-connect-hostnetwork.yaml"
    "k8s/microservices/aggregation-service-deployment-docker.yaml"
    "k8s/microservices/customer-profile-service-deployment-docker.yaml"
    "k8s/microservices/agreement-profile-service-deployment-docker.yaml"
    "k8s/microservices/legacy-ui-deployment-docker.yaml"
    "k8s/microservices/analytics-ui-deployment-docker.yaml"
    "k8s/microservices/bankui-landing-deployment-docker.yaml"
    "k8s/connectors/debezium-mysql-connector-hostnetwork.json"
    "k8s/connectors/mongodb-atlas-connector.json"
    "k8s/connectors/mongodb-source-cluster1-agreements.json"
    "k8s/connectors/mongodb-sink-cluster2-profiles.json"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        print_error "Required file not found: $file"
        exit 1
    fi
done

print_status "All required files found"

# Build microservices Docker images
print_status "Building microservices Docker images..."
if ! ./scripts/build-microservices.sh; then
    print_error "Failed to build microservices Docker images"
    exit 1
fi

# Create namespace
print_status "Creating namespace 'odl-demo'..."
kubectl create namespace odl-demo --dry-run=client -o yaml | kubectl apply -f -

# Deploy MySQL with host networking
print_status "Deploying MySQL with host networking..."
kubectl apply -f k8s/mysql/mysql-hostnetwork.yaml -n odl-demo
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

# Deploy Kafka with host networking
print_status "Deploying Kafka cluster with host networking..."
kubectl apply -f k8s/kafka/kafka-hostnetwork.yaml -n odl-demo

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

# Deploy Kafka Connect with host networking
print_status "Deploying Kafka Connect with host networking..."
kubectl apply -f k8s/kafka/kafka-connect-hostnetwork.yaml -n odl-demo

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

# Deploy microservices using Docker images
print_status "Deploying microservices using Docker images..."

# Deploy aggregation service
print_status "Deploying aggregation service..."
kubectl apply -f k8s/microservices/aggregation-service-deployment-docker.yaml -n odl-demo

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

# Deploy Customer Profile service
print_status "Deploying Customer Profile service..."
kubectl apply -f k8s/microservices/customer-profile-service-deployment-docker.yaml -n odl-demo

# Wait for Customer Profile service to be ready
print_status "Waiting for Customer Profile service to be ready..."
if ! kubectl wait --for=condition=available --timeout=300s deployment/customer-profile-service -n odl-demo; then
    print_error "Customer Profile service deployment failed to become available"
    print_status "Customer Profile service pod status:"
    kubectl get pods -n odl-demo -l app=customer-profile-service
    print_status "Customer Profile service pod logs:"
    kubectl logs -n odl-demo -l app=customer-profile-service --tail=50
    exit 1
fi

# Deploy Agreement Profile service
print_status "Deploying Agreement Profile service..."
kubectl apply -f k8s/microservices/agreement-profile-service-deployment-docker.yaml -n odl-demo

# Wait for Agreement Profile service to be ready
print_status "Waiting for Agreement Profile service to be ready..."
if ! kubectl wait --for=condition=available --timeout=300s deployment/agreement-profile-service -n odl-demo; then
    print_error "Agreement Profile service deployment failed to become available"
    print_status "Agreement Profile service pod status:"
    kubectl get pods -n odl-demo -l app=agreement-profile-service
    print_status "Agreement Profile service pod logs:"
    kubectl logs -n odl-demo -l app=agreement-profile-service --tail=50
    exit 1
fi

# Deploy Legacy Banking UI
print_status "Deploying Legacy Banking UI..."
kubectl apply -f k8s/microservices/legacy-ui-deployment-docker.yaml -n odl-demo

# Wait for legacy UI to be ready
print_status "Waiting for legacy UI to be ready..."
if ! kubectl wait --for=condition=available --timeout=300s deployment/legacy-ui -n odl-demo; then
    print_error "Legacy UI deployment failed to become available"
    print_status "Legacy UI pod status:"
    kubectl get pods -n odl-demo -l app=legacy-ui
    print_status "Legacy UI pod logs:"
    kubectl logs -n odl-demo -l app=legacy-ui --tail=50
    exit 1
fi

# Deploy Analytics UI
print_status "Deploying Analytics UI..."
kubectl apply -f k8s/microservices/analytics-ui-deployment-docker.yaml -n odl-demo

# Wait for analytics UI to be ready
print_status "Waiting for analytics UI to be ready..."
if ! kubectl wait --for=condition=available --timeout=300s deployment/analytics-ui -n odl-demo; then
    print_error "Analytics UI deployment failed to become available"
    print_status "Analytics UI pod status:"
    kubectl get pods -n odl-demo -l app=analytics-ui
    print_status "Analytics UI pod logs:"
    kubectl logs -n odl-demo -l app=analytics-ui --tail=50
    exit 1
fi

# Deploy BankUI Landing
print_status "Deploying BankUI Landing..."
kubectl apply -f k8s/microservices/bankui-landing-deployment-docker.yaml -n odl-demo

# Wait for BankUI Landing to be ready
print_status "Waiting for BankUI Landing to be ready..."
if ! kubectl wait --for=condition=available --timeout=300s deployment/bankui-landing -n odl-demo; then
    print_error "BankUI Landing deployment failed to become available"
    print_status "BankUI Landing pod status:"
    kubectl get pods -n odl-demo -l app=bankui-landing
    print_status "BankUI Landing pod logs:"
    kubectl logs -n odl-demo -l app=bankui-landing --tail=50
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

# Deploy Debezium MySQL connector (host networking version)
print_status "Deploying Debezium MySQL connector (host networking)..."
kubectl cp k8s/connectors/debezium-mysql-connector-hostnetwork.json odl-demo/$KAFKA_CONNECT_POD:/tmp/debezium-mysql-connector.json
kubectl exec -n odl-demo $KAFKA_CONNECT_POD -- curl -X POST -H "Content-Type: application/json" \
  --data @/tmp/debezium-mysql-connector.json \
  http://localhost:8083/connectors || print_warning "Failed to deploy Debezium connector (may already exist)"

# Deploy MongoDB Atlas connector
print_status "Deploying MongoDB Atlas connector..."

# Load MongoDB configuration to get the actual connection string
while IFS='=' read -r key value; do
    if [[ $key =~ ^[[:space:]]*# ]] || [[ -z $key ]]; then
        continue
    fi
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)
    export "$key"="$value"
done < "$LOCAL_CONFIG_FILE"

# Create a temporary connector configuration with the actual connection string
TEMP_CONNECTOR_FILE="/tmp/mongodb-atlas-connector-temp.json"
cat > "$TEMP_CONNECTOR_FILE" << EOF
{
  "name": "mongodb-atlas-connector",
  "config": {
    "connector.class": "com.mongodb.kafka.connect.MongoSinkConnector",
    "tasks.max": "1",
    "topics": "mysql.inventory.customers,mysql.inventory.accounts,mysql.inventory.transactions,mysql.inventory.agreements",
    "connection.uri": "$MONGO_CLUSTER1_URI",
    "database": "banking",
    "collection": "customers",
    "topic.override.mysql.inventory.customers.collection": "customers",
    "topic.override.mysql.inventory.accounts.collection": "accounts", 
    "topic.override.mysql.inventory.transactions.collection": "transactions",
    "topic.override.mysql.inventory.agreements.collection": "agreements",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "false",
    "value.converter.schemas.enable": "false"
  }
}
EOF

kubectl cp "$TEMP_CONNECTOR_FILE" odl-demo/$KAFKA_CONNECT_POD:/tmp/mongodb-atlas-connector.json
kubectl exec -n odl-demo $KAFKA_CONNECT_POD -- curl -X POST -H "Content-Type: application/json" \
  --data @/tmp/mongodb-atlas-connector.json \
  http://localhost:8083/connectors || print_warning "Failed to deploy MongoDB Atlas connector (may already exist)"

# Clean up temporary file
rm -f "$TEMP_CONNECTOR_FILE"

# Deploy MongoDB Source Connector for agreements (Cluster 1 → Kafka)
print_status "Deploying MongoDB Source Connector for agreements..."

# Create a temporary connector configuration with the actual connection string
TEMP_SOURCE_CONNECTOR_FILE="/tmp/mongodb-source-agreements-temp.json"
cat > "$TEMP_SOURCE_CONNECTOR_FILE" << EOF
{
  "name": "mongodb-source-cluster1-agreements",
  "config": {
    "connector.class": "com.mongodb.kafka.connect.MongoSourceConnector",
    "tasks.max": "1",
    "connection.uri": "$MONGO_CLUSTER1_URI",
    "database": "banking",
    "collection": "agreements",
    "topic.prefix": "",
    "topic.suffix": "",
    "topic.namespace.map": "{\"banking.agreements\":\"customer-agreement-events\"}",
    "publish.full.document.only": "true",
    "change.stream.full.document": "updateLookup",
    "output.format.value": "json",
    "output.format.key": "json",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "false",
    "value.converter.schemas.enable": "false",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
  }
}
EOF

kubectl cp "$TEMP_SOURCE_CONNECTOR_FILE" odl-demo/$KAFKA_CONNECT_POD:/tmp/mongodb-source-agreements.json
kubectl exec -n odl-demo $KAFKA_CONNECT_POD -- curl -X POST -H "Content-Type: application/json" \
  --data @/tmp/mongodb-source-agreements.json \
  http://localhost:8083/connectors || print_warning "Failed to deploy MongoDB Source connector (may already exist)"

# Clean up temporary file
rm -f "$TEMP_SOURCE_CONNECTOR_FILE"

# Deploy MongoDB Sink Connector for profiles (Kafka → Cluster 2)
print_status "Deploying MongoDB Sink Connector for agreement profiles..."

# Create a temporary connector configuration with the actual connection string
TEMP_SINK_CONNECTOR_FILE="/tmp/mongodb-sink-profiles-temp.json"
cat > "$TEMP_SINK_CONNECTOR_FILE" << EOF
{
  "name": "mongodb-sink-cluster2-profiles",
  "config": {
    "connector.class": "com.mongodb.kafka.connect.MongoSinkConnector",
    "tasks.max": "1",
    "topics": "customer-agreement-profiles",
    "connection.uri": "$MONGO_CLUSTER2_URI",
    "database": "analytics",
    "collection": "customer_agreement_profiles",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "false",
    "value.converter.schemas.enable": "false",
    "document.id.strategy": "com.mongodb.kafka.connect.sink.processor.id.strategy.PartialValueStrategy",
    "document.id.strategy.partial.value.projection.type": "AllowList",
    "document.id.strategy.partial.value.projection.list": "customerId",
    "writemodel.strategy": "com.mongodb.kafka.connect.sink.writemodel.strategy.ReplaceOneBusinessKeyStrategy",
    "writemodel.strategy.replace.one.business.key.fields": "customerId"
  }
}
EOF

kubectl cp "$TEMP_SINK_CONNECTOR_FILE" odl-demo/$KAFKA_CONNECT_POD:/tmp/mongodb-sink-profiles.json
kubectl exec -n odl-demo $KAFKA_CONNECT_POD -- curl -X POST -H "Content-Type: application/json" \
  --data @/tmp/mongodb-sink-profiles.json \
  http://localhost:8083/connectors || print_warning "Failed to deploy MongoDB Sink connector (may already exist)"

# Clean up temporary file
rm -f "$TEMP_SINK_CONNECTOR_FILE"


print_status "🎉 Deployment completed successfully!"

# Get VM IP
VM_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null)
if [ -z "$VM_IP" ]; then
    VM_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
fi

# Display service information
echo ""
print_status "🎯 Host Networking Deployment Complete!"
echo ""
print_status "Services are now accessible on standard ports:"
if [ -n "$VM_IP" ]; then
    echo "[$(get_timestamp)] MySQL: mysql://odl_user:odl_password@$VM_IP:3306/banking"
    echo "[$(get_timestamp)] Kafka UI: http://$VM_IP:8080"
    echo "[$(get_timestamp)] Kafka: $VM_IP:9092"
    echo "[$(get_timestamp)] Kafka Connect: http://$VM_IP:8083"
    echo "[$(get_timestamp)] Legacy UI: http://$VM_IP:3003"
    echo "[$(get_timestamp)] Analytics UI: http://$VM_IP:3002"
    echo "[$(get_timestamp)] BankUI Landing: http://$VM_IP:3004"
else
    echo "[$(get_timestamp)] MySQL: mysql://odl_user:odl_password@localhost:3306/banking"
    echo "[$(get_timestamp)] Kafka UI: http://localhost:8080"
    echo "[$(get_timestamp)] Kafka: localhost:9092"
    echo "[$(get_timestamp)] Kafka Connect: http://localhost:8083"
    echo "[$(get_timestamp)] Legacy UI: http://localhost:3003"
    echo "[$(get_timestamp)] Analytics UI: http://localhost:3002"
    echo "[$(get_timestamp)] BankUI Landing: http://localhost:3004"
fi

echo ""
print_status "Port Forwarding (for other services):"
echo "[$(get_timestamp)] Aggregation Service: kubectl port-forward service/aggregation-service 3000:3000 -n odl-demo"
echo "[$(get_timestamp)] Customer Profile Service: kubectl port-forward service/customer-profile-service 3001:3001 -n odl-demo"
echo "[$(get_timestamp)] Agreement Profile Service: kubectl port-forward service/agreement-profile-service 3005:3005 -n odl-demo"

echo ""
print_status "To check the status of all pods:"
echo "[$(get_timestamp)] kubectl get pods -n odl-demo"

echo ""
print_status "To view logs:"
echo "[$(get_timestamp)] kubectl logs -f deployment/aggregation-service -n odl-demo"
echo "[$(get_timestamp)] kubectl logs -f deployment/customer-profile-service -n odl-demo"
echo "[$(get_timestamp)] kubectl logs -f deployment/agreement-profile-service -n odl-demo"
