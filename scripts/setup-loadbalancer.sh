#!/bin/bash

# Setup Load Balancer for ODL Demo
# This script enables MetalLB load balancer and configures services

set -e

echo "🚀 Setting up Load Balancer for ODL Demo..."

# Check if MicroK8s is running
if ! microk8s status --wait-ready >/dev/null 2>&1; then
    echo "❌ MicroK8s is not running. Please start MicroK8s first:"
    echo "   sudo snap start microk8s"
    exit 1
fi

echo "✅ MicroK8s is running"

# Enable MetalLB add-on
echo "🔧 Enabling MetalLB add-on..."
microk8s enable metallb

# Wait for MetalLB to be ready
echo "⏳ Waiting for MetalLB to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/controller -n metallb-system

# Apply MetalLB configuration
echo "📝 Applying MetalLB configuration..."
kubectl apply -f k8s/loadbalancer/metallb-config.yaml

# Wait a moment for the configuration to be applied
sleep 10

# Apply load balancer services
echo "🌐 Creating load balancer services..."
kubectl apply -f k8s/loadbalancer/mysql-loadbalancer.yaml
kubectl apply -f k8s/loadbalancer/kafka-ui-loadbalancer.yaml

# Wait for services to get external IPs
echo "⏳ Waiting for load balancer IPs to be assigned..."
kubectl wait --for=condition=ready --timeout=300s service/mysql-loadbalancer -n odl-demo || true
kubectl wait --for=condition=ready --timeout=300s service/kafka-ui-loadbalancer -n odl-demo || true

# Display service information
echo ""
echo "🎉 Load Balancer setup complete!"
echo ""
echo "📋 Service Information:"
echo "======================="

echo ""
echo "MySQL Service:"
kubectl get service mysql-loadbalancer -n odl-demo

echo ""
echo "Kafka UI Service:"
kubectl get service kafka-ui-loadbalancer -n odl-demo

echo ""
echo "🔗 Access URLs:"
echo "==============="

# Get external IPs
MYSQL_IP=$(kubectl get service mysql-loadbalancer -n odl-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending")
KAFKA_UI_IP=$(kubectl get service kafka-ui-loadbalancer -n odl-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending")

if [ "$MYSQL_IP" != "Pending" ] && [ "$MYSQL_IP" != "" ]; then
    echo "MySQL: mysql://odl_user:odl_password@$MYSQL_IP:3306/banking"
else
    echo "MySQL: External IP pending... (check with: kubectl get service mysql-loadbalancer -n odl-demo)"
fi

if [ "$KAFKA_UI_IP" != "Pending" ] && [ "$KAFKA_UI_IP" != "" ]; then
    echo "Kafka UI: http://$KAFKA_UI_IP:8080"
else
    echo "Kafka UI: External IP pending... (check with: kubectl get service kafka-ui-loadbalancer -n odl-demo)"
fi

echo ""
echo "📝 Notes:"
echo "- If IPs are still pending, wait a few minutes and check again"
echo "- Make sure your network allows access to the assigned IP range"
echo "- You can check service status with: kubectl get services -n odl-demo"
echo "- To remove load balancers: kubectl delete -f k8s/loadbalancer/"
