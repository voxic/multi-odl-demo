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
- [ ] Update MongoDB connection strings in `k8s/microservices/aggregation-service-deployment.yaml`
- [ ] Update MongoDB Atlas connection string in `k8s/connectors/mongodb-atlas-connector.json`
- [ ] Replace `YOUR_PASSWORD` with actual `odl-writer` password in connector config
- [ ] Make deployment scripts executable: `chmod +x scripts/*.sh`

## Deployment Steps

### 1. Deploy Infrastructure
- [ ] Run deployment script: `./scripts/deploy.sh`
- [ ] Wait for all pods to be ready: `kubectl get pods -n odl-demo`
- [ ] Verify all services are running: `kubectl get services -n odl-demo`

### 2. Configure Connectors
- [ ] Wait for Kafka Connect to be ready (5-10 minutes): `kubectl wait --for=condition=ready pod -l app=kafka-connect -n odl-demo --timeout=300s`
- [ ] Port-forward Kafka Connect: `kubectl port-forward service/kafka-connect-service 8083:8083 -n odl-demo`
- [ ] Deploy Debezium MySQL connector: `curl -X POST -H "Content-Type: application/json" --data @k8s/connectors/debezium-mysql-connector.json http://localhost:8083/connectors`
- [ ] Deploy MongoDB Atlas connector: `curl -X POST -H "Content-Type: application/json" --data @k8s/connectors/mongodb-atlas-connector.json http://localhost:8083/connectors`
- [ ] Verify connectors are running: `curl http://localhost:8083/connectors`
- [ ] Check MySQL connector status: `curl http://localhost:8083/connectors/mysql-connector/status`
- [ ] Check MongoDB Atlas connector status: `curl http://localhost:8083/connectors/mongodb-atlas-connector/status`

### 3. Generate Sample Data
- [ ] Connect to MySQL: `kubectl exec -it deployment/mysql -n odl-demo -- mysql -u odl_user -podl_password banking`
- [ ] Run sample data generation script
- [ ] Verify data in MySQL

### 4. Verify Data Flow
- [ ] Check data appears in MongoDB Atlas Cluster 1 (customers collection)
- [ ] Check aggregated data appears in MongoDB Atlas Cluster 2 (analytics collection)
- [ ] Test real-time updates by modifying data in MySQL
- [ ] Verify change streams are working by watching aggregation service logs

## Post-Deployment Verification

### 1. Health Checks
- [ ] All pods are running: `kubectl get pods -n odl-demo`
- [ ] Aggregation service health: `curl http://localhost:3000/health`
- [ ] System statistics: `curl http://localhost:3000/stats`

### 2. Data Flow Testing
- [ ] Insert new customer in MySQL
- [ ] Verify customer appears in Atlas Cluster 1
- [ ] Verify aggregated data appears in Atlas Cluster 2
- [ ] Check aggregation service logs for processing

### 3. Real-time Updates
- [ ] Update customer record in MySQL
- [ ] Verify change streams trigger aggregation
- [ ] Check updated analytics in Atlas Cluster 2

## Demo Preparation

### 1. Demo Script Testing
- [ ] Run demo script: `./scripts/demo.sh`
- [ ] Verify all demo steps work correctly
- [ ] Prepare demo data scenarios
- [ ] Test presentation flow

### 2. Monitoring Setup
- [ ] Deploy health checks: `kubectl apply -f k8s/monitoring/health-checks.yaml`
- [ ] Set up log monitoring
- [ ] Prepare backup plans

## Troubleshooting

### Common Issues
- [ ] MySQL connection issues - check logs and credentials
- [ ] Kafka Connect issues - verify connector configurations and connection strings
- [ ] MongoDB Atlas connection - check IP whitelist and credentials
- [ ] Aggregation service issues - check logs and environment variables
- [ ] Connector deployment failures - check Kafka Connect logs and connector status
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
- [ ] Demo script runs successfully
- [ ] System is stable for presentation duration

## Notes

- Keep MongoDB Atlas clusters running during demo
- Have backup connection strings ready
- Test all scenarios before presentation
- Prepare fallback plans for common issues
