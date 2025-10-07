# Microservices Deployment - Docker Images vs ConfigMaps

## Problem with ConfigMaps

The original deployment approach used ConfigMaps to store source code, which has several issues:

- **Not a best practice**: ConfigMaps are meant for configuration, not source code
- **Performance**: Source code is copied at runtime, increasing startup time
- **Maintenance**: Hard to version and manage code changes
- **Security**: Source code is visible in Kubernetes resources
- **Size limits**: ConfigMaps have size limitations (1MB per key)

## New Docker-Based Approach

### Benefits

✅ **Proper containerization**: Each microservice is built as a proper Docker image  
✅ **Version control**: Images can be tagged and versioned  
✅ **Performance**: Faster startup times with pre-built images  
✅ **Security**: Source code is compiled into the image  
✅ **Best practices**: Follows Kubernetes and Docker best practices  
✅ **Scalability**: Images can be pushed to registries for multi-node clusters  

### Architecture

```
Source Code → Docker Build → Image → Kubernetes Deployment
```

Instead of:
```
Source Code → ConfigMap → Runtime Copy → Kubernetes Deployment
```

## Migration Guide

### 1. Clean Up Old Deployments

```bash
./scripts/cleanup-old-deployments.sh
```

### 2. Build and Deploy with Docker

```bash
# Complete deployment (recommended)
./scripts/deploy-complete.sh

# Or step by step
./scripts/build-microservices.sh
./scripts/deploy-microservices.sh
```

### 3. Verify Deployment

```bash
kubectl get pods -n odl-demo
kubectl get services -n odl-demo
```

## File Structure

### New Files

- `scripts/build-microservices.sh` - Builds all Docker images
- `scripts/deploy-microservices.sh` - Deploys microservices using Docker images
- `scripts/deploy-complete.sh` - Complete deployment with infrastructure
- `scripts/cleanup-old-deployments.sh` - Removes old ConfigMap-based deployments

### New Kubernetes Deployments

- `k8s/microservices/aggregation-service-deployment-docker.yaml`
- `k8s/microservices/customer-profile-service-deployment-docker.yaml`
- `k8s/microservices/analytics-ui-deployment-docker.yaml`
- `k8s/microservices/legacy-ui-deployment-docker.yaml`

### Existing Dockerfiles

- `microservices/aggregation-service/Dockerfile`
- `microservices/customer-profile-service/Dockerfile`
- `microservices/analytics-ui/Dockerfile`
- `microservices/legacy-ui/Dockerfile`

## Remote Deployment Options

### Option 1: Docker Required (Recommended)
**Requirements**: Docker installed on remote machine
```bash
# On remote machine
./scripts/deploy-hostnetwork.sh
```

### Option 2: Hybrid Deployment
**Requirements**: Docker on local machine, SSH access to remote
```bash
# From local machine
./scripts/deploy-hybrid.sh <remote-host> [remote-user]
```

### Option 3: No Docker Required (Fallback)
**Requirements**: Only MicroK8s on remote machine
```bash
# From local machine
./scripts/deploy-remote-configmap.sh <remote-host> [remote-user]
```

## Docker Installation Requirements

### For Remote Machine (Option 1)
```bash
# Install Docker on Ubuntu 24.04
sudo apt update
sudo apt install -y docker.io
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER
newgrp docker

# Verify installation
docker --version
docker run hello-world
```

### For Local Machine (Option 2)
- Docker Desktop or Docker Engine
- SSH key access to remote machine
- Project files on local machine

### Adding New Microservices

1. **Create Dockerfile** in `microservices/new-service/`
2. **Add to build script** in `scripts/build-microservices.sh`
3. **Create deployment YAML** in `k8s/microservices/`
4. **Add to deploy script** in `scripts/deploy-microservices.sh`

## Production Considerations

### Image Registry

For production, push images to a registry:

```bash
# Tag images for registry
docker tag aggregation-service:latest your-registry/aggregation-service:v1.0.0

# Push to registry
docker push your-registry/aggregation-service:v1.0.0

# Update deployment to use registry image
# Change imagePullPolicy from "Never" to "Always"
# Update image name to include registry URL
```

### Multi-Node Clusters

For multi-node clusters:

1. **Push images to registry**
2. **Update imagePullPolicy** to "Always"
3. **Update image names** to include registry URL
4. **Remove imagePullPolicy: Never** from deployments

### Security

- Use **non-root users** in Dockerfiles (already implemented)
- **Scan images** for vulnerabilities
- Use **specific image tags** instead of "latest"
- **Sign images** for integrity verification

## Troubleshooting

### Common Issues

1. **Images not found**: Ensure images are built and loaded into cluster
2. **Pull errors**: Check imagePullPolicy and registry access
3. **Startup failures**: Check logs with `kubectl logs deployment/service-name`

### Debugging

```bash
# Check pod status
kubectl get pods -n odl-demo

# Check pod logs
kubectl logs -f deployment/aggregation-service -n odl-demo

# Check image details
kubectl describe pod -l app=aggregation-service -n odl-demo

# Check Docker images locally
docker images | grep -E "(aggregation|customer|analytics|legacy)"
```

## Troubleshooting

### Common Issues

#### Docker Build Issues
- [ ] **Error**: `npm ci command can only install with an existing package-lock.json`
- [ ] **Solution**: Dockerfiles now use `npm install --omit=dev` instead of `npm ci`
- [ ] **For Better Performance**: Generate package-lock.json files first:
  ```bash
  ./scripts/generate-package-locks.sh
  ./scripts/build-microservices.sh --with-locks
  ```
- [ ] **Error**: `Docker is not running locally`
- [ ] **Solution**: Start Docker service: `sudo systemctl start docker`

#### Performance Comparison

| Aspect | ConfigMap Approach | Docker Approach |
|--------|-------------------|-----------------|
| Startup Time | ~30-60s | ~10-20s |
| Image Size | N/A | ~200-500MB |
| Memory Usage | Higher (runtime copy) | Lower (pre-built) |
| Versioning | Difficult | Easy (tags) |
| Security | Source visible | Source compiled |
| Best Practices | ❌ | ✅ |
