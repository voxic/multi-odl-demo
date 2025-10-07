# MongoDB Atlas Configuration - Quick Reference

This document provides a quick reference for managing MongoDB Atlas connection strings in the ODL demo.

## Overview

The ODL demo now uses a centralized configuration approach that simplifies MongoDB Atlas connection string management across all components:

- **Configuration File**: `config/mongodb-config.local.env`
- **Kubernetes Secrets**: Automatically generated from configuration
- **Components**: All microservices and connectors use the same configuration

## Quick Setup

### 1. Interactive Configuration (Recommended)
```bash
./scripts/configure-mongodb.sh
```

### 2. Deploy
```bash
# Host networking (recommended for demos)
./scripts/deploy-hostnetwork.sh

# Or standard Kubernetes
./scripts/deploy.sh
```

## Configuration File Structure

The `config/mongodb-config.local.env` file contains:

```bash
# Cluster 1 (Primary ODL) - Banking Data
MONGO_CLUSTER1_HOST=cluster1.mongodb.net
MONGO_CLUSTER1_DATABASE=banking
MONGO_CLUSTER1_USERNAME=odl-reader
MONGO_CLUSTER1_PASSWORD=your_password

# Cluster 2 (Analytics) - Analytics Data  
MONGO_CLUSTER2_HOST=cluster2.mongodb.net
MONGO_CLUSTER2_DATABASE=analytics
MONGO_CLUSTER2_USERNAME=odl-writer
MONGO_CLUSTER2_PASSWORD=your_password

# Generated connection strings (automatically created)
MONGO_CLUSTER1_URI=mongodb+srv://odl-reader:password@cluster1.mongodb.net/banking?retryWrites=true&w=majority
MONGO_CLUSTER2_URI=mongodb+srv://odl-writer:password@cluster2.mongodb.net/analytics?retryWrites=true&w=majority
MONGO_PASSWORD=your_password
```

## Components Using Configuration

### Microservices
- **Aggregation Service**: Uses `CLUSTER1_URI` and `CLUSTER2_URI` environment variables
- **Customer Profile Service**: Uses `CLUSTER1_URI` and `CLUSTER2_URI` environment variables

### Kafka Connect
- **MongoDB Atlas Connector**: Uses `MONGO_PASSWORD` environment variable for connection string

### Kubernetes Secrets
The `mongodb-secrets` secret contains:
- `cluster1-uri`: Full connection string for Cluster 1
- `cluster2-uri`: Full connection string for Cluster 2  
- `mongo-password`: Password for Kafka Connect connector

## Scripts

### `scripts/configure-mongodb.sh`
Interactive script to set up MongoDB configuration:
- Prompts for cluster details
- Creates `config/mongodb-config.local.env`
- Validates configuration

### `scripts/generate-mongodb-secrets.sh`
Generates Kubernetes secrets from configuration:
- Reads `config/mongodb-config.local.env`
- Creates `mongodb-secrets` secret in `odl-demo` namespace
- Validates secret creation

## Security Notes

- **Never commit** `config/mongodb-config.local.env` to version control
- The file is automatically ignored by `.gitignore`
- Keep your MongoDB Atlas passwords secure
- Use strong passwords for MongoDB Atlas users

## Troubleshooting

### Configuration Not Found
```bash
# Error: MongoDB configuration not found
# Solution: Run configuration script
./scripts/configure-mongodb.sh
```

### Secret Generation Failed
```bash
# Error: Failed to generate MongoDB secrets
# Solution: Check configuration file and run manually
./scripts/generate-mongodb-secrets.sh
```

### Connection Issues
1. Verify MongoDB Atlas clusters are accessible
2. Check IP whitelist in MongoDB Atlas
3. Verify user permissions
4. Check connection strings in `config/mongodb-config.local.env`

## Migration from Old Configuration

If you were previously editing connection strings manually:

1. **Remove hardcoded secrets** from deployment files (already done)
2. **Run configuration script**: `./scripts/configure-mongodb.sh`
3. **Deploy**: `./scripts/deploy-hostnetwork.sh`

The old manual approach required editing multiple files. The new approach uses a single configuration file that automatically updates all components.
