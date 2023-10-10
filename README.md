# README: Multi-Cluster Istio Service Mesh Setup Script Walkthrough

## Introduction
The provided Bash script is designed to set up a multi-cluster Istio service mesh across two Azure Kubernetes Service (AKS) clusters. It automates the process of checking prerequisites, bootstrapping the environment, generating certificates, installing and configuring Istio, and deploying sample applications to validate the setup.

## Prerequisites
- `az`: Azure CLI, used for managing Azure resources.
- `kubectl`: Kubernetes command-line tool, used for interacting with clusters.
- `istioctl`: Istio command-line tool, used for managing Istio service mesh.
- Azure CLI login and access to create/manage AKS clusters.
- Environment variables set in an `env` file.

## Script Execution Steps
1. **Loading Environment Variables and Functions**
2. **Validate Prerequisites**
3. **Bootstrapping the Environment**
4. **Certificate Generation**
5. **Istio Namespace and Secrets Setup**
6. **Network Configuration**
7. **Istio Installation and Configuration**
8. **East-West Gateway Setup**
9. **Service Exposure**
10. **Endpoint Discovery Setup**
11. **Sample Application Deployment**
12. **Cleanup and Finalization**

## Manual Execution Steps
Below are the steps to manually execute the script's operations:

1. **Validate Prerequisites**
   
   **1.1** Ensure `az`, `kubectl`, and `istioctl` are installed and available in your PATH.
   ```bash
   az --version
   kubectl version --client
   istioctl version
   ```

   **1.2** Edit the env file with a UNIQUEID that you want to use to create all the Azure Resources.
   ```bash
   # Edit this unique names to create the Azure resources
    export UNIQUEID=$(openssl rand -hex 3)
    export APPNAME=multicluster
    export LOCATION=eastus

    # Resource names (you can edit if needed)
    export BASE_DIR=$PWD
    export WORK_DIR=$BASE_DIR/workdir
    export PATH=$PATH:$WORK_DIR/bin:
    export RESOURCE_GROUP=rg-$APPNAME-$UNIQUEID
    export MYACR=acr$APPNAME$UNIQUEID
    export VIRTUAL_NETWORK_NAME=vnet-$APPNAME-$UNIQUEID
    export AKS1_SUBNET_CIDR=10.1.1.0/24
    export AKS2_SUBNET_CIDR=10.1.2.0/24
    export AKSCLUSTER1=aks1-$APPNAME-$UNIQUEID
    export AKSCLUSTER2=aks2-$APPNAME-$UNIQUEID
    export NODE_COUNT=3
    export ISTIO_VERSION=1.19.1
    export CTX_CLUSTER1=$AKSCLUSTER1
    export CTX_CLUSTER2=$AKSCLUSTER2

    # NON Istio / Cluster config
    # PE Color
    export PE_COLOR='\033[0;32m'
    # ECHO Color
    export ECHO_COLOR="\033[0;34m"
    export ERROR_COLOR="\033[0;31m"
    export NC='\033[0m'
   ```

   **1.3** After adjusting the env file, read it in your bash session so you can run all the remaining lab commands. Note that if you stop the lab in the middle, it is important to always reload the env file.
   ```bash
   source ./env 
   ```

2. **Bootstrapping the Environment**
   
   **2.1** For this workshop, you will need 2 AKS cluster that can communicate to each other, or that has access to each cluster eastwest gateway. The script bootstrap-workshop is the easiest way to create two vanilla AKS clusters for configuring Istio and the sample apps. To run it, all you need to do is ensure that tou have az tool installed and then login with your account:

   ```bash
   az login --use-device-code
   ```

   **2.2** Executing the command will automatically open a web browser window prompting you to authenticate. Once prompted, sign in using the user account that has the Owner role in the target Azure subscription that you will use in this lab and close the web browser window. Make sure that you are logged in to the right subscription for the consecutive commands.

   ```bash
   az account list -o table
   ```

   **2.3** If in the above statement you don’t see the right account being indicated as your default one, change your environment to the right subscription with the following command, replacing the <subscription-id>.

   ```bash
   az account set --subscription <subscription-id>
   ```
   **2.4** For this workshop, you will need 2 AKS cluster that can communicate to each other, or that has access to each cluster eastwest gateway. The script bootstrap-workshop is the easiest way to create two vanilla AKS clusters for configuring Istio and the sample apps. Note that this script can take from 5-10 minutes to run.

   ```bash
   ./boostrap-workshop.sh
   ```

3. **Certificate Generation**
   Navigate to the `certs` directory and use `make` commands to generate certificates.
   ```bash
   cd certs
   make -f ../tools/certs/Makefile.selfsigned.mk root-ca
   make -f ../tools/certs/Makefile.selfsigned.mk [CLUSTER]-cacerts
   ```
   
4. **Istio Namespace and Secrets Setup**
   Manually create namespaces and secrets using `kubectl`.
   ```bash
   kubectl create namespace istio-system
   kubectl create secret generic cacerts -n istio-system --from-file=[CLUSTER]/ca-cert.pem --from-file=[CLUSTER]/ca-key.pem --from-file=[CLUSTER]/root-cert.pem --from-file=[CLUSTER]/cert-chain.pem
   ```
   
5. **Network Configuration**
   Label the Istio namespace with the network name.
   ```bash
   kubectl label namespace istio-system topology.istio.io/network=[NETWORK_NAME]
   ```
   
6. **Istio Installation and Configuration**
   Use `istioctl` to install and configure Istio.
   ```bash
   istioctl install -y -f [ISTIO_CONFIG_FILE]
   ```
   
7. **East-West Gateway Setup**
   Install and configure the east-west gateway using `istioctl` and `kubectl`.
   ```bash
   istioctl install -y -f [GATEWAY_CONFIG_FILE]
   kubectl patch service istio-eastwestgateway -n istio-system -p '{"metadata":{"annotations":{"service.beta.kubernetes.io/azure-load-balancer-internal":"true"}}}'
   ```
   
8. **Service Exposure**
   Apply service exposure configurations using `kubectl`.
   ```bash
   kubectl apply -n istio-system -f [EXPOSE_SERVICES_YAML]
   ```
   
9. **Endpoint Discovery Setup**
   Create remote secrets and apply them using `istioctl` and `kubectl`.
   ```bash
   istioctl create-remote-secret --context="[CTX_CLUSTER]" --name=[CLUSTER_NAME] | kubectl apply -f -
   ```
   
10. **Sample Application Deployment**
    Deploy sample applications using `kubectl`.
    ```bash
    kubectl apply -n [NAMESPACE] -f [APPLICATION_YAML]
    ```
   
11. **Cleanup and Finalization**
    Ensure all resources are running and validate the setup by accessing the applications.

## Note
- Ensure to replace placeholders (like `[RESOURCE_GROUP]`, `[AKS_CLUSTER_NAME]`, etc.) with actual values.
- For detailed explanations of each step, refer to the comments in the provided script.
- Always validate the setup at each step to ensure smooth deployment and configuration.
