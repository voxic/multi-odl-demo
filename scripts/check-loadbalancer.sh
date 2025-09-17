#!/bin/bash

# Check Load Balancer Status for ODL Demo
# This script shows the current status of load balancer services

echo "🔍 Load Balancer Status Check"
echo "============================="

echo ""
echo "📋 MetalLB Status:"
echo "------------------"
kubectl get pods -n metallb-system 2>/dev/null || echo "MetalLB not installed"

echo ""
echo "🌐 Load Balancer Services:"
echo "--------------------------"
kubectl get services -n odl-demo | grep loadbalancer || echo "No load balancer services found"

echo ""
echo "🔗 Service Details:"
echo "-------------------"

# Check MySQL load balancer
MYSQL_SERVICE=$(kubectl get service mysql-loadbalancer -n odl-demo 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "MySQL Load Balancer:"
    echo "$MYSQL_SERVICE"
    MYSQL_IP=$(kubectl get service mysql-loadbalancer -n odl-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ -n "$MYSQL_IP" ] && [ "$MYSQL_IP" != "null" ]; then
        echo "  Access: mysql://odl_user:odl_password@$MYSQL_IP:3306/banking"
    else
        echo "  Status: External IP pending..."
    fi
else
    echo "MySQL Load Balancer: Not found"
fi

echo ""

# Check Kafka UI load balancer
KAFKA_UI_SERVICE=$(kubectl get service kafka-ui-loadbalancer -n odl-demo 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "Kafka UI Load Balancer:"
    echo "$KAFKA_UI_SERVICE"
    KAFKA_UI_IP=$(kubectl get service kafka-ui-loadbalancer -n odl-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ -n "$KAFKA_UI_IP" ] && [ "$KAFKA_UI_IP" != "null" ]; then
        echo "  Access: http://$KAFKA_UI_IP:8080"
    else
        echo "  Status: External IP pending..."
    fi
else
    echo "Kafka UI Load Balancer: Not found"
fi

echo ""
echo "📝 Notes:"
echo "- If external IPs are pending, wait a few minutes for MetalLB to assign them"
echo "- Make sure your network allows access to the assigned IP range"
echo "- To setup load balancers: ./scripts/setup-loadbalancer.sh"
echo "- To cleanup load balancers: ./scripts/cleanup-loadbalancer.sh"
