#!/bin/bash
# Build and push microservices container images

set -e

# Configuration
REGISTRY="sreproject01"
VERSION="v1.1"

# Output formatting removed for compatibility

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "ERROR: Azure CLI not found"
    echo "Please install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if user is logged in to Azure
echo "Checking Azure login status..."
if ! az account show &> /dev/null; then
    echo "ERROR: Not logged in to Azure"
    echo "Please run: az login"
    exit 1
fi

echo "Azure CLI authenticated"
echo ""

echo "Building and pushing microservices images"
echo "Registry: $REGISTRY"
echo "Version: $VERSION"
echo ""

# Login to ACR
echo "Logging in to Azure Container Registry..."
ACR_NAME=$(echo $REGISTRY | cut -d'.' -f1)

# Try to login using Azure CLI (recommended)
if command -v az &> /dev/null; then
    echo "Using Azure CLI to login to ACR..."
    az acr login --name $ACR_NAME
    
    if [ $? -eq 0 ]; then
        echo "Successfully logged in to ACR"
    else
        echo "Failed to login to ACR"
        echo "Please run: az login"
        exit 1
    fi
else
    echo "Azure CLI not found"
    echo "Please install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

echo ""

# Detect platform
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
    echo "Detected ARM64 architecture (Apple Silicon)"
    echo "Building for linux/amd64 platform for AKS compatibility..."
    PLATFORM="--platform linux/amd64"
else
    echo "Detected AMD64 architecture"
    PLATFORM=""
fi
echo ""

# Function to build and push an image
build_and_push() {
    local service=$1
    local image_name="${REGISTRY}.azurecr.io/${service}:${VERSION}"
    
    echo "Building ${service}..."
    cd "$service"
    
    # Build with platform specification for cross-platform compatibility
    docker build $PLATFORM -t "$image_name" .
    
    if [ $? -eq 0 ]; then
        echo "Built ${service}"
        
        echo "Pushing ${service}..."
        docker push "$image_name"
        
        if [ $? -eq 0 ]; then
            echo "Pushed ${service}"
        else
            echo "Failed to push ${service}"
            return 1
        fi
    else
        echo "Failed to build ${service}"
        return 1
    fi
    
    cd ..
    echo ""
}

# Build and push all services
build_and_push "frontend-api"
build_and_push "business-logic"
build_and_push "data-ingest"

echo "All microservices built and pushed successfully!"
echo ""
echo "Update your Kubernetes manifests with:"
echo "  image: ${REGISTRY}.azurecr.io/frontend-api:${VERSION}"
echo "  image: ${REGISTRY}.azurecr.io/business-logic:${VERSION}"
echo "  image: ${REGISTRY}.azurecr.io/data-ingest:${VERSION}"
