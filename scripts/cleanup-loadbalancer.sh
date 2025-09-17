#!/bin/bash

# Cleanup Load Balancer for ODL Demo
# This script removes load balancer services and optionally disables MetalLB

set -e

echo "🧹 Cleaning up Load Balancer for ODL Demo..."

# Remove load balancer services
echo "🗑️  Removing load balancer services..."
kubectl delete -f k8s/loadbalancer/mysql-loadbalancer.yaml 2>/dev/null || echo "MySQL load balancer not found"
kubectl delete -f k8s/loadbalancer/kafka-ui-loadbalancer.yaml 2>/dev/null || echo "Kafka UI load balancer not found"

# Remove MetalLB configuration
echo "🗑️  Removing MetalLB configuration..."
kubectl delete -f k8s/loadbalancer/metallb-config.yaml 2>/dev/null || echo "MetalLB config not found"

# Ask if user wants to disable MetalLB completely
echo ""
read -p "Do you want to disable MetalLB completely? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🔧 Disabling MetalLB add-on..."
    microk8s disable metallb
    echo "✅ MetalLB disabled"
else
    echo "ℹ️  MetalLB remains enabled but load balancer services removed"
fi

echo ""
echo "✅ Load balancer cleanup completed!"
echo ""
echo "📋 Remaining services:"
kubectl get services -n odl-demo
