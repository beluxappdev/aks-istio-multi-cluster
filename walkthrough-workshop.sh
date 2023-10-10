#!/usr/bin/env bash

set -eE

# Load configure env variables
source ./env
source ./functions.sh

# Check tools
echo -e "$ECHO_COLOR Checking if necessary tools (az, kubectl, istioctl) are installed..."
pe "validate_prerequisites"

echo -e "$ECHO_COLOR Bootstrapping the environment (creating resource groups, AKS clusters, etc.)..."
if [ $(az group exists --name $RESOURCE_GROUP) = false ]; then
    pe "source $BASE_DIR/bootstrap-workshop.sh"
fi

echo -e "$ECHO_COLOR << Clusters created, let's update our kube config >>"
echo -e "$ECHO_COLOR ============================================================ >>"
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKSCLUSTER1
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKSCLUSTER2

echo -e "$ECHO_COLOR << Set context name in the default Kubernetes configuration file used for accessing cluster1 and cluster2. >>"
echo -e "$ECHO_COLOR ============================================================ >>"
pe "export CTX_CLUSTER1=$AKSCLUSTER1"
pe "export CTX_CLUSTER2=$AKSCLUSTER2"


echo -e "$ECHO_COLOR Set context name in the default Kubernetes configuration file used for accessing cluster1 and cluster2. >>"
echo -e "$ECHO_COLOR For this, first we need to create a self >>"
echo -e "$ECHO_COLOR ============================================================ >>"
# A multicluster service mesh deployment requires that you establish trust between all clusters in the mesh.
pe "mkdir -p certs"
pe "pushd certs"

echo -e "$ECHO_COLOR Generating root and intermediate certificates for secure communication between clusters in Istio..."
#Generate the root certificate and key:
pe "make -f ../tools/certs/Makefile.selfsigned.mk root-ca"
# For each cluster, generate an intermediate certificate and key for the Istio CA. The following is an example for cluster1:
pe "make -f ../tools/certs/Makefile.selfsigned.mk cluster1-cacerts"
pe "make -f ../tools/certs/Makefile.selfsigned.mk cluster2-cacerts"

pe "kubectl create namespace istio-system --dry-run=client --context=\"${CTX_CLUSTER1}\" -o yaml | kubectl apply --context=\"${CTX_CLUSTER1}\" -f -"
pe "kubectl get secrets -n istio-system --context=\"${CTX_CLUSTER1}\" | grep -q \"^cacerts\" || \
        kubectl create secret generic cacerts -n istio-system --context=\"${CTX_CLUSTER1}\" \
        --from-file=cluster1/ca-cert.pem \
        --from-file=cluster1/ca-key.pem \
        --from-file=cluster1/root-cert.pem \
        --from-file=cluster1/cert-chain.pem" 

pe "kubectl create namespace istio-system --dry-run=client --context=\"${CTX_CLUSTER2}\" -o yaml | kubectl apply --context=\"${CTX_CLUSTER2}\" -f -"
pe "kubectl get secrets -n istio-system --context=\"${CTX_CLUSTER2}\" | grep -q \"^cacerts\" || \
        kubectl create secret generic cacerts -n istio-system --context=\"${CTX_CLUSTER2}\" \
        --from-file=cluster2/ca-cert.pem \
        --from-file=cluster2/ca-key.pem \
        --from-file=cluster2/root-cert.pem \
        --from-file=cluster2/cert-chain.pem" 

# Return to the top-level directory of the Istio installation:
pe "popd"

echo -e "$ECHO_COLOR Install Multi-Primary on different networks"
echo -e "$ECHO_COLOR Set the default network for cluster1"
pe "kubectl --context=\"${CTX_CLUSTER1}\" get namespace istio-system && \
    kubectl --context=\"${CTX_CLUSTER1}\" label namespace istio-system topology.istio.io/network=network1"

echo -e "$ECHO_COLOR Configure cluster1 as a primary"
pe "istioctl install -y --context=\"${CTX_CLUSTER1}\" -f $BASE_DIR/kubernetes/istio/cluster1.yaml"

echo -e "$ECHO_COLOR Install the east-west gateway in cluster1"
pe "$BASE_DIR/kubernetes/istio/gen-eastwest-gateway.sh \
    --mesh mesh1 --cluster cluster1 --network network1 | \
    istioctl --context=\"${CTX_CLUSTER1}\" install -y -f -"
pe "kubectl patch service istio-eastwestgateway -n istio-system --context=\"${CTX_CLUSTER1}\" -p '{\"metadata\":{\"annotations\":{\"service.beta.kubernetes.io/azure-load-balancer-internal\":\"true\"}}}'"

pe "sleep 20"

echo -e "$ECHO_COLOR Check that the east-west gateway assigned an external IP address:"
pe "kubectl --context="${CTX_CLUSTER1}" get svc istio-eastwestgateway -n istio-system"

echo -e "$ECHO_COLOR Since the clusters are on separate networks, we need to expose all services local on the east-west gateway in both clusters."
pe "kubectl apply --context=\"${CTX_CLUSTER1}\" -n istio-system -f \
    $BASE_DIR/kubernetes/istio/expose-services.yaml"

echo -e "$ECHO_COLOR Set the default network for cluster2"
pe "kubectl --context=\"${CTX_CLUSTER2}\" get namespace istio-system && \
    kubectl --context=\"${CTX_CLUSTER2}\" label namespace istio-system topology.istio.io/network=network2"

echo -e "$ECHO_COLOR Configure cluster2 as a primary"
pe "istioctl install -y --context=\"${CTX_CLUSTER2}\" -f $BASE_DIR/kubernetes/istio/cluster2.yaml"

echo -e "$ECHO_COLOR Install the east-west gateway in cluster2"
pe "$BASE_DIR/kubernetes/istio/gen-eastwest-gateway.sh \
    --mesh mesh1 --cluster cluster2 --network network2 | \
    istioctl --context=\"${CTX_CLUSTER2}\" install -y -f -"
pe "kubectl patch service istio-eastwestgateway -n istio-system --context=\"${CTX_CLUSTER2}\" -p '{\"metadata\":{\"annotations\":{\"service.beta.kubernetes.io/azure-load-balancer-internal\":\"true\"}}}'"

pe "sleep 20"

echo -e "$ECHO_COLOR Check that the east-west gateway assigned an external IP address:"
pe "kubectl --context=\"${CTX_CLUSTER2}\" get svc istio-eastwestgateway -n istio-system"

echo -e "$ECHO_COLOR Since the clusters are on separate networks, we need to expose all services \(*.local\) on the east-west gateway in both clusters."
pe "kubectl --context=\"${CTX_CLUSTER2}\" apply -n istio-system -f \
    $BASE_DIR/kubernetes/istio/expose-services.yaml"

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

echo -e "$ECHO_COLOR Verify the installation"

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

pe "kubectl apply --context=\"${CTX_CLUSTER1}\" \
    -f $BASE_DIR/kubernetes/sample-app/sleep.yaml -n sample"
pe "kubectl apply --context=\"${CTX_CLUSTER2}\" \
    -f $BASE_DIR/kubernetes/sample-app/sleep.yaml -n sample"


# BOOKINFO
pe "kubectl create namespace bookinfo --dry-run=client --context=\"${CTX_CLUSTER1}\" -o yaml | kubectl apply --context=\"${CTX_CLUSTER1}\" -f -"
pe "kubectl create namespace bookinfo --dry-run=client --context=\"${CTX_CLUSTER2}\" -o yaml | kubectl apply --context=\"${CTX_CLUSTER2}\" -f -"

pe "kubectl label namespace bookinfo istio-injection=enabled --context=\"${CTX_CLUSTER1}\""
pe "kubectl label namespace bookinfo istio-injection=enabled --context=\"${CTX_CLUSTER2}\""

pe "kubectl apply -n bookinfo -f $BASE_DIR/kubernetes/sample-app/bookinfo-cluster1.yaml --context=\"${CTX_CLUSTER1}\""
pe "kubectl apply -n bookinfo -f $BASE_DIR/kubernetes/sample-app/bookinfo-cluster2.yaml --context=\"${CTX_CLUSTER2}\""

pe "kubectl apply -n bookinfo -f $BASE_DIR/kubernetes/sample-app/bookinfo-gateway.yaml --context=\"${CTX_CLUSTER1}\""


echo -e "${NC}"