#!/bin/bash

# Port Forwarding Script for ODL Demo
# This script sets up port forwarding to standard ports

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

# Check if namespace exists
if ! kubectl get namespace odl-demo &> /dev/null; then
    print_error "Namespace 'odl-demo' not found. Please run ./scripts/deploy.sh first."
    exit 1
fi

print_status "Setting up port forwarding to standard ports..."

# Function to setup port forwarding
setup_port_forward() {
    local service_name=$1
    local local_port=$2
    local target_port=$3
    local description=$4
    
    print_status "Setting up port forwarding for $description..."
    print_status "Local port: $local_port -> Service: $service_name:$target_port"
    
    # Kill any existing port forwarding on this port
    lsof -ti:$local_port | xargs kill -9 2>/dev/null || true
    
    # Start port forwarding in background
    kubectl port-forward service/$service_name $local_port:$target_port -n odl-demo &
    local pid=$!
    
    # Wait a moment to check if it started successfully
    sleep 2
    if kill -0 $pid 2>/dev/null; then
        print_status "✅ $description is now available on localhost:$local_port"
        echo $pid > /tmp/odl-port-forward-$local_port.pid
    else
        print_error "Failed to start port forwarding for $description"
        return 1
    fi
}

# Setup port forwarding for all services
setup_port_forward "mysql-service" 3306 3306 "MySQL Database"
setup_port_forward "kafka-ui-service" 8080 8080 "Kafka UI"
setup_port_forward "kafka-service" 9092 9092 "Kafka Broker"
setup_port_forward "kafka-connect-service" 8083 8083 "Kafka Connect"
setup_port_forward "aggregation-service" 3000 3000 "Aggregation Service"

echo ""
print_status "🎉 All services are now accessible on standard ports:"
echo "[$(get_timestamp)] MySQL: mysql://odl_user:odl_password@localhost:3306/banking"
echo "[$(get_timestamp)] Kafka UI: http://localhost:8080"
echo "[$(get_timestamp)] Kafka: localhost:9092"
echo "[$(get_timestamp)] Kafka Connect: http://localhost:8083"
echo "[$(get_timestamp)] Aggregation Service: http://localhost:3000"

echo ""
print_status "Port forwarding is running in the background."
print_status "To stop port forwarding, run: ./scripts/stop-port-forward.sh"
print_status "Or kill the processes manually: kill \$(cat /tmp/odl-port-forward-*.pid)"

echo ""
print_warning "Keep this terminal open or run the script in the background:"
print_warning "nohup ./scripts/port-forward.sh > port-forward.log 2>&1 &"
