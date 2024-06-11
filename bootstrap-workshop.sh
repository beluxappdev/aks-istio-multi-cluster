#!/usr/bin/env bash
set -eE
# Load configure env variables
source ./env
source ./functions.sh

pe "az config set extension.use_dynamic_install=yes_without_prompt"

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
    --address-prefix 10.0.0.0/8"

pe "az network vnet subnet create \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VIRTUAL_NETWORK_NAME \
    --address-prefixes $AKS1_SUBNET_CIDR \
    --name aks1-subnet"

#pe "az network vnet subnet create \
#    --resource-group $RESOURCE_GROUP \
#    --vnet-name $VIRTUAL_NETWORK_NAME \
#    --address-prefixes $AKS1_POD_SUBNET_CIDR \
#    --name aks1-pod-subnet"

pe "az network vnet subnet create \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VIRTUAL_NETWORK_NAME \
    --address-prefixes $AKS2_SUBNET_CIDR \
    --name aks2-subnet"

#pe "az network vnet subnet create \
#    --resource-group $RESOURCE_GROUP \
#    --vnet-name $VIRTUAL_NETWORK_NAME \
#    --address-prefixes $AKS2_POD_SUBNET_CIDR \
#    --name aks2-pod-subnet"

# Azure Monitor workspace
pe "az resource create --resource-group $RESOURCE_GROUP \
    --namespace microsoft.monitor \
    --resource-type accounts \
    --name az-monitor-$UNIQUEID \
    --location $LOCATION \
    --properties \"{}\" "

# Managed Grafana workspace
pe "az grafana create --name grafana-$UNIQUEID \
    --resource-group $RESOURCE_GROUP"

# Log Analytics workspace
pe "az monitor log-analytics workspace create --resource-group $RESOURCE_GROUP \
    --workspace-name $LOG_ANALYICS_WORKSPACE"
pe "LAW_ID=$(az monitor log-analytics workspace show --resource-group $RESOURCE_GROUP --workspace-name $LOG_ANALYICS_WORKSPACE --query id -o tsv)"

# Cluster 1 creation
pe "SUBNET_ID1=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name $VIRTUAL_NETWORK_NAME --name aks1-subnet --query id -o tsv)"
#pe "SUBNET_POD_ID1=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name $VIRTUAL_NETWORK_NAME --name aks1-pod-subnet --query id -o tsv)"

pe "az aks create -n $AKSCLUSTER1 \
    -g $RESOURCE_GROUP \
    --max-pods 250 \
    --node-count $NODE_COUNT \
    --location $LOCATION \
    --generate-ssh-keys \
    --attach-acr $MYACR \
    --network-plugin azure \
    --network-plugin-mode overlay \
    --vnet-subnet-id $SUBNET_ID1 \
    --pod-cidr $AKS1_POD_SUBNET_CIDR \
    --enable-managed-identity \
    --enable-azure-monitor-metrics"

pe "AKS1_RESOURCE_ID=$(az aks show --resource-group $RESOURCE_GROUP --name $AKSCLUSTER1 --query id -o tsv)"

az monitor diagnostic-settings create \
    --resource $AKS1_RESOURCE_ID  \
    --name $AKSCLUSTER1-Diagnostics \
    --workspace $LAW_ID \
    --logs '[{"category": "kube-audit", "enabled": true}, {"category": "kube-apiserver", "enabled": true}, {"category": "kube-controller-manager", "enabled": true}, {"category": "kube-scheduler", "enabled": true}, {"category": "cluster-autoscaler", "enabled": true}]' \
    --metrics '[{"category": "AllMetrics", "enabled": true}]'

# Start a loop that runs if the node pool state is not Succeeded
while [ "$(az aks nodepool show --resource-group $RESOURCE_GROUP --cluster-name $AKSCLUSTER1 --name nodepool1 --query provisioningState -o tsv)" != "Succeeded" ]
do
  # Print a message to wait or retry later
  echo "Waiting for all node pool operations to complete."
  pe "sleep 20"
done

pe "az aks enable-addons -a monitoring -n $AKSCLUSTER1 \
    -g $RESOURCE_GROUP \
    --workspace-resource-id $LAW_ID"

# Cluster 2 creation
pe "SUBNET_ID2=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name $VIRTUAL_NETWORK_NAME --name aks2-subnet --query id -o tsv)"
#pe "SUBNET_POD_ID2=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name $VIRTUAL_NETWORK_NAME --name aks2-pod-subnet --query id -o tsv)"

pe "az aks create -n $AKSCLUSTER2 \
    -g $RESOURCE_GROUP \
    --max-pods 250 \
    --node-count $NODE_COUNT \
    --location $LOCATION \
    --generate-ssh-keys \
    --attach-acr $MYACR \
    --network-plugin azure \
    --network-plugin-mode overlay \
    --vnet-subnet-id $SUBNET_ID2 \
    --pod-cidr $AKS2_POD_SUBNET_CIDR \
    --enable-managed-identity \
    --enable-azure-monitor-metrics"

pe "AKS2_RESOURCE_ID=$(az aks show --resource-group $RESOURCE_GROUP --name $AKSCLUSTER2 --query id -o tsv)"

az monitor diagnostic-settings create \
    --resource $AKS2_RESOURCE_ID  \
    --name $AKSCLUSTER2-Diagnostics \
    --workspace $LAW_ID \
    --logs '[{"category": "kube-audit", "enabled": true}, {"category": "kube-apiserver", "enabled": true}, {"category": "kube-controller-manager", "enabled": true}, {"category": "kube-scheduler", "enabled": true}, {"category": "cluster-autoscaler", "enabled": true}]' \
    --metrics '[{"category": "AllMetrics", "enabled": true}]'

# Start a loop that runs if the node pool state is not Succeeded
while [ "$(az aks nodepool show --resource-group $RESOURCE_GROUP --cluster-name $AKSCLUSTER2 --name nodepool1 --query provisioningState -o tsv)" != "Succeeded" ]
do
  # Print a message to wait or retry later
  echo "Waiting for all node pool operations to complete."
  pe "sleep 20"
done

pe "az aks enable-addons -a monitoring -n $AKSCLUSTER2 \
    -g $RESOURCE_GROUP \
    --workspace-resource-id $LAW_ID"

