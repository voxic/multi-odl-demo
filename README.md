# Operational Data Layer (ODL) Demo

This repository contains a complete demo of an Operational Data Layer using MongoDB Atlas as the target data platform. The architecture demonstrates real-time data synchronization from a MySQL operational system through Kafka-based CDC to multiple MongoDB Atlas clusters.

## Architecture Overview

```
MySQL (Source) → Debezium CDC → Kafka → MongoDB Atlas Cluster 1 (Primary ODL) → MongoDB Atlas Cluster 2 (Analytics/Subset)
```

### Key Components

- **Source System**: MySQL database with transactional data
- **Change Data Capture**: Debezium for MySQL CDC
- **Streaming Platform**: Apache Kafka for event streaming
- **Primary ODL**: MongoDB Atlas Cluster 1 (full dataset)
- **Analytics Layer**: MongoDB Atlas Cluster 2 (transformed subset)
- **Orchestration**: MicroK8s for container orchestration
- **Transformation Layer**: Node.js microservices for data processing

## Prerequisites

### Required Software
- MicroK8s (or any Kubernetes cluster)
- kubectl
- curl
- Node.js 18+ (for local development)

### MongoDB Atlas Setup
1. Create two MongoDB Atlas clusters:
   - **Cluster 1**: M10 tier (or higher) for primary ODL
   - **Cluster 2**: M5 tier (or higher) for analytics
2. Create database users:
   - `odl-reader` (read access to Cluster 1)
   - `odl-writer` (readWrite access to both clusters)
3. Whitelist your VM's public IP address
4. Get connection strings for both clusters

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
```

### 2. Configure MongoDB Atlas Secrets
Update the connection strings in `k8s/microservices/aggregation-service-deployment.yaml`:

```yaml
stringData:
  cluster1-uri: "mongodb+srv://odl-reader:YOUR_PASSWORD@cluster1.mongodb.net/banking?retryWrites=true&w=majority"
  cluster2-uri: "mongodb+srv://odl-writer:YOUR_PASSWORD@cluster2.mongodb.net/analytics?retryWrites=true&w=majority"
```

### 3. Deploy Everything
```bash
./scripts/deploy.sh
```

### 4. Verify Deployment
```bash
kubectl get pods -n odl-demo
kubectl get services -n odl-demo
```

### 5. Access Services
```bash
# MySQL
kubectl port-forward service/mysql-service 3306:3306 -n odl-demo

# Kafka
kubectl port-forward service/kafka-service 9092:9092 -n odl-demo

# Kafka Connect
kubectl port-forward service/kafka-connect-service 8083:8083 -n odl-demo

# Aggregation Service
kubectl port-forward service/aggregation-service 3000:3000 -n odl-demo
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
```bash
# Connect to MySQL and generate data
kubectl exec -it deployment/mysql -n odl-demo -- mysql -u odl_user -podl_password banking

# In MySQL shell:
INSERT INTO customers (first_name, last_name, email, customer_status) 
VALUES ('Demo', 'User', 'demo@example.com', 'ACTIVE');

# Or use the sample data script
node scripts/generate-sample-data.js
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
│   └── monitoring/
│       └── health-checks.yaml
├── microservices/
│   └── aggregation-service/
│       ├── package.json
│       └── index.js
├── scripts/
│   ├── deploy.sh
│   ├── cleanup.sh
│   └── generate-sample-data.js
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
