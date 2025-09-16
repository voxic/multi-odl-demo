#!/bin/bash

# ODL Demo Presentation Script
# This script helps demonstrate the ODL functionality

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Function to print colored output
print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace odl-demo &> /dev/null; then
    print_error "odl-demo namespace not found. Please run ./scripts/deploy.sh first"
    exit 1
fi

print_header "ODL Demo Presentation"

echo ""
print_step "1. Checking system health..."
kubectl get pods -n odl-demo

echo ""
print_step "2. Checking aggregation service health..."
kubectl port-forward service/aggregation-service 3000:3000 -n odl-demo &
AGG_PID=$!
sleep 5

if curl -s http://localhost:3000/health > /dev/null; then
    print_success "Aggregation service is healthy"
    curl -s http://localhost:3000/health | jq .
else
    print_error "Aggregation service is not responding"
fi

echo ""
print_step "3. Checking system statistics..."
if curl -s http://localhost:3000/stats > /dev/null; then
    print_success "System statistics:"
    curl -s http://localhost:3000/stats | jq .
else
    print_error "Could not retrieve statistics"
fi

echo ""
print_step "4. Demonstrating real-time data flow..."

print_info "Let's add a new customer to MySQL..."
kubectl exec -it deployment/mysql -n odl-demo -- mysql -u odl_user -podl_password banking -e "
INSERT INTO customers (first_name, last_name, email, customer_status, created_at, updated_at) 
VALUES ('Demo', 'Customer', 'demo.customer@example.com', 'ACTIVE', NOW(), NOW());
"

print_info "Customer added! Now let's check the aggregation service logs..."
echo "Press Ctrl+C to stop watching logs and continue the demo"
kubectl logs -f deployment/aggregation-service -n odl-demo --tail=10

echo ""
print_step "5. Checking Kafka Connect status..."
kubectl port-forward service/kafka-connect-service 8083:8083 -n odl-demo &
CONNECT_PID=$!
sleep 5

if curl -s http://localhost:8083/connectors > /dev/null; then
    print_success "Kafka Connect connectors:"
    curl -s http://localhost:8083/connectors | jq .
else
    print_error "Kafka Connect is not responding"
fi

echo ""
print_step "6. Demonstrating data aggregation..."

print_info "Triggering manual aggregation for all customers..."
curl -X POST http://localhost:3000/aggregate -H "Content-Type: application/json" -d '{}'

print_info "Waiting for aggregation to complete..."
sleep 10

print_info "Final statistics:"
curl -s http://localhost:3000/stats | jq .

echo ""
print_header "Demo Complete!"

print_info "To continue exploring:"
echo "1. Check MongoDB Atlas Cluster 1 for raw data"
echo "2. Check MongoDB Atlas Cluster 2 for aggregated analytics"
echo "3. Make more changes in MySQL to see real-time updates"
echo "4. Use kubectl logs to monitor the system"

print_info "To clean up:"
echo "./scripts/cleanup.sh"

# Clean up background processes
kill $AGG_PID 2>/dev/null || true
kill $CONNECT_PID 2>/dev/null || true

print_success "Demo completed successfully!"
