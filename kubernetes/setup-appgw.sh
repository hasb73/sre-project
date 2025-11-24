#!/bin/bash
# Setup Azure Application Gateway Ingress Controller (AGIC) for JupyterHub
# Following: https://learn.microsoft.com/en-us/azure/application-gateway/tutorial-ingress-controller-add-on-existing

set -e

# Output formatting removed for compatibility

echo "=== Azure Application Gateway Ingress Controller Setup ==="
echo ""

# Configuration
PRIMARY_RG="azure-maen-primary-rg"
DR_RG="azure-meun-dr-rg"
PRIMARY_LOCATION="uaenorth"
DR_LOCATION="northeurope"
PRIMARY_VNET="primary-vnet"
DR_VNET="dr-vnet"
PRIMARY_APPGW="primary-appgw"
DR_APPGW="dr-appgw"
PRIMARY_CLUSTER="primary-aks-cluster"
DR_CLUSTER="dr-aks-cluster"

# Step 1: Create subnet for Application Gateway in Primary
echo "Step 1: Creating Application Gateway subnet in Primary VNet"

# Check if subnet exists
PRIMARY_APPGW_SUBNET=$(az network vnet subnet show \
  --resource-group $PRIMARY_RG \
  --vnet-name $PRIMARY_VNET \
  --name appgw-subnet \
  --query id -o tsv 2>/dev/null || echo "")

if [ -z "$PRIMARY_APPGW_SUBNET" ]; then
    echo "Creating appgw-subnet in Primary VNet..."
    az network vnet subnet create \
      --resource-group $PRIMARY_RG \
      --vnet-name $PRIMARY_VNET \
      --name appgw-subnet \
      --address-prefixes 10.1.18.0/24
    
    echo "Primary Application Gateway subnet created"
else
    echo "Primary Application Gateway subnet already exists"
fi
echo ""

# Step 2: Create Public IP for Primary Application Gateway
echo "Step 2: Creating Public IP for Primary Application Gateway"

PRIMARY_PIP=$(az network public-ip show \
  --resource-group $PRIMARY_RG \
  --name ${PRIMARY_APPGW}-pip \
  --query id -o tsv 2>/dev/null || echo "")

if [ -z "$PRIMARY_PIP" ]; then
    echo "Creating public IP for Primary Application Gateway..."
    az network public-ip create \
      --resource-group $PRIMARY_RG \
      --name ${PRIMARY_APPGW}-pip \
      --location $PRIMARY_LOCATION \
      --sku Standard \
      --allocation-method Static \
      --dns-name sreproject-primary
    
    echo "Primary Application Gateway public IP created"
else
    echo "Primary Application Gateway public IP already exists"
fi

PRIMARY_PIP_ADDRESS=$(az network public-ip show \
  --resource-group $PRIMARY_RG \
  --name ${PRIMARY_APPGW}-pip \
  --query ipAddress -o tsv)

echo "Primary Public IP: $PRIMARY_PIP_ADDRESS"
echo ""

# Step 3: Create Primary Application Gateway
echo "Step 3: Creating Primary Application Gateway"

PRIMARY_APPGW_EXISTS=$(az network application-gateway show \
  --resource-group $PRIMARY_RG \
  --name $PRIMARY_APPGW \
  --query id -o tsv 2>/dev/null || echo "")

if [ -z "$PRIMARY_APPGW_EXISTS" ]; then
    echo "Creating Primary Application Gateway (this may take 10-15 minutes)..."
    
    # Get AKS node resource group to find the load balancer
    AKS_NODE_RG=$(az aks show \
      --resource-group $PRIMARY_RG \
      --name $PRIMARY_CLUSTER \
      --query nodeResourceGroup -o tsv)
    
    # Create Application Gateway
    az network application-gateway create \
      --resource-group $PRIMARY_RG \
      --name $PRIMARY_APPGW \
      --location $PRIMARY_LOCATION \
      --sku Standard_v2 \
      --capacity 2 \
      --vnet-name $PRIMARY_VNET \
      --subnet appgw-subnet \
      --public-ip-address ${PRIMARY_APPGW}-pip \
      --http-settings-cookie-based-affinity Enabled \
      --http-settings-port 80 \
      --http-settings-protocol Http \
      --frontend-port 80 \
      --priority 100
    
    echo "Primary Application Gateway created"
else
    echo "Primary Application Gateway already exists"
fi
echo ""

# Step 4: Create subnet for Application Gateway in DR
echo "Step 4: Creating Application Gateway subnet in DR VNet"

DR_APPGW_SUBNET=$(az network vnet subnet show \
  --resource-group $DR_RG \
  --vnet-name $DR_VNET \
  --name appgw-subnet \
  --query id -o tsv 2>/dev/null || echo "")

if [ -z "$DR_APPGW_SUBNET" ]; then
    echo "Creating appgw-subnet in DR VNet..."
    az network vnet subnet create \
      --resource-group $DR_RG \
      --vnet-name $DR_VNET \
      --name appgw-subnet \
      --address-prefixes 10.2.18.0/24
    
    echo "DR Application Gateway subnet created"
else
    echo "DR Application Gateway subnet already exists"
fi
echo ""

# Step 5: Create Public IP for DR Application Gateway
echo "Step 5: Creating Public IP for DR Application Gateway"

DR_PIP=$(az network public-ip show \
  --resource-group $DR_RG \
  --name ${DR_APPGW}-pip \
  --query id -o tsv 2>/dev/null || echo "")

if [ -z "$DR_PIP" ]; then
    echo "Creating public IP for DR Application Gateway..."
    az network public-ip create \
      --resource-group $DR_RG \
      --name ${DR_APPGW}-pip \
      --location $DR_LOCATION \
      --sku Standard \
      --allocation-method Static \
      --dns-name sreproject-dr
    
    echo "DR Application Gateway public IP created"
else
    echo "DR Application Gateway public IP already exists"
fi

DR_PIP_ADDRESS=$(az network public-ip show \
  --resource-group $DR_RG \
  --name ${DR_APPGW}-pip \
  --query ipAddress -o tsv)

echo "DR Public IP: $DR_PIP_ADDRESS"
echo ""

# Step 6: Create DR Application Gateway
echo "Step 6: Creating DR Application Gateway"

DR_APPGW_EXISTS=$(az network application-gateway show \
  --resource-group $DR_RG \
  --name $DR_APPGW \
  --query id -o tsv 2>/dev/null || echo "")

if [ -z "$DR_APPGW_EXISTS" ]; then
    echo "Creating DR Application Gateway (this may take 10-15 minutes)..."
    
    az network application-gateway create \
      --resource-group $DR_RG \
      --name $DR_APPGW \
      --location $DR_LOCATION \
      --sku Standard_v2 \
      --capacity 2 \
      --vnet-name $DR_VNET \
      --subnet appgw-subnet \
      --public-ip-address ${DR_APPGW}-pip \
      --http-settings-cookie-based-affinity Enabled \
      --http-settings-port 80 \
      --http-settings-protocol Http \
      --frontend-port 80 \
      --priority 100
    
    echo "DR Application Gateway created"
else
    echo "DR Application Gateway already exists"
fi
echo ""

# Step 7: Enable AGIC add-on for Primary cluster
echo "Step 7: Enabling AGIC add-on for Primary cluster"

PRIMARY_APPGW_ID=$(az network application-gateway show \
  --resource-group $PRIMARY_RG \
  --name $PRIMARY_APPGW \
  --query id -o tsv)

echo "Enabling AGIC add-on for Primary AKS cluster..."
az aks enable-addons \
  --resource-group $PRIMARY_RG \
  --name $PRIMARY_CLUSTER \
  --addons ingress-appgw \
  --appgw-id $PRIMARY_APPGW_ID

echo "AGIC add-on enabled for Primary cluster"
echo ""

# Step 8: Enable AGIC add-on for DR cluster
echo "Step 8: Enabling AGIC add-on for DR cluster"

DR_APPGW_ID=$(az network application-gateway show \
  --resource-group $DR_RG \
  --name $DR_APPGW \
  --query id -o tsv)

echo "Enabling AGIC add-on for DR AKS cluster..."
az aks enable-addons \
  --resource-group $DR_RG \
  --name $DR_CLUSTER \
  --addons ingress-appgw \
  --appgw-id $DR_APPGW_ID

echo "AGIC add-on enabled for DR cluster"
echo ""

# Step 9: Peer VNets if needed (for cross-region communication)
echo "Step 9: Checking VNet peering"

PRIMARY_VNET_ID=$(az network vnet show \
  --resource-group $PRIMARY_RG \
  --name $PRIMARY_VNET \
  --query id -o tsv)

DR_VNET_ID=$(az network vnet show \
  --resource-group $DR_RG \
  --name $DR_VNET \
  --query id -o tsv)

# Check if peering exists
PEERING_EXISTS=$(az network vnet peering show \
  --resource-group $PRIMARY_RG \
  --vnet-name $PRIMARY_VNET \
  --name primary-to-dr \
  --query id -o tsv 2>/dev/null || echo "")

if [ -z "$PEERING_EXISTS" ]; then
    echo "Creating VNet peering (optional for cross-region scenarios)..."
    echo "Skipping - not required for basic setup"
else
    echo "VNet peering already configured"
fi
echo ""

# Summary
echo "=== Setup Complete ==="
echo ""
echo "Primary Application Gateway:"
echo "  Name: $PRIMARY_APPGW"
echo "  Public IP: $PRIMARY_PIP_ADDRESS"
echo "  DNS: jupyterhub-primary.${PRIMARY_LOCATION}.cloudapp.azure.com"
echo "  Location: $PRIMARY_LOCATION"
echo "  AGIC: Enabled"
echo ""
echo "DR Application Gateway:"
echo "  Name: $DR_APPGW"
echo "  Public IP: $DR_PIP_ADDRESS"
echo "  DNS: jupyterhub-dr.${DR_LOCATION}.cloudapp.azure.com"
echo "  Location: $DR_LOCATION"
echo "  AGIC: Enabled"
echo ""
echo "Next Steps:"
echo "  1. Verify AGIC pods are running:"
echo "     kubectl get pods -n kube-system | grep ingress-appgw"
echo ""
echo "  2. Create Ingress resource for JupyterHub:"
echo "     kubectl apply -f kubernetes/application-gateway/jupyterhub-ingress.yaml"
echo ""
echo "  3. Check Ingress status:"
echo "     kubectl get ingress -n jupyterhub"
echo ""
echo "  4. Access JupyterHub:"
echo "     http://$PRIMARY_PIP_ADDRESS"
echo "     http://$DR_PIP_ADDRESS"
