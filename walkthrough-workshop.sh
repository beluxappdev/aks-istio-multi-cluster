#!/usr/bin/env bash

# Script Purpose:
# This script sets up a multi-cluster Istio service mesh across two AKS clusters.
# It checks for necessary tools, bootstraps the environment, sets up certificates,
# installs and configures Istio, and deploys sample applications to validate the setup.
#
# Prerequisites:
# - Ensure 'az', 'kubectl', and 'istioctl' are installed and available in PATH.
# - Ensure you are logged into Azure CLI and have access to create/manage AKS clusters.
# - Ensure necessary environment variables are set in 'env' file.
#
# Usage:
# ./walkthrough-workshop.sh
#
set -eE

# Loading environment variables and functions
source ./env  # Load environment variables (e.g., RESOURCE_GROUP, AKSCLUSTER1, etc.)
source ./functions.sh  # Load additional functions (e.g., pe)

# 'pe' is a custom function used to execute and print commands.
# It is defined in 'functions.sh' and used throughout this script to execute commands.

# Validate that necessary variables are set
echo -e "$ECHO_COLOR Checking if necessary tools (az, kubectl, istioctl) are installed..."
pe "validate_prerequisites"

echo -e "$ECHO_COLOR Bootstrapping the environment (creating resource groups, AKS clusters, etc.)..."
if [ $(az group exists --name $RESOURCE_GROUP) = false ]; then
    pe "source $BASE_DIR/bootstrap-workshop.sh"
    pe "sleep 20"
fi

echo -e "$ECHO_COLOR << Clusters created, let's update our kube config >>"
pe "az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKSCLUSTER1"
pe "az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKSCLUSTER2"

echo -e "$ECHO_COLOR Set context name in the default Kubernetes configuration file used for accessing cluster1 and cluster2."
pe "export CTX_CLUSTER1=$AKSCLUSTER1"
pe "export CTX_CLUSTER2=$AKSCLUSTER2"

# SECTION: Certificate Generation
# Generate root and intermediate certificates for secure communication between
# clusters in the Istio service mesh. Certificates are generated using Makefile
# targets and stored in the 'certs' directory.
pe "mkdir -p certs"
pe "pushd certs"

echo -e "$ECHO_COLOR Generating root and intermediate certificates for secure communication between clusters in Istio..."
#Generate the root certificate and key:
pe "make -f ../tools/certificates/Makefile.selfsigned.mk root-ca"
# For each cluster, generate an intermediate certificate and key for the Istio CA. The following is an example for cluster1:
pe "make -f ../tools/certificates/Makefile.selfsigned.mk cluster1-cacerts"
pe "make -f ../tools/certificates/Makefile.selfsigned.mk cluster2-cacerts"

# SECTION: Istio Namespace and Secrets Setup
# Creating the Istio system namespace and setting up secrets in both clusters.
pe "kubectl create namespace istio-system --dry-run=client --context=\"${CTX_CLUSTER1}\" -o yaml | kubectl apply --context=\"${CTX_CLUSTER1}\" -f -"
pe "kubectl create namespace istio-system --dry-run=client --context=\"${CTX_CLUSTER2}\" -o yaml | kubectl apply --context=\"${CTX_CLUSTER2}\" -f -"
pe "sleep 20"
pe "kubectl get secrets -n istio-system --context=\"${CTX_CLUSTER1}\" | grep -q \"^cacerts\" || \
        kubectl create secret generic cacerts -n istio-system --context=\"${CTX_CLUSTER1}\" \
        --from-file=cluster1/ca-cert.pem \
        --from-file=cluster1/ca-key.pem \
        --from-file=cluster1/root-cert.pem \
        --from-file=cluster1/cert-chain.pem" 
pe "kubectl get secrets -n istio-system --context=\"${CTX_CLUSTER2}\" | grep -q \"^cacerts\" || \
        kubectl create secret generic cacerts -n istio-system --context=\"${CTX_CLUSTER2}\" \
        --from-file=cluster2/ca-cert.pem \
        --from-file=cluster2/ca-key.pem \
        --from-file=cluster2/root-cert.pem \
        --from-file=cluster2/cert-chain.pem" 

# Return to the top-level directory of the Istio installation:
pe "popd"

# SECTION: Network Configuration
# Setting and labeling the default network for clusters.
echo -e "$ECHO_COLOR Set the default network for cluster1"
pe "kubectl --context=\"${CTX_CLUSTER1}\" get namespace istio-system && \
    kubectl --context=\"${CTX_CLUSTER1}\" label namespace istio-system topology.istio.io/network=network1"

echo -e "$ECHO_COLOR Set the default network for cluster2"
pe "kubectl --context=\"${CTX_CLUSTER2}\" get namespace istio-system && \
    kubectl --context=\"${CTX_CLUSTER2}\" label namespace istio-system topology.istio.io/network=network2"

# SECTION: Istio Installation and Configuration
# Installing and configuring Istio on both clusters.
echo -e "$ECHO_COLOR Configure cluster1 as a primary"
pe "istioctl install -y --context=\"${CTX_CLUSTER1}\" -f $BASE_DIR/kubernetes/istio/cluster1.yaml"

echo -e "$ECHO_COLOR Configure cluster2 as a primary"
pe "istioctl install -y --context=\"${CTX_CLUSTER2}\" -f $BASE_DIR/kubernetes/istio/cluster2.yaml"

# SECTION: East-West Gateway Setup
# Installing and configuring the east-west gateway in both clusters.
echo -e "$ECHO_COLOR Install the east-west gateway in cluster1"
pe "istioctl --context=\"${CTX_CLUSTER1}\" install -y -f  $BASE_DIR/kubernetes/istio/cluster1-ew-gtw-config.yaml"
pe "kubectl patch service istio-eastwestgateway -n istio-system --context=\"${CTX_CLUSTER1}\" -p '{\"metadata\":{\"annotations\":{\"service.beta.kubernetes.io/azure-load-balancer-internal\":\"true\"}}}'"

echo -e "$ECHO_COLOR Install the east-west gateway in cluster2"
pe "istioctl --context=\"${CTX_CLUSTER2}\" install -y -f  $BASE_DIR/kubernetes/istio/cluster2-ew-gtw-config.yaml"
pe "kubectl patch service istio-eastwestgateway -n istio-system --context=\"${CTX_CLUSTER2}\" -p '{\"metadata\":{\"annotations\":{\"service.beta.kubernetes.io/azure-load-balancer-internal\":\"true\"}}}'"

pe "sleep 30"

echo -e "$ECHO_COLOR Check that the east-west gateway assigned an external IP address:"
pe "kubectl --context="${CTX_CLUSTER1}" get svc istio-eastwestgateway -n istio-system"

echo -e "$ECHO_COLOR Check that the east-west gateway assigned an external IP address:"
pe "kubectl --context=\"${CTX_CLUSTER2}\" get svc istio-eastwestgateway -n istio-system"

# SECTION: Service Exposure
# Exposing services on the east-west gateway in both clusters.
echo -e "$ECHO_COLOR Since the clusters are on separate networks, we need to expose all services local on the east-west gateway in both clusters."
pe "kubectl apply --context=\"${CTX_CLUSTER1}\" -n istio-system -f \
    $BASE_DIR/kubernetes/istio/expose-services.yaml"

echo -e "$ECHO_COLOR Since the clusters are on separate networks, we need to expose all services \(*.local\) on the east-west gateway in both clusters."
pe "kubectl --context=\"${CTX_CLUSTER2}\" apply -n istio-system -f \
    $BASE_DIR/kubernetes/istio/expose-services.yaml"

# SECTION: Endpoint Discovery Setup
# Enabling endpoint discovery by installing remote secrets in both clusters.
echo -e "$ECHO_COLOR Enable Endpoint Discovery"
echo -e "$ECHO_COLOR Install a remote secret in cluster2 that provides access to cluster1 s API server."
pe "istioctl create-remote-secret \
  --context=\"${CTX_CLUSTER1}\" \
  --name=cluster1 | \
  kubectl apply -f - --context=\"${CTX_CLUSTER2}\" "

echo -e "$ECHO_COLOR Install a remote secret in cluster1 that provides access to cluster2 s API server."
pe "istioctl create-remote-secret \
  --context=\"${CTX_CLUSTER2}\" \
  --name=cluster2 | \
  kubectl apply -f - --context=\"${CTX_CLUSTER1}\" "


# SECTION: Sample Application Deployment
# Deploy sample applications (helloworld and bookinfo) to validate the Istio
# multi-cluster setup and demonstrate cross-cluster communication.

echo -e "$ECHO_COLOR Verify the installation with the helloworld app"

echo -e "$ECHO_COLOR Create sample namespace and enable sidecar injection"
pe "kubectl create namespace sample --dry-run=client --context=\"${CTX_CLUSTER1}\" -o yaml | kubectl apply --context=\"${CTX_CLUSTER1}\" -f -"
pe "kubectl create namespace sample --dry-run=client --context=\"${CTX_CLUSTER2}\" -o yaml | kubectl apply --context=\"${CTX_CLUSTER2}\" -f -"

pe "kubectl label --context=\"${CTX_CLUSTER1}\" namespace sample \
    istio-injection=enabled"
pe "kubectl label --context=\"${CTX_CLUSTER2}\" namespace sample \
    istio-injection=enabled"

echo -e "$ECHO_COLOR Create the HelloWorld service in both clusters:"
pe "kubectl apply --context=\"${CTX_CLUSTER1}\" \
    -f $BASE_DIR/kubernetes/sample-app/helloworld.yaml \
    -l service=helloworld -n sample"
pe "kubectl apply --context=\"${CTX_CLUSTER2}\" \
    -f $BASE_DIR/kubernetes/sample-app/helloworld.yaml \
    -l service=helloworld -n sample"

pe "kubectl apply --context=\"${CTX_CLUSTER1}\" \
    -f $BASE_DIR/kubernetes/sample-app/helloworld.yaml \
    -l version=v1 -n sample"

pe "kubectl apply --context=\"${CTX_CLUSTER2}\" \
    -f $BASE_DIR/kubernetes/sample-app/helloworld.yaml \
    -l version=v2 -n sample"

# Restric cluster 1 scv traffic to intra cluster
pe "kubectl apply -n sample -f $BASE_DIR/kubernetes/sample-app/helloworld-cluster-local.yaml --context=\"${CTX_CLUSTER1}\""

pe "kubectl apply --context=\"${CTX_CLUSTER1}\" \
    -f $BASE_DIR/kubernetes/sample-app/sleep.yaml -n sample"
pe "kubectl apply --context=\"${CTX_CLUSTER2}\" \
    -f $BASE_DIR/kubernetes/sample-app/sleep.yaml -n sample"

echo -e "$ECHO_COLOR Verify the installation with the bookinfo app"

pe "kubectl create namespace bookinfo --dry-run=client --context=\"${CTX_CLUSTER1}\" -o yaml | kubectl apply --context=\"${CTX_CLUSTER1}\" -f -"
pe "kubectl create namespace bookinfo --dry-run=client --context=\"${CTX_CLUSTER2}\" -o yaml | kubectl apply --context=\"${CTX_CLUSTER2}\" -f -"

pe "kubectl label namespace bookinfo istio-injection=enabled --context=${CTX_CLUSTER1}"
pe "kubectl label namespace bookinfo istio-injection=enabled --context=${CTX_CLUSTER2}"

echo -e "$ECHO_COLOR Assign all components to cluster 1, except for reviews, which is created on cluster 2."
pe "kubectl apply -n bookinfo -f $BASE_DIR/kubernetes/sample-app/bookinfo-cluster1.yaml --context=\"${CTX_CLUSTER1}\""
pe "kubectl apply -n bookinfo -f $BASE_DIR/kubernetes/sample-app/bookinfo-cluster2.yaml --context=\"${CTX_CLUSTER2}\""
# Create product page gateway
pe "kubectl apply -n bookinfo -f $BASE_DIR/kubernetes/sample-app/bookinfo-istio.yaml --context=\"${CTX_CLUSTER1}\""

export GATEWAY_PRODUCT=$(kubectl --context="${CTX_CLUSTER1}" get -n istio-system service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo -e "$ECHO_COLOR Check on your browser the bookinfo app and note that the review service is in cluster 2"
echo -e "$ECHO_COLOR http://${GATEWAY_PRODUCT}/productpage"

# SECTION: Cleanup and Finalization.
echo -e "${ECHO_COLOR}Script execution completed. Review the outputs and logs for any issues.${NC}"
echo -e "${ECHO_COLOR}You can now proceed to test the multi-cluster setup using the provided sample applications.${NC}"