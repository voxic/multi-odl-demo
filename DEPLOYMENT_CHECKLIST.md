# ODL Demo Deployment Checklist

## Pre-Deployment Setup

### 1. MongoDB Atlas Setup
- [ ] Create MongoDB Atlas account
- [ ] Create Cluster 1 (M10 or higher) for primary ODL
- [ ] Create Cluster 2 (M5 or higher) for analytics
- [ ] Create database user `odl-reader` with read access to Cluster 1
- [ ] Create database user `odl-writer` with readWrite access to both clusters
- [ ] **IMPORTANT**: Note down the `odl-writer` password for connector configuration
- [ ] Whitelist VM public IP address
- [ ] Get connection strings for both clusters
- [ ] Test connections from VM

### 2. VM Preparation
- [ ] Ensure VM has MicroK8s installed and running
- [ ] Verify kubectl is working: `kubectl cluster-info`
- [ ] Check available resources: `kubectl top nodes`
- [ ] Ensure VM has internet access for pulling images

### 3. Code Preparation
- [ ] Clone repository to VM
- [ ] Install Python dependencies: `pip install -r requirements.txt`
- [ ] Update MongoDB connection strings in `k8s/microservices/aggregation-service-deployment.yaml`
- [ ] Update MongoDB connection strings in `k8s/microservices/customer-profile-service-deployment.yaml`
- [ ] Update MongoDB Atlas connection string in `k8s/connectors/mongodb-atlas-connector.json`
- [ ] Replace `YOUR_PASSWORD` with actual `odl-writer` password in connector config
- [ ] Make deployment scripts executable: `chmod +x scripts/*.sh`
- [ ] **Note**: The aggregation service has been updated to work with the flat MySQL data structure (not nested)

## Deployment Steps

### 1. Deploy Infrastructure (Single Command)
- [ ] **For Host Networking (Recommended)**: Run `./scripts/deploy-hostnetwork.sh`
  - [ ] This deploys all infrastructure including UIs in one command
  - [ ] UIs are built inside Kubernetes using ConfigMaps
  - [ ] No Docker image building required
  - [ ] Direct access to all services on standard ports
- [ ] **For Standard Deployment**: Run `./scripts/deploy.sh`
- [ ] Wait for all pods to be ready: `kubectl get pods -n odl-demo`
- [ ] Verify all services are running: `kubectl get services -n odl-demo`

### 2. Configure Connectors
- [ ] Wait for Kafka Connect to be ready (5-10 minutes): `kubectl wait --for=condition=ready pod -l app=kafka-connect -n odl-demo --timeout=300s`
- [ ] **For Host Networking**: Connectors are automatically deployed by the script
- [ ] **For Regular Deployment**: Port-forward Kafka Connect: `kubectl port-forward service/kafka-connect-service 8083:8083 -n odl-demo`
- [ ] Deploy Debezium MySQL connector: `curl -X POST -H "Content-Type: application/json" --data @k8s/connectors/debezium-mysql-connector-hostnetwork.json http://localhost:8083/connectors`
- [ ] Deploy MongoDB Atlas connector: `curl -X POST -H "Content-Type: application/json" --data @k8s/connectors/mongodb-atlas-connector.json http://localhost:8083/connectors`
- [ ] Verify connectors are running: `curl http://localhost:8083/connectors`
- [ ] Check MySQL connector status: `curl http://localhost:8083/connectors/mysql-connector/status`
- [ ] Check MongoDB Atlas connector status: `curl http://localhost:8083/connectors/mongodb-atlas-connector/status`
- [ ] **IMPORTANT**: If MySQL connector fails with permission errors, the init scripts should handle this automatically

### 3. Generate Sample Data
- [ ] **Option 1 (Recommended)**: Set up port forwarding: `kubectl port-forward service/mysql-service 3306:3306 -n odl-demo`
- [ ] Run Python sample data generation script: `python3 scripts/generate-sample-data.py`
- [ ] **Option 2**: Copy script to pod: `kubectl cp scripts/generate-sample-data.py odl-demo/$(kubectl get pods -n odl-demo -l app=mysql -o jsonpath='{.items[0].metadata.name}'):/tmp/`
- [ ] Run script in pod: `kubectl exec -it deployment/mysql -n odl-demo -- python3 /tmp/generate-sample-data.py`
- [ ] Verify data in MySQL: `kubectl exec -it deployment/mysql -n odl-demo -- mysql -u odl_user -podl_password banking -e "SELECT COUNT(*) FROM customers;"`

### 4. Verify Data Flow
- [ ] Check data appears in MongoDB Atlas Cluster 1 (customers collection)
- [ ] Check aggregated analytics appear in MongoDB Atlas Cluster 2 (`analytics.customer_analytics`)
- [ ] Check customer profiles appear in MongoDB Atlas Cluster 2 (`analytics.customer_profile`)
- [ ] Test real-time updates by modifying data in MySQL
- [ ] Verify change streams are working by watching aggregation service logs

## Post-Deployment Verification

### 1. Health Checks
- [ ] All pods are running: `kubectl get pods -n odl-demo`
- [ ] Aggregation service health: `curl http://localhost:3000/health`
- [ ] Customer profile service health: `curl http://localhost:3001/health`
- [ ] System statistics: `curl http://localhost:3000/stats`
- [ ] Legacy UI accessible: `curl http://YOUR_VM_IP:3001/health`
- [ ] Analytics UI accessible: `curl http://YOUR_VM_IP:3002/api/health`

### 2. Data Flow Testing
- [ ] Insert new customer in MySQL
- [ ] Verify customer appears in Atlas Cluster 1
- [ ] Verify aggregated data appears in Atlas Cluster 2
- [ ] Check aggregation service logs for processing

### 3. Real-time Updates
- [ ] Update customer record in MySQL
- [ ] Verify change streams trigger aggregation
- [ ] Check updated analytics in Atlas Cluster 2 (`analytics.customer_analytics`)
- [ ] Check updated profile in Atlas Cluster 2 (`analytics.customer_profile`)

## Demo Preparation

### 1. Demo Script Testing
- [ ] Run demo script: `./scripts/demo.sh`
- [ ] Verify all demo steps work correctly
- [ ] Test Legacy UI functionality:
  - [ ] Access http://YOUR_VM_IP:3001
  - [ ] Test customer management features
  - [ ] Test account management features
  - [ ] Test transaction viewing and adding
- [ ] Test Analytics UI functionality:
  - [ ] Access http://YOUR_VM_IP:3002
  - [ ] Verify data visualization
  - [ ] Test real-time updates
- [ ] Prepare demo data scenarios
- [ ] Test presentation flow

### 2. Monitoring Setup
- [ ] Deploy health checks: `kubectl apply -f k8s/monitoring/health-checks.yaml`
- [ ] Set up log monitoring
- [ ] Prepare backup plans

## Troubleshooting

### Common Issues

#### MySQL Connector Permission Errors
- [ ] **Error**: `Access denied; you need (at least one of) the RELOAD or FLUSH_TABLES privilege(s)`
- [ ] **Solution**: The init scripts should handle this automatically, but if not:
  ```bash
  kubectl exec -n odl-demo deployment/mysql -- mysql -u root -p mysql_password -e "
  GRANT RELOAD, FLUSH_TABLES ON *.* TO 'odl_user'@'%';
  GRANT REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO 'odl_user'@'%';
  GRANT SELECT ON banking.* TO 'odl_user'@'%';
  FLUSH PRIVILEGES;
  "
  ```

#### Schema History Configuration Errors
- [ ] **Error**: `Error configuring an instance of KafkaSchemaHistory`
- [ ] **Solution**: Delete and recreate the connector:
  ```bash
  curl -X DELETE http://localhost:8083/connectors/mysql-connector
  curl -X POST -H "Content-Type: application/json" \
    --data @k8s/connectors/debezium-mysql-connector-hostnetwork.json \
    http://localhost:8083/connectors
  ```

#### MongoDB Connector Topic Errors
- [ ] **Error**: `Unknown topic: customers, must be one of: [mysql.inventory.customers, ...]`
- [ ] **Solution**: Delete and recreate the connector:
  ```bash
  curl -X DELETE http://localhost:8083/connectors/mongodb-atlas-connector
  curl -X POST -H "Content-Type: application/json" \
    --data @k8s/connectors/mongodb-atlas-connector.json \
    http://localhost:8083/connectors
  ```

#### No Messages in Kafka Topics
- [ ] Check MySQL connector status: `curl http://localhost:8083/connectors/mysql-connector/status`
- [ ] Check MySQL binary log: `kubectl exec -n odl-demo deployment/mysql -- mysql -u root -p mysql_password -e "SHOW VARIABLES LIKE 'log_bin';"`
- [ ] Make test changes in MySQL and verify they appear in Kafka

#### Aggregation Service Issues
- [ ] **Error**: Service not processing data correctly
- [ ] **Solution**: Update and restart the service:
  ```bash
  kubectl create configmap aggregation-source -n odl-demo \
    --from-file=package.json=microservices/aggregation-service/package.json \
    --from-file=index.js=microservices/aggregation-service/index.js \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl rollout restart deployment/aggregation-service -n odl-demo
  ```

#### UI Service Issues
- [ ] **Error**: Legacy UI not accessible or not working
- [ ] **Solution**: Check and restart the service:
  ```bash
  kubectl get pods -n odl-demo -l app=legacy-ui
  kubectl logs -n odl-demo deployment/legacy-ui --tail=50
  kubectl rollout restart deployment/legacy-ui -n odl-demo
  ```
- [ ] **Error**: Analytics UI not accessible or not working
- [ ] **Solution**: Check and restart the service:
  ```bash
  kubectl get pods -n odl-demo -l app=analytics-ui
  kubectl logs -n odl-demo deployment/analytics-ui --tail=50
  kubectl rollout restart deployment/analytics-ui -n odl-demo
  ```
- [ ] **Error**: UI ConfigMaps missing or outdated
- [ ] **Solution**: Recreate ConfigMaps and restart deployments:
  ```bash
  # For Legacy UI
  kubectl create configmap legacy-ui-source \
    --from-file=package.json=microservices/legacy-ui/package.json \
    --from-file=server.js=microservices/legacy-ui/server.js \
    --from-file=public/index.html=microservices/legacy-ui/public/index.html \
    --from-file=public/script.js=microservices/legacy-ui/public/script.js \
    --from-file=public/styles.css=microservices/legacy-ui/public/styles.css \
    -n odl-demo --dry-run=client -o yaml | kubectl apply -f -
  
  # For Analytics UI
  kubectl create configmap analytics-ui-source \
    --from-file=package.json=microservices/analytics-ui/package.json \
    --from-file=server.js=microservices/analytics-ui/server.js \
    --from-file=public/index.html=microservices/analytics-ui/public/index.html \
    --from-file=public/script.js=microservices/analytics-ui/public/script.js \
    --from-file=public/styles.css=microservices/analytics-ui/public/styles.css \
    -n odl-demo --dry-run=client -o yaml | kubectl apply -f -
  ```

### Debug Commands
- [ ] Check all pods: `kubectl get pods -n odl-demo`
- [ ] Check connector status: `curl http://localhost:8083/connectors`
- [ ] View MySQL logs: `kubectl logs -n odl-demo deployment/mysql --tail=50`
- [ ] View Kafka Connect logs: `kubectl logs -n odl-demo deployment/kafka-connect --tail=50`
- [ ] View aggregation service logs: `kubectl logs -n odl-demo deployment/aggregation-service --tail=50`
- [ ] View customer profile service logs: `kubectl logs -n odl-demo deployment/customer-profile-service --tail=50`
- [ ] View Legacy UI logs: `kubectl logs -n odl-demo deployment/legacy-ui --tail=50`
- [ ] View Analytics UI logs: `kubectl logs -n odl-demo deployment/analytics-ui --tail=50`
- [ ] Check UI ConfigMaps: `kubectl get configmaps -n odl-demo | grep ui`
- [ ] Data not flowing to MongoDB - verify connector status and topic routing

### Recovery Steps
- [ ] Check pod logs: `kubectl logs -f deployment/<service-name> -n odl-demo`
- [ ] Check connector status: `curl http://localhost:8083/connectors/<connector-name>/status`
- [ ] Restart connectors if needed: `curl -X POST http://localhost:8083/connectors/<connector-name>/restart`
- [ ] Delete and recreate connectors if needed: `curl -X DELETE http://localhost:8083/connectors/<connector-name>`
- [ ] Restart services if needed: `kubectl rollout restart deployment/<service-name> -n odl-demo`
- [ ] Full reset if necessary: `./scripts/cleanup.sh && ./scripts/deploy.sh`

### Connector-Specific Troubleshooting
- [ ] **MySQL Connector Issues**:
  - Check connector status: `curl http://localhost:8083/connectors/mysql-connector/status`
  - Verify MySQL is accessible: `kubectl exec -it deployment/mysql -n odl-demo -- mysql -u odl_user -podl_password banking`
  - Check connector logs: `kubectl logs deployment/kafka-connect -n odl-demo | grep mysql-connector`
- [ ] **MongoDB Atlas Connector Issues**:
  - Check connector status: `curl http://localhost:8083/connectors/mongodb-atlas-connector/status`
  - Verify connection string is correct in `k8s/connectors/mongodb-atlas-connector.json`
  - Test MongoDB connection from VM: `mongosh "mongodb+srv://odl-writer:PASSWORD@cluster1.mongodb.net/banking"`
  - Check connector logs: `kubectl logs deployment/kafka-connect -n odl-demo | grep mongodb-atlas-connector`
- [ ] **Data Flow Issues**:
  - Check Kafka topics: `kubectl exec -it deployment/kafka -n odl-demo -- kafka-topics --bootstrap-server localhost:9092 --list`
  - Verify topic data: `kubectl exec -it deployment/kafka -n odl-demo -- kafka-console-consumer --bootstrap-server localhost:9092 --topic mysql.inventory.customers --from-beginning`

## Cleanup

### After Demo
- [ ] Run cleanup script: `./scripts/cleanup.sh`
- [ ] Verify all resources are removed: `kubectl get all -A | grep odl-demo`
- [ ] Clean up MongoDB Atlas clusters if no longer needed

## Success Criteria

- [ ] All services are running and healthy
- [ ] Data flows from MySQL to Atlas Cluster 1
- [ ] Aggregated data appears in Atlas Cluster 2
- [ ] Real-time updates work correctly
- [ ] Legacy UI is accessible and functional at http://YOUR_VM_IP:3001
- [ ] Analytics UI is accessible and functional at http://YOUR_VM_IP:3002
- [ ] UIs can interact with the data pipeline
- [ ] Demo script runs successfully
- [ ] System is stable for presentation duration

## Notes

- Keep MongoDB Atlas clusters running during demo
- Have backup connection strings ready
- Test all scenarios before presentation
- Prepare fallback plans for common issues
