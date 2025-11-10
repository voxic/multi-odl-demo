# Agreement Profile Service

A Java Spring Boot microservice that builds comprehensive customer profiles with a focus on agreements. This service consumes Kafka events from MongoDB change streams and produces enriched customer agreement profiles to another Kafka topic.

## Architecture

```
MongoDB Cluster 1 (agreements collection)
  ↓ (MongoDB Source Connector)
Kafka Topic: customer-agreement-events
  ↓ (Agreement Profile Service)
Kafka Topic: customer-agreement-profiles
  ↓ (MongoDB Sink Connector)
MongoDB Cluster 2 (customer_agreement_profiles collection)
```

## Features

- **Event-Driven**: Consumes Kafka events triggered by MongoDB change streams
- **Agreement-Focused**: Builds complete customer profiles with all agreement information
- **Real-Time Processing**: Processes events as they occur in MongoDB
- **Comprehensive Profiles**: Includes customer info, all agreements, and summary metrics

## Building

### Prerequisites
- Java 17+
- Maven 3.6+
- Docker (for containerization)

### Build Docker Image
```bash
./scripts/build-agreement-profile-service.sh
```

Or manually:
```bash
cd microservices/agreement-profile-service
docker build -t agreement-profile-service:latest .
```

## Configuration

The service uses environment variables for configuration:

- `CLUSTER1_URI`: MongoDB Cluster 1 connection string (for reading customer and agreement data)
- `KAFKA_BOOTSTRAP_SERVERS`: Kafka bootstrap servers (default: `kafka-service:9092`)
- `SPRING_PROFILES_ACTIVE`: Spring profile (default: `production`)

Kafka topics are configured in `application.properties`:
- Input topic: `customer-agreement-events`
- Output topic: `customer-agreement-profiles`

## Deployment

### Kubernetes Deployment

Standard deployment:
```bash
kubectl apply -f k8s/microservices/agreement-profile-service-deployment.yaml
```

Docker-based deployment (host networking):
```bash
kubectl apply -f k8s/microservices/agreement-profile-service-deployment-docker.yaml
```

### Prerequisites

1. **MongoDB Source Connector** must be deployed to publish events to `customer-agreement-events` topic
2. **MongoDB Sink Connector** must be deployed to consume from `customer-agreement-profiles` topic
3. **Kafka** must be running and accessible
4. **MongoDB Secrets** must be configured in Kubernetes

## API Endpoints

- `GET /actuator/health` - Health check endpoint
- `GET /api/health` - Service health status
- `GET /api/profile/{customerId}` - Get agreement profile for a customer (manual trigger)

## Data Model

### Input Event (from Kafka)
```json
{
  "operationType": "insert",
  "fullDocument": {
    "customer_id": 12345,
    "agreement_id": 67890,
    "agreement_type": "LOAN",
    ...
  }
}
```

### Output Profile (to Kafka)
```json
{
  "customerId": 12345,
  "customerInfo": {
    "firstName": "John",
    "lastName": "Doe",
    "email": "john.doe@email.com",
    ...
  },
  "agreements": [
    {
      "agreementId": 67890,
      "agreementType": "LOAN",
      "principalAmount": 50000.00,
      "currentBalance": 35000.00,
      ...
    }
  ],
  "agreementSummary": {
    "totalAgreements": 3,
    "activeAgreements": 2,
    "totalPrincipalAmount": 150000.00,
    "totalCurrentBalance": 120000.00,
    ...
  },
  "computedAt": "2024-01-15T17:00:00Z"
}
```

## Troubleshooting

### Service not consuming messages
- Check Kafka connectivity: `KAFKA_BOOTSTRAP_SERVERS` environment variable
- Verify MongoDB source connector is running and publishing to `customer-agreement-events`
- Check service logs: `kubectl logs -f deployment/agreement-profile-service`

### Service not producing messages
- Verify Kafka producer configuration
- Check output topic exists: `customer-agreement-profiles`
- Review service logs for errors

### MongoDB connection issues
- Verify `CLUSTER1_URI` is correctly set in Kubernetes secrets
- Check MongoDB network access and credentials
- Ensure MongoDB user has read permissions on `banking` database

