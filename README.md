# Operational Data Layer (ODL) Demo

This repository contains a complete demo of an Operational Data Layer using MongoDB Atlas as the target data platform. The architecture demonstrates real-time data synchronization from a MySQL operational system through Kafka-based CDC to multiple MongoDB Atlas clusters.

## Architecture Overview

```
MySQL (Source) → Debezium CDC → Kafka → MongoDB Atlas Cluster 1 (Primary ODL) → MongoDB Atlas Cluster 2 (Analytics/Subset)
                    ↓
            Load Balancer (MetalLB) → External Access (MySQL: 10.64.140.43, Kafka UI: 10.64.140.44)
```

### Key Components

- **Source System**: MySQL database with transactional data
- **Change Data Capture**: Debezium for MySQL CDC
- **Streaming Platform**: Apache Kafka for event streaming
- **Primary ODL**: MongoDB Atlas Cluster 1 (full dataset)
- **Analytics Layer**: MongoDB Atlas Cluster 2 (transformed subset)
- **Orchestration**: MicroK8s for container orchestration
- **Load Balancer**: MetalLB for external service access
- **Transformation Layer**: Node.js microservices for data processing
- **Data Generation**: Python scripts for sample data creation

## Prerequisites

### Required Software
- MicroK8s (or any Kubernetes cluster)
- kubectl
- curl
- Node.js 18+ (for microservices)
- Python 3.8+ (for data generation scripts)

### MicroK8s Setup on Ubuntu 24.04

#### 1. Install MicroK8s and kubectl
```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# Verify kubectl installation
kubectl version --client

# Install MicroK8s
sudo snap install microk8s --classic

# Add your user to the microk8s group
sudo usermod -a -G microk8s $USER

# Apply the group change (logout and login, or use newgrp)
newgrp microk8s

# Verify installation
microk8s status --wait-ready
```

#### 2. Enable Required Add-ons
```bash
# Enable essential add-ons for the ODL demo
microk8s enable dns
microk8s enable storage
microk8s enable ingress

# Enable load balancer for easier access to services (default behavior)
microk8s enable metallb

# Optional: Enable dashboard for monitoring
microk8s enable dashboard

# Check status
microk8s status
```

#### 3. Configure kubectl
```bash
# Create kubectl config directory
mkdir -p ~/.kube

# Copy MicroK8s config to kubectl
microk8s config > ~/.kube/config

# Verify kubectl works
kubectl get nodes
kubectl get pods -A
```

#### 4. Configure Resource Limits (Important for Demo)
```bash
# Check available resources
microk8s kubectl top nodes

# If needed, increase MicroK8s resource limits
sudo snap set microk8s memory=4G
sudo snap set microk8s cpu=4

# Restart MicroK8s to apply changes
sudo snap restart microk8s
```

#### 5. Verify Setup
```bash
# Check all services are running
microk8s status

# Test with a simple deployment
kubectl run nginx --image=nginx --port=80
kubectl expose pod nginx --port=80 --type=NodePort
kubectl get pods,services

# Clean up test
kubectl delete pod nginx
kubectl delete service nginx
```

#### 6. Troubleshooting MicroK8s

**If MicroK8s fails to start:**
```bash
# Check MicroK8s logs
sudo journalctl -u snap.microk8s.daemon-apiserver
sudo journalctl -u snap.microk8s.daemon-kubelet

# Reset MicroK8s if needed (WARNING: This removes all data)
microk8s reset
```

**If pods are stuck in Pending state:**
```bash
# Check node resources
kubectl describe nodes

# Check if storage is available
kubectl get storageclass
```

**If DNS issues occur:**
```bash
# Restart DNS add-on
microk8s disable dns
microk8s enable dns
```

### MongoDB Atlas Setup
1. Create two MongoDB Atlas clusters:
   - **Cluster 1**: M10 tier (or higher) for primary ODL
   - **Cluster 2**: M5 tier (or higher) for analytics
2. Create database users:
   - `odl-reader` (read access to Cluster 1)
   - `odl-writer` (readWrite access to both clusters)
3. Whitelist your VM's public IP address
4. Get connection strings for both clusters
5. **Important**: Note down the `odl-writer` password as it will be needed for the Kafka Connect MongoDB Atlas connector configuration

### VM Requirements
- CPU: 4 cores minimum
- RAM: 8GB minimum
- Storage: 100GB SSD
- Network: Persistent IP configuration

## Quick Start

### 1. Clone and Setup
```bash
git clone <your-repo-url>
cd 2025_ODL_Demo

# Install Python dependencies
pip install -r requirements.txt
```

### 2. Enable MicroK8s Add-ons
```bash
# Enable required add-ons
microk8s enable dns storage ingress metallb

# Optional: Enable dashboard for monitoring
microk8s enable dashboard
```

### 3. Configure MongoDB Atlas Secrets
Update the connection strings in `k8s/microservices/aggregation-service-deployment.yaml`:

```yaml
stringData:
  cluster1-uri: "mongodb+srv://odl-reader:YOUR_PASSWORD@cluster1.mongodb.net/banking?retryWrites=true&w=majority"
  cluster2-uri: "mongodb+srv://odl-writer:YOUR_PASSWORD@cluster2.mongodb.net/analytics?retryWrites=true&w=majority"
```

### 4. Configure Kafka Connect Connectors

#### 4.1 Update Debezium MySQL Connector
The MySQL connector is pre-configured in `k8s/connectors/debezium-mysql-connector.json` and should work with the default MySQL deployment. No changes needed unless you're using custom MySQL credentials.

#### 4.2 Update MongoDB Atlas Connector
Update the MongoDB Atlas connection string in `k8s/connectors/mongodb-atlas-connector.json`:

```json
{
  "name": "mongodb-atlas-connector",
  "config": {
    "connector.class": "com.mongodb.kafka.connect.MongoSinkConnector",
    "tasks.max": "1",
    "topics": "mysql.inventory.customers,mysql.inventory.accounts,mysql.inventory.transactions,mysql.inventory.agreements",
    "connection.uri": "mongodb+srv://odl-writer:YOUR_PASSWORD@cluster1.mongodb.net/banking?retryWrites=true&w=majority",
    "database": "banking",
    "collection": "customers",
    "document.id.strategy": "com.mongodb.kafka.connect.sink.processor.id.strategy.PartialValueStrategy",
    "document.id.strategy.partial.value.projection.list": "customer_id",
    "document.id.strategy.partial.value.projection.type": "AllowList",
    "writemodel.strategy": "com.mongodb.kafka.connect.sink.writemodel.strategy.ReplaceOneBusinessKeyStrategy",
    "writemodel.strategy.replace.one.filter.field.name": "customer_id",
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "false",
    "value.converter.schemas.enable": "false",
    "transforms": "route",
    "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
    "transforms.route.regex": "mysql.inventory.(.*)",
    "transforms.route.replacement": "$1"
  }
}
```

**Important**: Replace `YOUR_PASSWORD` with your actual MongoDB Atlas password for the `odl-writer` user.

### 5. Deploy Everything

#### Option 1: Default Deployment (Load Balancer - Recommended)
```bash
./scripts/deploy.sh
```

#### Option 2: Port Forwarding Only
```bash
./scripts/deploy.sh --no-loadbalancer
```

**Note**: The deployment script automatically handles Kafka Connect connector deployment after Kafka Connect is ready. You don't need to manually deploy the connectors.

### 6. Verify Deployment
```bash
kubectl get pods -n odl-demo
kubectl get services -n odl-demo
```

### 7. Access Services

#### Option 1: Load Balancer (Default - Recommended)
```bash
# Deploy with load balancer (default behavior)
./scripts/deploy.sh

# After deployment, access services directly via external IPs:
# MySQL: mysql://odl_user:odl_password@10.64.140.43:3306/banking
# Kafka UI: http://10.64.140.44:8080

# Check load balancer status
kubectl get services -n odl-demo | grep loadbalancer
```

#### Option 2: Port Forwarding Only
```bash
# Deploy without load balancer
./scripts/deploy.sh --no-loadbalancer

# Then use port forwarding:
kubectl port-forward service/mysql-service 3306:3306 -n odl-demo
kubectl port-forward service/kafka-service 9092:9092 -n odl-demo
kubectl port-forward service/kafka-connect-service 8083:8083 -n odl-demo
kubectl port-forward service/aggregation-service 3000:3000 -n odl-demo
```

## Kafka UI - Monitoring and Management

Kafka UI provides a web-based interface for monitoring and managing your Kafka cluster and connectors. It's essential for debugging data flow issues and monitoring system health.

### Accessing Kafka UI

#### Load Balancer Access (Recommended)
```bash
# Access via external IP
http://10.64.140.44:8080
```

#### Port Forwarding Access
```bash
# Set up port forwarding
kubectl port-forward service/kafka-ui-loadbalancer 8080:8080 -n odl-demo

# Access via localhost
http://localhost:8080
```

### Kafka UI Features

#### 1. Cluster Overview
- **Brokers**: View broker status, configuration, and metrics
- **Topics**: Browse all Kafka topics and their configurations
- **Messages**: View real-time message flow through topics
- **Consumers**: Monitor consumer groups and their lag

#### 2. Topic Management
- **Topic List**: See all topics including system topics
- **Topic Details**: View partitions, replication factor, and configuration
- **Message Browser**: Browse messages by partition and offset
- **Topic Creation**: Create new topics with custom configurations

#### 3. Connector Management
- **Connector Status**: View all deployed connectors and their status
- **Connector Configuration**: Inspect connector configurations
- **Connector Logs**: View connector-specific logs and errors
- **Connector Control**: Start, stop, restart, and delete connectors

### Key Topics to Monitor

The ODL demo uses these critical topics:
- `mysql.inventory.customers` - Customer data changes
- `mysql.inventory.accounts` - Account data changes  
- `mysql.inventory.transactions` - Transaction data changes
- `mysql.inventory.agreements` - Agreement data changes

## Connector Status Monitoring

### Checking Connector Status

#### 1. Via Kafka UI (Recommended)
1. Open Kafka UI in your browser
2. Navigate to **Connectors** section
3. View connector list with status indicators:
   - **RUNNING** (Green) - Connector is healthy and processing data
   - **FAILED** (Red) - Connector has errors and needs attention
   - **PAUSED** (Yellow) - Connector is temporarily stopped
   - **UNASSIGNED** (Gray) - Connector is not assigned to any worker

#### 2. Via REST API
```bash
# List all connectors
curl http://localhost:8083/connectors

# Check specific connector status
curl http://localhost:8083/connectors/debezium-mysql-connector/status
curl http://localhost:8083/connectors/mongodb-atlas-connector/status

# Get connector configuration
curl http://localhost:8083/connectors/debezium-mysql-connector/config

# Get connector tasks
curl http://localhost:8083/connectors/debezium-mysql-connector/tasks
```

#### 3. Via kubectl
```bash
# Check Kafka Connect logs
kubectl logs deployment/kafka-connect -n odl-demo

# Check specific connector logs
kubectl logs deployment/kafka-connect -n odl-demo | grep "debezium-mysql-connector"
kubectl logs deployment/kafka-connect -n odl-demo | grep "mongodb-atlas-connector"
```

### Connector Health Indicators

#### Healthy Connector Status
```json
{
  "name": "debezium-mysql-connector",
  "connector": {
    "state": "RUNNING",
    "worker_id": "kafka-connect-0:8083"
  },
  "tasks": [
    {
      "id": 0,
      "state": "RUNNING",
      "worker_id": "kafka-connect-0:8083"
    }
  ]
}
```

#### Failed Connector Status
```json
{
  "name": "mongodb-atlas-connector",
  "connector": {
    "state": "FAILED",
    "worker_id": "kafka-connect-0:8083",
    "trace": "Connection refused to MongoDB Atlas cluster"
  },
  "tasks": [
    {
      "id": 0,
      "state": "FAILED",
      "worker_id": "kafka-connect-0:8083",
      "trace": "Connection refused to MongoDB Atlas cluster"
    }
  ]
}
```

### Troubleshooting Connector Issues

#### 1. MySQL Connector (Debezium) Issues

**Common Problems:**
- MySQL connection failures
- Binlog not enabled
- User permissions issues
- Network connectivity problems

**Debugging Steps:**
```bash
# Check connector status
curl http://localhost:8083/connectors/debezium-mysql-connector/status

# Check connector logs
kubectl logs deployment/kafka-connect -n odl-demo | grep -i "debezium"

# Test MySQL connection
kubectl exec -it deployment/mysql -n odl-demo -- mysql -u odl_user -podl_password -e "SHOW MASTER STATUS;"

# Check if binlog is enabled
kubectl exec -it deployment/mysql -n odl-demo -- mysql -u odl_user -podl_password -e "SHOW VARIABLES LIKE 'log_bin';"
```

**Common Fixes:**
```bash
# Restart connector
curl -X POST http://localhost:8083/connectors/debezium-mysql-connector/restart

# Delete and recreate connector
curl -X DELETE http://localhost:8083/connectors/debezium-mysql-connector
curl -X POST -H "Content-Type: application/json" \
  --data @k8s/connectors/debezium-mysql-connector.json \
  http://localhost:8083/connectors
```

#### 2. MongoDB Atlas Connector Issues

**Common Problems:**
- Authentication failures
- Network connectivity issues
- IP whitelist problems
- Database/collection access issues

**Debugging Steps:**
```bash
# Check connector status
curl http://localhost:8083/connectors/mongodb-atlas-connector/status

# Check connector logs
kubectl logs deployment/kafka-connect -n odl-demo | grep -i "mongodb"

# Test MongoDB connection (if you have mongosh installed)
mongosh "mongodb+srv://odl-writer:YOUR_PASSWORD@cluster1.mongodb.net/banking"
```

**Common Fixes:**
```bash
# Verify connection string format
# Should be: mongodb+srv://odl-writer:PASSWORD@cluster1.mongodb.net/banking?retryWrites=true&w=majority

# Check IP whitelist in MongoDB Atlas
# Ensure your VM's public IP is whitelisted

# Restart connector
curl -X POST http://localhost:8083/connectors/mongodb-atlas-connector/restart

# Delete and recreate connector
curl -X DELETE http://localhost:8083/connectors/mongodb-atlas-connector
curl -X POST -H "Content-Type: application/json" \
  --data @k8s/connectors/mongodb-atlas-connector.json \
  http://localhost:8083/connectors
```

### Data Flow Verification

#### 1. Check Topic Messages
```bash
# View messages in customer topic
kubectl exec -it deployment/kafka -n odl-demo -- kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic mysql.inventory.customers \
  --from-beginning

# View messages in account topic
kubectl exec -it deployment/kafka -n odl-demo -- kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic mysql.inventory.accounts \
  --from-beginning
```

#### 2. Check MongoDB Collections
```bash
# Connect to MongoDB Atlas (if mongosh is available)
mongosh "mongodb+srv://odl-reader:YOUR_PASSWORD@cluster1.mongodb.net/banking"

# Check collections
show collections

# Check customer data
db.customers.find().limit(5)

# Check account data
db.accounts.find().limit(5)
```

#### 3. Real-time Monitoring
```bash
# Watch connector logs in real-time
kubectl logs -f deployment/kafka-connect -n odl-demo

# Watch aggregation service logs
kubectl logs -f deployment/aggregation-service -n odl-demo

# Monitor topic message flow
kubectl exec -it deployment/kafka -n odl-demo -- kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic mysql.inventory.customers
```

## Load Balancer Configuration

The demo uses MetalLB for load balancing with the following IP allocation:

- **IP Range**: `10.64.140.43-10.64.140.49`
- **MySQL Load Balancer**: `10.64.140.43:3306`
- **Kafka UI Load Balancer**: `10.64.140.44:8080`

### Benefits of Load Balancer

- **No Port Forwarding**: Direct external access to services
- **Predictable IPs**: Fixed IP addresses for easy connection
- **Better for Demos**: Share IPs directly with others
- **Production-like**: More realistic than port forwarding
- **Persistent Access**: Services remain accessible across sessions

### Load Balancer Management

```bash
# Check load balancer status
kubectl get services -n odl-demo | grep loadbalancer

# Check MetalLB status
kubectl get pods -n metallb-system

# View load balancer details
kubectl describe service mysql-loadbalancer -n odl-demo
kubectl describe service kafka-ui-loadbalancer -n odl-demo
```

## Demo Script

### 1. Check System Health
```bash
# View health check logs
kubectl logs -f deployment/aggregation-service -n odl-demo

# Check aggregation service API
curl http://localhost:3000/health
curl http://localhost:3000/stats
```

### 2. Generate Sample Data

#### Option 1: Port Forward (Recommended)
```bash
# In one terminal, set up port forwarding
kubectl port-forward service/mysql-service 3306:3306 -n odl-demo

# In another terminal, run the script
python3 scripts/generate-sample-data.py
```

#### Option 2: Run inside MySQL pod
```bash
# Copy script to MySQL pod
kubectl cp scripts/generate-sample-data.py odl-demo/$(kubectl get pods -n odl-demo -l app=mysql -o jsonpath='{.items[0].metadata.name}'):/tmp/

# Run script inside the pod
kubectl exec -it deployment/mysql -n odl-demo -- python3 /tmp/generate-sample-data.py
```

#### Option 3: Manual data insertion
```bash
# Connect to MySQL and generate data manually
kubectl exec -it deployment/mysql -n odl-demo -- mysql -u odl_user -podl_password banking

# In MySQL shell:
INSERT INTO customers (first_name, last_name, email, customer_status) 
VALUES ('Demo', 'User', 'demo@example.com', 'ACTIVE');
```

### 3. Verify Data Flow
1. **Check MySQL**: Data should be in the source database
2. **Check Kafka Topics**: Data should flow through Kafka
3. **Check Atlas Cluster 1**: Raw data should appear in primary ODL
4. **Check Atlas Cluster 2**: Aggregated analytics should appear

### 4. Real-time Demo
```bash
# Make changes in MySQL
kubectl exec -it deployment/mysql -n odl-demo -- mysql -u odl_user -podl_password banking

# Update a customer record
UPDATE customers SET first_name = 'Updated' WHERE customer_id = 1;

# Watch the aggregation service logs
kubectl logs -f deployment/aggregation-service -n odl-demo
```

## API Endpoints

### Aggregation Service
- `GET /health` - Health check
- `GET /stats` - System statistics
- `POST /aggregate` - Trigger aggregation
  - Body: `{"customerId": 123}` (optional)

### Kafka Connect
- `GET /connectors` - List connectors
- `GET /connectors/{name}/status` - Connector status
- `POST /connectors` - Create connector

## Monitoring

### Health Checks
```bash
# Run health check
kubectl apply -f k8s/monitoring/health-checks.yaml

# View health check logs
kubectl logs -f job/health-check-cronjob -n odl-demo
```

### Logs
```bash
# All services
kubectl logs -f -l app=mysql -n odl-demo
kubectl logs -f -l app=kafka -n odl-demo
kubectl logs -f -l app=kafka-connect -n odl-demo
kubectl logs -f -l app=aggregation-service -n odl-demo
```

## Troubleshooting

### Common Issues

1. **MySQL Connection Issues**
   ```bash
   kubectl logs deployment/mysql -n odl-demo
   kubectl describe pod -l app=mysql -n odl-demo
   ```

2. **Kafka Connect Issues**
   ```bash
   kubectl logs deployment/kafka-connect -n odl-demo
   curl http://localhost:8083/connectors
   ```

3. **MongoDB Atlas Connection Issues**
   - Verify IP whitelist
   - Check connection strings
   - Verify database user permissions

4. **Aggregation Service Issues**
   ```bash
   kubectl logs deployment/aggregation-service -n odl-demo
   curl http://localhost:3000/health
   ```

5. **Kafka Connect Connector Issues**
   ```bash
   # Check connector status
   curl http://localhost:8083/connectors/mysql-connector/status
   curl http://localhost:8083/connectors/mongodb-atlas-connector/status
   
   # Check connector logs
   kubectl logs deployment/kafka-connect -n odl-demo
   
   # Restart connector if needed
   curl -X POST http://localhost:8083/connectors/mysql-connector/restart
   curl -X POST http://localhost:8083/connectors/mongodb-atlas-connector/restart
   
   # Delete and recreate connector if needed
   curl -X DELETE http://localhost:8083/connectors/mysql-connector
   curl -X DELETE http://localhost:8083/connectors/mongodb-atlas-connector
   
   # Manually deploy connectors if automatic deployment failed
   kubectl port-forward service/kafka-connect-service 8083:8083 -n odl-demo &
   curl -X POST -H "Content-Type: application/json" \
     --data @k8s/connectors/debezium-mysql-connector.json \
     http://localhost:8083/connectors
   curl -X POST -H "Content-Type: application/json" \
     --data @k8s/connectors/mongodb-atlas-connector.json \
     http://localhost:8083/connectors
   ```

6. **Load Balancer Issues**
   ```bash
   # Check if MetalLB is running
   kubectl get pods -n metallb-system
   
   # Check load balancer services
   kubectl get services -n odl-demo | grep loadbalancer
   
   # Check MetalLB logs
   kubectl logs -n metallb-system -l app=metallb
   
   # If services don't get external IPs, check IP pool configuration
   kubectl get configmap -n metallb-system config -o yaml
   
   # Verify IP range is available on your network
   ping 10.64.140.43
   ping 10.64.140.44
   
   # Restart MetalLB if needed
   microk8s disable metallb
   microk8s enable metallb
   
   # Recreate load balancer services
   kubectl delete service mysql-loadbalancer kafka-ui-loadbalancer -n odl-demo
   kubectl apply -f k8s/loadbalancer/
   ```

7. **Kafka UI Issues**
   ```bash
   # Check if Kafka UI pod is running
   kubectl get pods -n odl-demo | grep kafka-ui
   
   # Check Kafka UI logs
   kubectl logs deployment/kafka-ui -n odl-demo
   
   # Check Kafka UI service
   kubectl get service kafka-ui-loadbalancer -n odl-demo
   
   # Verify Kafka UI can connect to Kafka
   kubectl exec -it deployment/kafka-ui -n odl-demo -- curl http://localhost:8080/actuator/health
   
   # Check if Kafka UI is accessible via port forwarding
   kubectl port-forward service/kafka-ui-loadbalancer 8080:8080 -n odl-demo
   # Then test: curl http://localhost:8080
   
   # Restart Kafka UI if needed
   kubectl rollout restart deployment/kafka-ui -n odl-demo
   
   # Check Kafka UI configuration
   kubectl describe deployment kafka-ui -n odl-demo
   ```

8. **Kafka UI Connection Issues**
   ```bash
   # Verify Kafka UI can reach Kafka brokers
   kubectl exec -it deployment/kafka-ui -n odl-demo -- nslookup kafka-service
   
   # Check network connectivity
   kubectl exec -it deployment/kafka-ui -n odl-demo -- telnet kafka-service 9092
   
   # Verify Kafka UI environment variables
   kubectl exec -it deployment/kafka-ui -n odl-demo -- env | grep KAFKA
   
   # Check if Kafka UI is using correct bootstrap servers
   kubectl get configmap kafka-ui-config -n odl-demo -o yaml
   ```

9. **Kafka UI Performance Issues**
   ```bash
   # Check Kafka UI resource usage
   kubectl top pod -l app=kafka-ui -n odl-demo
   
   # Check if Kafka UI has enough memory
   kubectl describe pod -l app=kafka-ui -n odl-demo
   
   # Monitor Kafka UI logs for memory issues
   kubectl logs deployment/kafka-ui -n odl-demo | grep -i "out of memory"
   
   # Check Kafka UI metrics endpoint
   kubectl exec -it deployment/kafka-ui -n odl-demo -- curl http://localhost:8080/actuator/metrics
   ```

### Reset Everything
```bash
./scripts/cleanup.sh
./scripts/deploy.sh
```

## File Structure

```
2025_ODL_Demo/
├── k8s/
│   ├── mysql/
│   │   ├── mysql-deployment.yaml
│   │   └── mysql-init-scripts.yaml
│   ├── kafka/
│   │   ├── kafka-all-in-one.yaml
│   │   └── kafka-connect.yaml
│   ├── connectors/
│   │   ├── debezium-mysql-connector.json
│   │   └── mongodb-atlas-connector.json
│   ├── microservices/
│   │   └── aggregation-service-deployment.yaml
│   ├── monitoring/
│   │   └── health-checks.yaml
│   └── loadbalancer/
│       ├── metallb-config.yaml
│       ├── mysql-loadbalancer.yaml
│       └── kafka-ui-loadbalancer.yaml
├── microservices/
│   └── aggregation-service/
│       ├── package.json
│       └── index.js
├── scripts/
│   ├── deploy.sh
│   ├── cleanup.sh
│   └── generate-sample-data.py
├── requirements.txt
└── README.md
```

## Performance Tuning

### For Production Use
1. Increase resource limits in deployment files
2. Use persistent volumes with appropriate storage classes
3. Configure proper backup strategies
4. Set up monitoring and alerting
5. Use proper security configurations

### For Demo Use
- Current configuration is optimized for demo purposes
- Uses minimal resources for easy deployment
- Includes sample data generation for quick testing

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review logs for error messages
3. Verify all prerequisites are met
4. Ensure MongoDB Atlas clusters are properly configured

## License

MIT License - see LICENSE file for details.
