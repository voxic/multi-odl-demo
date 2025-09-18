#!/bin/bash

# Build and deploy Legacy Banking UI
# This script creates ConfigMaps and deploys the UI to Kubernetes

set -e

echo "🏦 Building Legacy Banking UI..."

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
kubectl create configmap legacy-ui-source \
  --from-file=package.json=microservices/legacy-ui/package.json \
  --from-file=server.js=microservices/legacy-ui/server.js \
  --from-file=public/index.html=microservices/legacy-ui/public/index.html \
  --from-file=public/script.js=microservices/legacy-ui/public/script.js \
  --from-file=public/styles.css=microservices/legacy-ui/public/styles.css \
  -n odl-demo \
  --dry-run=client -o yaml | kubectl apply -f -

# Apply Kubernetes deployment
echo "Deploying to Kubernetes..."
kubectl apply -f k8s/microservices/legacy-ui-deployment.yaml

# Wait for deployment to be ready
echo "Waiting for deployment to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/legacy-ui -n odl-demo

# Get the VM IP
VM_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo ""
echo "✅ Legacy Banking UI deployed successfully!"
echo ""
echo "🌐 Access the application at:"
echo "   http://$VM_IP:3001"
echo ""
echo "📊 The UI provides:"
echo "   - Customer management and editing"
echo "   - Account management and editing"
echo "   - Transaction viewing and adding"
echo "   - Legacy-style interface for demo purposes"
echo ""
echo "🔧 To check deployment status:"
echo "   kubectl get pods -n odl-demo -l app=legacy-ui"
echo "   kubectl logs -f deployment/legacy-ui -n odl-demo"
echo ""
echo "🔄 To update the UI:"
echo "   ./scripts/build-legacy-ui.sh"
