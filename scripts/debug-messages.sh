#!/bin/bash

echo "🔍 Debugging MySQL to Kafka message flow..."

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo ""
print_status "1. Checking connector status..."
curl -s http://localhost:8083/connectors/mysql-connector/status | jq .

echo ""
print_status "2. Checking Kafka Connect logs (last 20 lines)..."
kubectl logs -n odl-demo deployment/kafka-connect --tail=20

echo ""
print_status "3. Checking if MySQL is accessible..."
kubectl exec -n odl-demo deployment/kafka-connect -- nc -zv localhost 3306

echo ""
print_status "4. Testing MySQL connection and checking current data..."
kubectl exec -n odl-demo deployment/kafka-connect -- mysql -h localhost -u odl_user -p odl_password -e "SELECT COUNT(*) as customer_count FROM banking.customers; SELECT COUNT(*) as account_count FROM banking.accounts; SELECT COUNT(*) as transaction_count FROM banking.transactions;"

echo ""
print_status "5. Checking Kafka topics and their message counts..."
kubectl exec -n odl-demo deployment/kafka -- kafka-topics --bootstrap-server localhost:9092 --list | grep mysql

echo ""
print_status "6. Checking message counts in each topic..."
for topic in mysql.inventory.customers mysql.inventory.accounts mysql.inventory.transactions mysql.inventory.agreements; do
    echo "Topic: $topic"
    kubectl exec -n odl-demo deployment/kafka -- kafka-run-class kafka.tools.GetOffsetShell --bootstrap-server localhost:9092 --topic $topic --time -1 2>/dev/null || echo "  No messages found"
done

echo ""
print_status "7. Checking if binlog is enabled in MySQL..."
kubectl exec -n odl-demo deployment/mysql -- mysql -u root -p mysql_password -e "SHOW VARIABLES LIKE 'log_bin'; SHOW VARIABLES LIKE 'binlog_format';"

echo ""
print_status "8. Checking MySQL binary log status..."
kubectl exec -n odl-demo deployment/mysql -- mysql -u root -p mysql_password -e "SHOW MASTER STATUS;"

echo ""
print_status "9. Checking recent MySQL binary log events..."
kubectl exec -n odl-demo deployment/mysql -- mysql -u root -p mysql_password -e "SHOW BINLOG EVENTS LIMIT 10;"

echo ""
print_status "Debug complete!"
