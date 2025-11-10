#!/bin/bash

# Build script for Agreement Profile Service (Java Spring Boot)
# This script builds the Docker image for the agreement-profile-service

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVICE_DIR="$PROJECT_ROOT/microservices/agreement-profile-service"

echo "Building Agreement Profile Service (Java Spring Boot)..."

cd "$SERVICE_DIR"

# Build the Maven project and create Docker image
echo "Building Maven project..."
docker build -t agreement-profile-service:latest .

echo "✅ Agreement Profile Service built successfully!"
echo "Docker image: agreement-profile-service:latest"

