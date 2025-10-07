#!/bin/bash

# Generate package-lock.json files for all microservices
# This ensures reproducible builds and enables npm ci usage

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Change to project root
cd "$PROJECT_ROOT"

print_status "Generating package-lock.json files for all microservices..."

# Check if Node.js is available
if ! command -v node &> /dev/null; then
    print_error "Node.js is not installed. Please install Node.js 18+ and try again."
    exit 1
fi

print_status "Node.js version: $(node --version)"
print_status "npm version: $(npm --version)"

# Generate package-lock.json for each microservice
microservices=("aggregation-service" "customer-profile-service" "analytics-ui" "legacy-ui")

for service in "${microservices[@]}"; do
    service_dir="microservices/$service"
    
    if [ -d "$service_dir" ] && [ -f "$service_dir/package.json" ]; then
        print_status "Generating package-lock.json for $service..."
        
        cd "$service_dir"
        
        # Remove existing package-lock.json if it exists
        if [ -f "package-lock.json" ]; then
            rm package-lock.json
            print_status "Removed existing package-lock.json"
        fi
        
        # Generate new package-lock.json
        npm install --package-lock-only
        
        if [ -f "package-lock.json" ]; then
            print_success "Generated package-lock.json for $service"
        else
            print_error "Failed to generate package-lock.json for $service"
            exit 1
        fi
        
        cd "$PROJECT_ROOT"
    else
        print_warning "Service directory not found: $service_dir"
    fi
done

print_success "All package-lock.json files generated successfully!"
print_status "You can now use 'npm ci' in Dockerfiles for faster, reproducible builds"
print_status "To update dependencies:"
print_status "  1. Edit package.json files"
print_status "  2. Run this script again: ./scripts/generate-package-locks.sh"
print_status "  3. Rebuild Docker images: ./scripts/build-microservices.sh"
