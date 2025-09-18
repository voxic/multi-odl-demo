#!/bin/bash

# Build and deploy Analytics UI
# This script creates ConfigMaps and deploys the UI to Kubernetes

set -e

echo "🏗️  Building Analytics UI..."

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Change to project root
cd "$PROJECT_ROOT"

# Create namespace if it doesn't exist
echo "Creating namespace..."
kubectl create namespace odl-demo --dry-run=client -o yaml | kubectl apply -f -

# Create ConfigMap for source code
echo "Creating ConfigMap for source code..."
kubectl create configmap analytics-ui-source \
  --from-file=package.json=microservices/analytics-ui/package.json \
  --from-file=server.js=microservices/analytics-ui/server.js \
  --from-file=public/index.html=microservices/analytics-ui/public/index.html \
  --from-file=public/script.js=microservices/analytics-ui/public/script.js \
  --from-file=public/styles.css=microservices/analytics-ui/public/styles.css \
  -n odl-demo \
  --dry-run=client -o yaml | kubectl apply -f -

# Apply Kubernetes deployment
echo "Deploying to Kubernetes..."
kubectl apply -f k8s/microservices/analytics-ui-deployment.yaml

# Wait for deployment to be ready
echo "Waiting for deployment to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/analytics-ui -n odl-demo

# Get the VM IP
VM_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo ""
echo "✅ Analytics UI deployed successfully!"
echo ""
echo "🌐 Access the application at:"
echo "   http://$VM_IP:3002"
echo ""
echo "📊 The UI provides:"
echo "   - Modern customer analytics dashboard"
echo "   - Real-time data visualization"
echo "   - Customer insights and trends"
echo "   - Integration with aggregation service"
echo ""
echo "🔧 To check deployment status:"
echo "   kubectl get pods -n odl-demo -l app=analytics-ui"
echo "   kubectl logs -f deployment/analytics-ui -n odl-demo"
echo ""
echo "🔄 To update the UI:"
echo "   ./scripts/build-analytics-ui.sh"
