#!/bin/bash

# Debug script for Debezium MySQL connector issues

echo "🔍 Debugging Debezium MySQL Connector..."

# Check if we can connect to Kafka
echo "1. Checking Kafka connectivity..."
kubectl exec -n odl-demo deployment/kafka -- kafka-topics --bootstrap-server localhost:9092 --list

echo ""
echo "2. Checking existing topics..."
kubectl exec -n odl-demo deployment/kafka -- kafka-topics --bootstrap-server localhost:9092 --list

echo ""
echo "3. Creating schema history topic manually..."
kubectl exec -n odl-demo deployment/kafka -- kafka-topics --bootstrap-server localhost:9092 \
  --create --topic mysql.history \
  --partitions 1 \
  --replication-factor 1 \
  --config cleanup.policy=compact \
  --config retention.ms=604800000 || echo "Topic might already exist"

echo ""
echo "4. Verifying topic creation..."
kubectl exec -n odl-demo deployment/kafka -- kafka-topics --bootstrap-server localhost:9092 --describe --topic mysql.history

echo ""
echo "5. Checking Kafka Connect logs..."
echo "Recent Kafka Connect logs:"
kubectl logs -n odl-demo deployment/kafka-connect --tail=20

echo ""
echo "6. Checking if MySQL is accessible from Kafka Connect pod..."
kubectl exec -n odl-demo deployment/kafka-connect -- nc -zv localhost 3306

echo ""
echo "7. Testing MySQL connection from Kafka Connect pod..."
kubectl exec -n odl-demo deployment/kafka-connect -- mysql -h localhost -u odl_user -p odl_password -e "SELECT 1;" banking

echo ""
echo "8. Current connector status..."
curl -s http://localhost:8083/connectors/mysql-connector/status | jq .

echo ""
echo "Debug complete!"
