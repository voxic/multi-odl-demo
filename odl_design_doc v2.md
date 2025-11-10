# Operational Data Layer (ODL) with MongoDB Atlas - Design Document

## Executive Summary

This document outlines the design for a demo Operational Data Layer using MongoDB Atlas as the target data platform. The architecture demonstrates real-time data synchronization from a MySQL operational system through Kafka-based CDC to multiple MongoDB Atlas clusters, showcasing data transformation and tiered storage patterns.

## Architecture Overview

### High-Level Flow
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

## Data Model Design

### Source MySQL Schema

#### Customers Table
```sql
CREATE TABLE customers (
    customer_id INT PRIMARY KEY AUTO_INCREMENT,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20),
    date_of_birth DATE,
    address_line1 VARCHAR(255),
    address_line2 VARCHAR(255),
    city VARCHAR(100),
    state VARCHAR(50),
    postal_code VARCHAR(20),
    country VARCHAR(50),
    customer_status ENUM('ACTIVE', 'INACTIVE', 'SUSPENDED'),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
```

#### Accounts Table
```sql
CREATE TABLE accounts (
    account_id INT PRIMARY KEY AUTO_INCREMENT,
    customer_id INT NOT NULL,
    account_number VARCHAR(20) UNIQUE NOT NULL,
    account_type ENUM('CHECKING', 'SAVINGS', 'CREDIT', 'LOAN'),
    balance DECIMAL(15,2) DEFAULT 0.00,
    currency VARCHAR(3) DEFAULT 'USD',
    account_status ENUM('ACTIVE', 'CLOSED', 'FROZEN'),
    interest_rate DECIMAL(5,4),
    credit_limit DECIMAL(15,2),
    opened_date DATE NOT NULL,
    closed_date DATE NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);
```

#### Transactions Table
```sql
CREATE TABLE transactions (
    transaction_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    account_id INT NOT NULL,
    transaction_type ENUM('DEPOSIT', 'WITHDRAWAL', 'TRANSFER_IN', 'TRANSFER_OUT', 'PAYMENT', 'FEE'),
    amount DECIMAL(15,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    description VARCHAR(500),
    reference_number VARCHAR(50),
    counterparty_account VARCHAR(20),
    transaction_date DATETIME NOT NULL,
    posted_date DATETIME,
    status ENUM('PENDING', 'COMPLETED', 'FAILED', 'REVERSED'),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (account_id) REFERENCES accounts(account_id),
    INDEX idx_account_date (account_id, transaction_date),
    INDEX idx_transaction_date (transaction_date),
    INDEX idx_status (status)
);
```

#### Agreements Table
```sql
CREATE TABLE agreements (
    agreement_id INT PRIMARY KEY AUTO_INCREMENT,
    customer_id INT NOT NULL,
    account_id INT,
    agreement_type ENUM('LOAN', 'CREDIT_CARD', 'OVERDRAFT', 'INVESTMENT'),
    agreement_number VARCHAR(50) UNIQUE NOT NULL,
    principal_amount DECIMAL(15,2),
    current_balance DECIMAL(15,2),
    interest_rate DECIMAL(5,4),
    term_months INT,
    payment_amount DECIMAL(15,2),
    payment_frequency ENUM('MONTHLY', 'QUARTERLY', 'ANNUALLY'),
    start_date DATE NOT NULL,
    end_date DATE,
    status ENUM('ACTIVE', 'COMPLETED', 'DEFAULT', 'CANCELLED'),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    FOREIGN KEY (account_id) REFERENCES accounts(account_id)
);
```

### MongoDB Atlas Cluster 1 Schema (Primary ODL)

#### Customers Collection
```javascript
{
  "_id": ObjectId("..."),
  "customer_id": 12345,
  "personal_info": {
    "first_name": "John",
    "last_name": "Doe",
    "email": "john.doe@email.com",
    "phone": "+1-555-0123",
    "date_of_birth": ISODate("1985-06-15")
  },
  "address": {
    "line1": "123 Main St",
    "line2": "Apt 4B",
    "city": "New York",
    "state": "NY",
    "postal_code": "10001",
    "country": "USA"
  },
  "status": "ACTIVE",
  "metadata": {
    "created_at": ISODate("2024-01-15T10:30:00Z"),
    "updated_at": ISODate("2024-01-15T10:30:00Z"),
    "source_updated_at": ISODate("2024-01-15T10:30:00Z"),
    "sync_timestamp": ISODate("2024-01-15T10:30:05Z")
  }
}
```

#### Accounts Collection
```javascript
{
  "_id": ObjectId("..."),
  "account_id": 67890,
  "customer_id": 12345,
  "account_details": {
    "account_number": "ACC-2024-001234",
    "account_type": "CHECKING",
    "currency": "USD",
    "status": "ACTIVE"
  },
  "financial_info": {
    "balance": 2500.75,
    "interest_rate": 0.0125,
    "credit_limit": null
  },
  "dates": {
    "opened_date": ISODate("2024-01-01"),
    "closed_date": null
  },
  "metadata": {
    "created_at": ISODate("2024-01-01T09:00:00Z"),
    "updated_at": ISODate("2024-01-15T14:22:00Z"),
    "source_updated_at": ISODate("2024-01-15T14:22:00Z"),
    "sync_timestamp": ISODate("2024-01-15T14:22:03Z")
  }
}
```

### MongoDB Atlas Cluster 2 Schema (Analytics Subset)

#### Customer Analytics Collection
```javascript
{
  "_id": ObjectId("..."),
  "customer_id": 12345,
  "profile": {
    "name": "John Doe",
    "email": "john.doe@email.com",
    "location": "New York, NY",
    "status": "ACTIVE"
  },
  "financial_summary": {
    "total_accounts": 3,
    "total_balance": 15750.25,
    "account_types": ["CHECKING", "SAVINGS", "CREDIT"],
    "avg_monthly_transactions": 45,
    "last_transaction_date": ISODate("2024-01-15T16:30:00Z")
  },
  "risk_profile": {
    "credit_score_band": "EXCELLENT",
    "default_risk": "LOW",
    "transaction_pattern": "REGULAR"
  },
  "computed_at": ISODate("2024-01-15T17:00:00Z")
}
```

## Technical Architecture

### Infrastructure Components

#### MicroK8s Cluster Configuration
```yaml
# Cluster specifications
- CPU: 4 cores minimum
- RAM: 8GB minimum
- Storage: 100GB SSD
- Network: Persistent IP configuration

# Add-ons to enable:
- dns
- storage
- ingress
- dashboard
- metrics-server
```

#### Kafka Configuration
```yaml
# Kafka Topics
topics:
  - mysql.inventory.customers
  - mysql.inventory.accounts  
  - mysql.inventory.transactions
  - mysql.inventory.agreements
  - customer-agreement-events (MongoDB source connector output)
  - customer-agreement-profiles (Java service output)
  - atlas-cluster1-updates
  - atlas-cluster2-analytics

# Kafka Connect Configuration
- Source: Debezium MySQL Connector
- Source: MongoDB Source Connector (Cluster 1 agreements → customer-agreement-events)
- Sink: MongoDB Atlas Kafka Connector (MySQL topics → Cluster 1)
- Sink: MongoDB Atlas Kafka Connector (customer-agreement-profiles → Cluster 2)
- Partitions: 3 per topic
- Replication Factor: 1 (demo environment)
```

### Data Flow Architecture

#### Stage 1: MySQL → Kafka (CDC)
```
MySQL Binlog → Debezium → Kafka Topics
- Real-time capture of INSERT, UPDATE, DELETE operations
- JSON format with schema evolution support
- Tombstone records for DELETE operations
```

#### Stage 2: Kafka → MongoDB Atlas Cluster 1
```
Kafka Topics → MongoDB Kafka Connector → Atlas Cluster 1
- Direct streaming to primary collections
- Upsert operations based on primary key
- Document transformation via connector configuration
```

#### Stage 3: Atlas Cluster 1 → Processing → Atlas Cluster 2
```
Atlas Cluster 1 → Change Streams → Node.js Microservices → Atlas Cluster 2
- Aggregation and transformation logic
- Business rule application
- Computed analytics fields
```

#### Stage 4: Atlas Cluster 1 → Kafka → Java Spring Service → Kafka → Atlas Cluster 2
```
Atlas Cluster 1 → MongoDB Source Connector → Kafka (customer-agreement-events)
→ Java Spring Boot Agreement Profile Service → Kafka (customer-agreement-profiles)
→ MongoDB Sink Connector → Atlas Cluster 2
- Real-time agreement-focused customer profile building
- Event-driven architecture with Kafka
- Complete agreement information aggregation
```

### Simplified Microservices Design

#### Single Aggregation Service (MVP)
```javascript
// Purpose: Basic customer data aggregation only
// Input: Customer and Account changes from Atlas Cluster 1
// Output: Simple customer profiles for Cluster 2

const aggregateCustomerData = async (customer) => {
  // Fetch customer accounts
  // Calculate total balance
  // Count accounts by type
  // Write to Cluster 2
};
```

#### Agreement Profile Service (Java Spring Boot)
```java
// Purpose: Build complete customer profiles with focus on agreements
// Input: Kafka events from customer-agreement-events topic (MongoDB source connector)
// Output: Kafka events to customer-agreement-profiles topic (MongoDB sink connector)

@Service
public class AgreementProfileService {
    public CustomerAgreementProfile buildCustomerAgreementProfile(Long customerId) {
        // Fetch customer information from Cluster 1
        // Fetch all agreements for the customer
        // Build comprehensive agreement profile with:
        //   - Customer information
        //   - All agreement details
        //   - Agreement summary (totals, active, completed, defaulted)
        //   - Financial metrics
        // Publish to Kafka output topic
    }
}
```

## Deployment Strategy

### Minimal Kubernetes Manifests Structure
```
k8s/
├── mysql/
│   ├── mysql-deployment.yaml
│   └── mysql-service.yaml
├── kafka/
│   ├── kafka-all-in-one.yaml (zookeeper + kafka + connect)
└── microservices/
    ├── aggregation-service/
    │   ├── deployment.yaml
    │   └── service.yaml
    └── agreement-profile-service/
        ├── deployment.yaml
        └── service.yaml
```

### MongoDB Atlas Configuration

#### Cluster 1 (Primary ODL)
```yaml
Configuration:
  - Cluster Tier: M10 (demo appropriate)
  - Region: Same as VM for latency
  - Backup: Enabled
  - Monitoring: Enabled
  
Security:
  - Database User: odl-writer (readWrite)
  - Database User: odl-reader (read)
  - IP Whitelist: VM public IP
  - Connection String: MongoDB+SRV format

Indexes:
  - customers: customer_id, email, status
  - accounts: customer_id, account_number, status
  - transactions: account_id + transaction_date, status
  - agreements: customer_id, agreement_number, status
```

#### Cluster 2 (Analytics)
```yaml
Configuration:
  - Cluster Tier: M5 (smaller for analytics)
  - Region: Same as Cluster 1
  - Backup: Enabled
  - Monitoring: Enabled

Collections:
  - customer_analytics (computed profiles)
  - customer_agreement_profiles (agreement-focused profiles from Java service)
  - account_metrics (aggregated data)
  - transaction_patterns (ML insights)
```

## RAPID DEPLOYMENT PLAN (1-DAY IMPLEMENTATION)

### Phase 1: Infrastructure Setup (Morning - 4 hours)
- [ ] Provision VM with MicroK8s
- [ ] Deploy MySQL with pre-built sample data
- [ ] Setup basic Kafka cluster (single node)
- [ ] Configure MongoDB Atlas clusters (automated)
- [ ] Test basic connectivity

### Phase 2: Core CDC Pipeline (Afternoon - 4 hours)  
- [ ] Deploy Debezium MySQL connector (pre-configured)
- [ ] Setup MongoDB Kafka connector
- [ ] Test basic data flow MySQL → Atlas Cluster 1
- [ ] Validate core functionality works

### Phase 3: Basic Transformation (Evening - 2 hours)
- [ ] Deploy single Node.js transformation service
- [ ] Implement basic aggregation Atlas Cluster 1 → Cluster 2
- [ ] End-to-end validation
- [ ] Demo preparation

### Phase 4: Agreement Profile Service (Additional - 2 hours)
- [ ] Deploy MongoDB source connector for agreements (Cluster 1 → Kafka)
- [ ] Build and deploy Java Spring Boot agreement profile service
- [ ] Deploy MongoDB sink connector (Kafka → Cluster 2)
- [ ] Test end-to-end Kafka-based flow
- [ ] Validate agreement profiles in Cluster 2

## Sample Data Generation

### Simplified Mock Data
```javascript
// Generate minimal viable demo data
const mockDataSpec = {
  customers: 100,        // Reduced from 10k
  accounts_per_customer: 1-2,    // Reduced complexity
  transactions_per_account: 10,   // Fixed number for demo
  agreements_percentage: 30,      // Keep agreements for demo completeness
  data_timeline: "last_month"     // Smaller dataset
};
```

## MVP Success Criteria (Demo Ready)

### Core Functionality (Must Have)
- [x] Data flows from MySQL → Atlas Cluster 1 via CDC
- [x] Basic aggregation from Atlas Cluster 1 → Atlas Cluster 2
- [x] Can demonstrate real-time sync by making changes in MySQL
- [x] Simple dashboard/query interface to show results

### Performance Requirements (Demo Level)
- [x] Handle 10+ transactions per minute (sufficient for demo)
- [x] End-to-end latency < 30 seconds (acceptable for demo)
- [x] No data loss during demo period
- [x] Services stay running during presentation

## Risk Mitigation

### Technical Risks
- **Network Connectivity**: VPN/firewall configuration for Atlas access
- **Resource Constraints**: VM sizing and K8s resource limits
- **Data Consistency**: Eventual consistency handling in transformations
- **Service Dependencies**: Circuit breaker patterns in microservices

### Operational Risks
- **Configuration Drift**: Infrastructure as Code approach
- **Security**: Credential management via K8s secrets
- **Monitoring Gaps**: Comprehensive logging and alerting setup
- **Demo Failures**: Automated health checks and rollback procedures

## IMMEDIATE NEXT STEPS (Tomorrow's Checklist)

### Pre-work (Tonight - 1 hour)
1. **Atlas Setup**: Create 2 MongoDB Atlas clusters (M0 free tier is fine)
2. **VM Preparation**: Ensure VM has MicroK8s ready
3. **Download Images**: Pre-pull Docker images to save time
   - `mysql:8.0`
   - `confluentinc/cp-kafka:latest`
   - `confluentinc/cp-zookeeper:latest`
   - `debezium/connect:latest`

### Morning Session (4 hours)
1. **MySQL Deployment** (30 min)
   - Deploy with pre-loaded sample data
   - Enable binlog for CDC
   
2. **Kafka Setup** (1.5 hours)
   - Single-node Kafka + Zookeeper
   - Kafka Connect with Debezium
   
3. **Atlas Configuration** (1 hour)
   - Network access setup
   - Database users creation
   - Connection string testing
   
4. **CDC Pipeline** (1 hour)
   - Debezium MySQL connector
   - MongoDB sink connector
   - Basic flow testing

### Afternoon Session (2 hours)
1. **Validation** (30 min)
   - Insert/Update/Delete in MySQL
   - Verify data in Atlas Cluster 1
   
2. **Microservice** (1 hour)
   - Basic Node.js aggregation service
   - Connect to both Atlas clusters
   
3. **Demo Prep** (30 min)
   - Prepare demo script
   - Test end-to-end flow

---

*This design document will be updated as implementation progresses and requirements evolve.*