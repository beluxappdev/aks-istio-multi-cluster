# README: Multi-Cluster Istio Service Mesh Setup Script Walkthrough

## Introduction
The provided Bash script is designed to set up a multi-cluster Istio service mesh across two Azure Kubernetes Service (AKS) clusters. It automates the process of checking prerequisites, bootstrapping the environment, generating certificates, installing and configuring Istio, and deploying sample applications to validate the setup.

![Istio Multiclister](/assets/Multi-primary-different-networks.jpeg)

## Prerequisites
Ensure the following tools and access are available to facilitate the setup process:
- `az`: Azure CLI, used for managing Azure resources.
- `kubectl`: Kubernetes command-line tool, used for interacting with clusters.
- `istioctl`: Istio command-line tool, used for managing Istio service mesh.
- Azure CLI login and access to create/manage AKS clusters.
- Environment variables set in an `env` file.

## Script Execution Steps

If you're eager to witness the end result without delving into the details, execute the script below. This will orchestrate the creation of Azure Resources and manage Istio installation and configuration seamlessly.
```bash
./walkthrough-workshop.sh
```

## Manual Execution Steps
For those who prefer a hands-on approach, let's delve into each step, exploring how to configure from scratch and understanding the resources being orchestrated.

1. **Validate Prerequisites**
   
Ensure `az`, `kubectl`, and `istioctl` are installed and available in your PATH.
```bash
az --version
kubectl version --client
istioctl version
```

Modify the env file with a UNIQUEID of your choice, which will be used to create all Azure Resources. After adjusting the env file, ensure to source it in your bash session to utilize it for subsequent lab commands. Remember to reload the env file if you pause and resume the lab.

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

After adjusting the env file, read it in your bash session so you can run all the remaining lab commands. Note that if you stop the lab in the middle, it is important to always reload the env file.
```bash
source ./env 
```

2. **Bootstrapping the Environment**
   
In this lab, you'll establish a foundational setup by creating two AKS clusters, ensuring they have the capability to communicate with each other and access each cluster's east-west gateway. The bootstrap-workshop script provides a streamlined method to generate two basic AKS clusters, which will subsequently be configured with Istio and the sample apps.

Ensure the Azure CLI tool (az) is installed and authenticated with your account:

```bash
az login --use-device-code
```

Upon executing the command, you need to opean a web browser window that will prompt you to sign in with the generated code. Authenticate using the user account associated with the Owner role in your target Azure subscription, and then close the browser window. Verify that you are connected to the correct subscription for subsequent commands:

```bash
az account list -o table
```

If the correct account isn’t indicated as your default in the output, switch to the desired subscription using the following command (replace <subscription-id> with the actual ID):

```bash
az account set --subscription <subscription-id>
```
Now, initiate the bootstrap-workshop script. This process, which may take between 5-10 minutes, will create and configure the two AKS clusters:

```bash
./boostrap-workshop.sh
```

3. **Configure Trust Between the Clusters**
   
Multicluster service mesh deployments require that you establish trust between all clusters in the mesh. For example, you could use a certificate authority (CA) to sign certificates for all of the clusters in the mesh. This would allow the clusters to verify each other's identities using their certificates. Now let's move to the `certs` directory and use `make` commands to generate certificates.
```bash
mkdir -p certs
pushd certs
#Generate the root certificate and key:
make -f ../tools/certificates/Makefile.selfsigned.mk root-ca
# For each cluster, generate an intermediate certificate and key for the Istio CA. The following is an example for cluster1:
make -f ../tools/certificates/Makefile.selfsigned.mk cluster1-cacerts
make -f ../tools/certificates/Makefile.selfsigned.mk cluster2-cacerts
popd
```
> Follow these instructions to try this out. But if you are setting up a cluster that you will be using in production, make sure to use a CA that is designed for production use.
   
4. **Istio Namespace and Secrets Setup**
   
Before diving into secret creation for the certificates, establish the istio-system namespace in both clusters to house Istio components:
```bash
# For Cluster 1
kubectl create namespace istio-system --context="${CTX_CLUSTER1}"
# For Cluster 2
kubectl create namespace istio-system --context="${CTX_CLUSTER2}"
```

Now you can create a secret including all the certs files in each cluster:
```bash
# For Cluster 1
kubectl create secret generic cacerts --context="${CTX_CLUSTER1}" -n istio-system \
   --from-file=cluster1/ca-cert.pem \
   --from-file=cluster1/ca-key.pem \
   --from-file=cluster1/root-cert.pem \
   --from-file=cluster1/cert-chain.pem
# For Cluster 2
kubectl create secret generic cacerts --context="${CTX_CLUSTER2}" -n istio-system \
   --from-file=cluster2/ca-cert.pem \
   --from-file=cluster2/ca-key.pem \
   --from-file=cluster2/root-cert.pem \
   --from-file=cluster2/cert-chain.pem
```
   
5. **Network Configuration**

Network for a mesh is different from traditional networking. Here labeling assists in network segmentation and management within the Istio mesh, ensuring accurate routing and isolation of communication paths. Nowl abel the default network for clusters to manage the network topology within the Istio mesh: 
```bash
# Set the default network for cluster1
kubectl --context="${CTX_CLUSTER1}" get namespace istio-system && \
   kubectl --context="${CTX_CLUSTER1}" label namespace istio-system topology.istio.io/network=network1

# Set the default network for cluster2
kubectl --context="${CTX_CLUSTER2}" get namespace istio-system && \
   kubectl --context="${CTX_CLUSTER2}" label namespace istio-system topology.istio.io/network=network2
```
   
6. **Istio Installation and Configuration**
   
Let's take a look at the Istio configuration for each cluster

```yaml
# Cluster 1
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
values:
   global:
      meshID: mesh1
      multiCluster:
      clusterName: cluster1
      network: network1
---
# Cluster 2 
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
values:
   global:
      meshID: mesh1
      multiCluster:
      clusterName: cluster2
      network: network2
```
Note that we have the same meshID for both clusters, but different clusterName and network. The network must be the same value used during the labeling of the istio-system namespace in step 5. Feel free to tweak the configuration with any other parameters you might need for your use case. 

Now we are going to use `istioctl` to install and configure Istio: 
```bash
# Configure cluster1 as a primary
istioctl install -y --context="${CTX_CLUSTER1}" -f $BASE_DIR/kubernetes/istio/cluster1.yaml
# Configure cluster2 as a primary
istioctl install -y --context="${CTX_CLUSTER2}" -f $BASE_DIR/kubernetes/istio/cluster2.yaml
```
   
7. **East-West Gateway Setup**

In this step we will install and configure the east-west gateway in both clusters, facilitating communication between services in different clusters. This step ensures that services in different clusters can communicate with each other through a dedicated gateway. Let's take a look at one of the configurations we are going to pass to `istioctl`:
```yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
name: eastwest
spec:
revision: ""
profile: empty
components:
   ingressGateways:
      - name: istio-eastwestgateway
      label:
         istio: eastwestgateway
         app: istio-eastwestgateway
         topology.istio.io/network: network1
      enabled: true
      k8s:
         env:
            # traffic through this gateway should be routed inside the network
            - name: ISTIO_META_REQUESTED_NETWORK_VIEW
            value: network1
         service:
            ports:
            - name: status-port
               port: 15021
               targetPort: 15021
            - name: tls
               port: 15443
               targetPort: 15443
            - name: tls-istiod
               port: 15012
               targetPort: 15012
            - name: tls-webhook
               port: 15017
               targetPort: 15017
values:
   gateways:
      istio-ingressgateway:
      injectionTemplate: gateway
   global:
      network: network1
```

Note that the network needs to match the network you labeled the Istio namespace in Step 5. Now, let's install and configure the east-west gateway using `istioctl`:.
```bash
# Installing and configuring the east-west gateway in both clusters.
istioctl --context="${CTX_CLUSTER1}" install -y -f  $BASE_DIR/kubernetes/istio/cluster1-ew-gtw-config.yaml
# Install the east-west gateway in cluster2
istioctl --context="${CTX_CLUSTER2}" install -y -f  $BASE_DIR/kubernetes/istio/cluster2-ew-gtw-config.yaml
```
Optitionally, you can mark those gateways to be exposed as as Internal Load Balancer:
```bash
# Patch cluster 1
kubectl patch service istio-eastwestgateway -n istio-system --context="${CTX_CLUSTER1}" -p '{"metadata":{"annotations":{"service.beta.kubernetes.io/azure-load-balancer-internal":"true"}}}'
# Patch cluster 2
kubectl patch service istio-eastwestgateway -n istio-system --context="${CTX_CLUSTER2}" -p '{"metadata\":{"annotations":{"service.beta.kubernetes.io/azure-load-balancer-internal":"true"}}}'
```
Now wait for the east-west gateway to get an assigned external or internal IP before proceeding:
```bash
# Check cluster 1
kubectl --context="${CTX_CLUSTER1}" get svc istio-eastwestgateway -n istio-system
# Check cluster 2
kubectl --context="${CTX_CLUSTER2}" get svc istio-eastwestgateway -n istio-system
```
   
8. **Service Exposure**

Now we are going to expose services on the east-west gateway in both clusters, making them accessible to services in the other cluster. This step ensures that services can be discovered and accessed across clusters, enabling a truly multi-cluster service mesh. Let's check the gateway configuration for that:

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
name: cross-network-gateway
spec:
selector:
   istio: eastwestgateway
servers:
   - port:
      number: 15443
      name: tls
      protocol: TLS
      tls:
      mode: AUTO_PASSTHROUGH
      hosts:
      - "*.local"
```
As you can see, the host configuration is set to any service that is deployed in the cluster. Other options would be to specify a service ("mysvc.myns.svc.cluster.local"), namespace ("*.myns.svc.cluster.local") or global ("*").  Now let's apply service exposure configurations using `kubectl`:
```bash
# Cluster 1
kubectl apply --context="${CTX_CLUSTER1}" -n istio-system -f \
   $BASE_DIR/kubernetes/istio/expose-services.yaml
# Cluster 2
kubectl --context="${CTX_CLUSTER2}" apply -n istio-system -f \
   $BASE_DIR/kubernetes/istio/expose-services.yaml
```
   
9. **Endpoint Discovery Setup**

On this step we are going to enable endpoint discovery by installing remote secrets in both clusters, allowing each cluster to discover services in the other. This step is crucial for enabling dynamic discovery of services across clusters. Create remote secrets and apply them using `istioctl` and `kubectl`.
```bash
   # Cluster 1
istioctl create-remote-secret \
   --context="${CTX_CLUSTER1}" \
   --name=cluster1 | \
   kubectl apply -f - --context="${CTX_CLUSTER2}" 
# Cluster 2
istioctl create-remote-secret \
   --context="${CTX_CLUSTER2}" \
   --name=cluster2 | \
   kubectl apply -f - --context="${CTX_CLUSTER1}"
```
   
10. **Helloworld Application Deployment**

Now is where the fun (or despair) begins. Let's make sure everything is working as expected. The first application we are going to deploy is the helloworld app from the public Istio respo. The goal will be to deploy it in both clusters and use the sleep app to validate that the service in both cluster are accessible.   

Here's the helloworld app deployment
```bash
#Create sample namespace 
kubectl create namespace sample --context="${CTX_CLUSTER1}"
kubectl create namespace sample --context="${CTX_CLUSTER2}"
# Enable istio injection
kubectl label --context="${CTX_CLUSTER1}" namespace sample istio-injection=enabled
kubectl label --context="${CTX_CLUSTER2}" namespace sample istio-injection=enabled
# Create the HelloWorld service in both clusters:
kubectl apply --context="${CTX_CLUSTER1}" \
   -f $BASE_DIR/kubernetes/sample-app/helloworld.yaml \
   -l service=helloworld -n sample
kubectl apply --context="${CTX_CLUSTER2}" \
   -f $BASE_DIR/kubernetes/sample-app/helloworld.yaml \
   -l service=helloworld -n sample
# Deploy version 1 in cluster 1
kubectl apply --context=\"${CTX_CLUSTER1}\" \
   -f $BASE_DIR/kubernetes/sample-app/helloworld.yaml \
   -l version=v1 -n sample
# Deploy version 2 in cluster 2
kubectl apply --context="${CTX_CLUSTER2}" \
   -f $BASE_DIR/kubernetes/sample-app/helloworld.yaml \
   -l version=v2 -n sample
# Now let's deploy the sleep app
kubectl apply --context="${CTX_CLUSTER1}" \
   -f $BASE_DIR/kubernetes/sample-app/sleep.yaml -n sample
kubectl apply --context="${CTX_CLUSTER2}" \
   -f $BASE_DIR/kubernetes/sample-app/sleep.yaml -n sample
```

Make sure all pods are running, including the envoy side car:
```bash
kubectl get pods -n sample --context="${CTX_CLUSTER1}" -o wide
kubectl get pods -n sample --context="${CTX_CLUSTER2}" -o wide
```

Now it's time to verify the cross-cluster traffic. For that, we are going to call the helloworld service seceral times using the Sleep pod. The reason why we are doing this from the Sleep pod is to ensure the traffic is being routed inside the mesh we created. 

Send one request from the Sleep pod on cluster1 to the HelloWorld service:
```bash
kubectl exec --context="${CTX_CLUSTER1}" -n sample -c sleep \
   "$(kubectl get pod --context="${CTX_CLUSTER1}" -n sample -l \
   app=sleep -o jsonpath='{.items[0].metadata.name}')" \
   -- curl -sS helloworld.sample:5000/hello
```
Repeat this request several times and verify that the HelloWorld version should toggle between v1 and v2.

Now let's do the same from cluster 2:
```bash
kubectl exec --context="${CTX_CLUSTER2}" -n sample -c sleep \
   "$(kubectl get pod --context="${CTX_CLUSTER2}" -n sample -l \
   app=sleep -o jsonpath='{.items[0].metadata.name}')" \
   -- curl -sS helloworld.sample:5000/hello
```

You should see alternate responses from Helloworld V1 and Helloworld V2.

11. **Multi-cluster Traffic Management**
In this section we are going to play with ServiceEntry and DestinationRule to see how we can manage the traffic between the clusters. The result will be the following:

![Helloworld Multiclister](/assets/Helloworld-multicluster.jpeg)


For this example, we are going to apply the following Istio resources to cluster 1:
```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
name: helloworld-per-cluster-dr
spec:
host: helloworld.sample.svc.cluster.local
subsets:
- name: cluster1
   labels:
      topology.istio.io/cluster: cluster1
- name: cluster2
   labels:
      topology.istio.io/cluster: cluster2
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
name: helloworld-cluster-local-vs
spec:
hosts:
- helloworld.sample.svc.cluster.local
http:
- name: "cluster-1-local"
   match:
   - sourceLabels:
      topology.istio.io/cluster: "cluster1"
   route:
   - destination:
      host: helloworld.sample.svc.cluster.local
      subset: cluster1
- name: "cluster-2-local"
   match:
   - sourceLabels:
      topology.istio.io/cluster: "cluster2"
   route:
   - destination:
      host: helloworld.sample.svc.cluster.local
      subset: cluster2
```
DestinationRule subsets allows you to partition a service by selecting labels. In the example above, we create two subsets: 1 for cluster 1 and another one for cluster 2. This provides another way to create cluster-local traffic rules by limiting the destination subset in a VirtualService, as can be seen above.

Now let's try to do the same test as before, by executing the curl command via the Sleep pod several times in each cluster:
```bash
kubectl exec --context="${CTX_CLUSTER1}" -n sample -c sleep \
   "$(kubectl get pod --context="${CTX_CLUSTER1}" -n sample -l \
   app=sleep -o jsonpath='{.items[0].metadata.name}')" \
   -- curl -sS helloworld.sample:5000/hello
```
   Repeat this request several times and verify that the HelloWorld version should always respond with V1, since we restricted the traffic of that service to that cluster only. 

   Now let's do the same from cluster 2:
```bash
kubectl exec --context="${CTX_CLUSTER2}" -n sample -c sleep \
   "$(kubectl get pod --context="${CTX_CLUSTER2}" -n sample -l \
   app=sleep -o jsonpath='{.items[0].metadata.name}')" \
   -- curl -sS helloworld.sample:5000/hello
```
This should continue beyond routed to both clusters, with V1 and V2 being in the responses.

12. **Bookinfo Application Deployment**

Let's focus on something that can be accessed by a browser. We are going to deploy the Istio Bookinfo sample app. Plase check which services are part of this solution by checking the Istio documentation. 

Now we are going to deploy the bookinfo app in our clusters, but instead of deploying everything to a single cluster. We are deploying the review service and all its versions on Cluster 2 and the remaining services on Cluster 1.  It will be something like this:

![Bookinfo Multiclister](/assets/Bookinfo-multicluster.jpeg)

```bash
#Create sample namespace 
kubectl create namespace bookinfo --context="${CTX_CLUSTER1}"
kubectl create namespace bookinfo --context="${CTX_CLUSTER2}"
# Enable istio injection
kubectl label --context="${CTX_CLUSTER1}" namespace bookinfo istio-injection=enabled
kubectl label --context="${CTX_CLUSTER2}" namespace bookinfo istio-injection=enabled
# Deploy all components to cluster 1, except for reviews, which is created on cluster 2
kubectl apply -n bookinfo -f $BASE_DIR/kubernetes/sample-app/bookinfo-cluster1.yaml --context="${CTX_CLUSTER1}"
kubectl apply -n bookinfo -f $BASE_DIR/kubernetes/sample-app/bookinfo-cluster2.yaml --context="${CTX_CLUSTER2}"
# Deploy the istio gateway for the front end in cluster 1
kubectl apply -n bookinfo -f $BASE_DIR/kubernetes/sample-app/bookinfo-gateway.yaml --context="${CTX_CLUSTER1}"
# Retrieve the gateway external IP
export GATEWAY_PRODUCT=$(kubectl --context="${CTX_CLUSTER1}" get -n istio-system service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
# Check on your browser the bookinfo app and note that the review service is in cluster 2
echo "http://${GATEWAY_PRODUCT}/productpage"
```

Copy the URL generated by the echo command above and paste it in your browser. If the networking gods are on your side, you should be able to see the main bookinfo landing page with the review section alternating versions everytime you refresh the page. 

But wait, how the Product page service was able to find the reviews service in another cluster? In multicluster deployments, the client cluster must have a DNS entry for the service in order for the DNS lookup to succeed To ensure successful DNS lookups in multicluster deployments, deploy a Kubernetes Service, even if there are no instances of that service's pods running in the client cluster.

Check the bookinfo-cluster1.yaml and note that there's a service definition for the reviews service, even tough there's no reviews deployment in cluster 1. 

13. **Cleanup**
To remove all the resources created, just delete the Azure Resource Group:
```bash
az group delete --name $RESOURCE_GROUP
```

13. **Troubleshoot**
TODO

13. **References / More Information**
1. [Istio Deployment Models](https://istio.io/latest/docs/ops/deployment/deployment-models/)
2. [Multi-Primary on different networks](https://istio.io/latest/docs/setup/install/multicluster/multi-primary_multi-network/)
3. [Plug in CA Certificates](https://istio.io/latest/docs/tasks/security/cert-management/plugin-ca-cert/)
4. [Bookinfo Application](https://istio.io/latest/docs/examples/bookinfo/)
5. [Azure Kubernetes Services](https://learn.microsoft.com/en-us/azure/aks/intro-kubernetes)