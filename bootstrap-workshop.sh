#!/usr/bin/env bash

# Load configure env variables
source ./env
source ./functions.sh

# Create resource group
pe "az group create -g $RESOURCE_GROUP -l $LOCATION"
pe "az acr create \
    -n $MYACR \
    -g $RESOURCE_GROUP \
    --sku Basic"

# Networking resources
pe "az network vnet create \
    --resource-group $RESOURCE_GROUP \
    --name $VIRTUAL_NETWORK_NAME \
    --location $LOCATION \
    --address-prefix 10.1.0.0/16"

pe "az network vnet subnet create \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VIRTUAL_NETWORK_NAME \
    --address-prefixes $AKS1_SUBNET_CIDR \
    --name aks1-subnet"

pe "az network vnet subnet create \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VIRTUAL_NETWORK_NAME \
    --address-prefixes $AKS2_SUBNET_CIDR \
    --name aks2-subnet"

# Cluster 1 creation
pe "SUBNET_ID1=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name $VIRTUAL_NETWORK_NAME --name aks1-subnet --query id -o tsv)"

pe "az aks create -n $AKSCLUSTER1 \
    -g $RESOURCE_GROUP \
    --node-count $NODE_COUNT \
    --location $LOCATION \
    --generate-ssh-keys \
    --attach-acr $MYACR \
    --vnet-subnet-id $SUBNET_ID1"

# Cluster 2 creation
pe "SUBNET_ID2=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name $VIRTUAL_NETWORK_NAME --name aks2-subnet --query id -o tsv)"

pe "az aks create -n $AKSCLUSTER2 \
    -g $RESOURCE_GROUP \
    --node-count $NODE_COUNT \
    --location $LOCATION \
    --generate-ssh-keys \
    --attach-acr $MYACR \
    --vnet-subnet-id $SUBNET_ID2"

