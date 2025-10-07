#!/bin/bash

# MongoDB Atlas Configuration Script for ODL Demo
# This script helps configure MongoDB Atlas connection strings for the ODL demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration files
CONFIG_DIR="config"
TEMPLATE_FILE="$CONFIG_DIR/mongodb-config.env"
LOCAL_CONFIG_FILE="$CONFIG_DIR/mongodb-config.local.env"

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if config directory exists
if [ ! -d "$CONFIG_DIR" ]; then
    mkdir -p "$CONFIG_DIR"
fi

# Check if template exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    print_error "Template file $TEMPLATE_FILE not found!"
    exit 1
fi

print_status "MongoDB Atlas Configuration Setup"
echo "========================================"
echo ""
echo "This script will help you configure MongoDB Atlas connection strings for the ODL demo."
echo "You'll need the following information:"
echo ""
echo "1. Cluster 1 (Primary ODL) - Banking Data:"
echo "   - Host: e.g., cluster1.mongodb.net"
echo "   - Database: banking"
echo "   - Username: odl-reader"
echo "   - Password: (your odl-reader password)"
echo ""
echo "2. Cluster 2 (Analytics) - Analytics Data:"
echo "   - Host: e.g., cluster2.mongodb.net"
echo "   - Database: analytics"
echo "   - Username: odl-writer"
echo "   - Password: (your odl-writer password)"
echo ""

# Check if local config already exists
if [ -f "$LOCAL_CONFIG_FILE" ]; then
    print_warning "Local configuration file already exists: $LOCAL_CONFIG_FILE"
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Configuration cancelled."
        exit 0
    fi
fi

# Copy template to local config
cp "$TEMPLATE_FILE" "$LOCAL_CONFIG_FILE"

print_status "Please provide your MongoDB Atlas configuration:"
echo ""

# Cluster 1 configuration
echo "=== Cluster 1 (Primary ODL) Configuration ==="
read -p "Cluster 1 Host (e.g., cluster1.mongodb.net): " cluster1_host
read -p "Cluster 1 Database [banking]: " cluster1_db
read -p "Cluster 1 Username [odl-reader]: " cluster1_user
read -s -p "Cluster 1 Password: " cluster1_pass
echo ""

# Use defaults if empty
cluster1_db=${cluster1_db:-banking}
cluster1_user=${cluster1_user:-odl-reader}

# Cluster 2 configuration
echo ""
echo "=== Cluster 2 (Analytics) Configuration ==="
read -p "Cluster 2 Host (e.g., cluster2.mongodb.net): " cluster2_host
read -p "Cluster 2 Database [analytics]: " cluster2_db
read -p "Cluster 2 Username [odl-writer]: " cluster2_user
read -s -p "Cluster 2 Password: " cluster2_pass
echo ""

# Use defaults if empty
cluster2_db=${cluster2_db:-analytics}
cluster2_user=${cluster2_user:-odl-writer}

# Update the local config file
print_status "Updating configuration file..."

# Use sed to replace values in the local config file
sed -i.bak "s/MONGO_CLUSTER1_HOST=.*/MONGO_CLUSTER1_HOST=$cluster1_host/" "$LOCAL_CONFIG_FILE"
sed -i.bak "s/MONGO_CLUSTER1_DATABASE=.*/MONGO_CLUSTER1_DATABASE=$cluster1_db/" "$LOCAL_CONFIG_FILE"
sed -i.bak "s/MONGO_CLUSTER1_USERNAME=.*/MONGO_CLUSTER1_USERNAME=$cluster1_user/" "$LOCAL_CONFIG_FILE"
sed -i.bak "s/MONGO_CLUSTER1_PASSWORD=.*/MONGO_CLUSTER1_PASSWORD=$cluster1_pass/" "$LOCAL_CONFIG_FILE"

sed -i.bak "s/MONGO_CLUSTER2_HOST=.*/MONGO_CLUSTER2_HOST=$cluster2_host/" "$LOCAL_CONFIG_FILE"
sed -i.bak "s/MONGO_CLUSTER2_DATABASE=.*/MONGO_CLUSTER2_DATABASE=$cluster2_db/" "$LOCAL_CONFIG_FILE"
sed -i.bak "s/MONGO_CLUSTER2_USERNAME=.*/MONGO_CLUSTER2_USERNAME=$cluster2_user/" "$LOCAL_CONFIG_FILE"
sed -i.bak "s/MONGO_CLUSTER2_PASSWORD=.*/MONGO_CLUSTER2_PASSWORD=$cluster2_pass/" "$LOCAL_CONFIG_FILE"

# Remove backup file
rm -f "$LOCAL_CONFIG_FILE.bak"

# Generate connection strings
cluster1_uri="mongodb+srv://$cluster1_user:$cluster1_pass@$cluster1_host/$cluster1_db?retryWrites=true&w=majority"
cluster2_uri="mongodb+srv://$cluster2_user:$cluster2_pass@$cluster2_host/$cluster2_db?retryWrites=true&w=majority"

# Update connection strings in the file
sed -i.bak "s|MONGO_CLUSTER1_URI=.*|MONGO_CLUSTER1_URI=$cluster1_uri|" "$LOCAL_CONFIG_FILE"
sed -i.bak "s|MONGO_CLUSTER2_URI=.*|MONGO_CLUSTER2_URI=$cluster2_uri|" "$LOCAL_CONFIG_FILE"
sed -i.bak "s|MONGO_PASSWORD=.*|MONGO_PASSWORD=$cluster2_pass|" "$LOCAL_CONFIG_FILE"

# Remove backup file
rm -f "$LOCAL_CONFIG_FILE.bak"

print_success "Configuration saved to $LOCAL_CONFIG_FILE"
echo ""
print_status "Configuration Summary:"
echo "Cluster 1 URI: $cluster1_uri"
echo "Cluster 2 URI: $cluster2_uri"
echo ""
print_status "Next steps:"
echo "1. Run './scripts/deploy-hostnetwork.sh' to deploy with your configuration"
echo "2. Or run './scripts/deploy.sh' for standard Kubernetes deployment"
echo ""
print_warning "Important: Keep your $LOCAL_CONFIG_FILE file secure and never commit it to version control!"
