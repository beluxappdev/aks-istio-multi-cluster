# View Cluster Info
kubectl cluster-info

# Create Namespaces for each team
kubectl create namespace team-1
kubectl create namespace team-2

# List Namespaces
kubectl get namespaces

# Deploy Sample Application
kubectl apply -f kube-manifests/01-Sample-Application -n team-a
kubectl apply -f kube-manifests/01-Sample-Application -n team-b

# Access Dev Application
kubectl get svc -n dev
http://<public-ip>/app1/index.html

# Access Dev Application
kubectl get svc -n qa
http://<public-ip>/app1/index.html

# Get Azure AKS Cluster Id
AKS_CLUSTER_ID=$(az aks show --resource-group rg-bu0001a0008 --name aks-soxpftrvl34xi --query id -o tsv)
AKS_CLUSTER_ID="/subscriptions/7b94870a-998d-4dd8-a051-9cc35ceb1ade/resourcegroups/rg-bu0001a0008/providers/Microsoft.ContainerService/managedClusters/aks-soxpftrvl34xi"

# Create Azure AD Group
az ad group create --display-name team-1 --mail-nickname team-1   
TEAM_A_GROUP_ID="970a797e-443e-4e4c-80d5-b9832fe23bb0"

# Create Role Assignment 
az role assignment create \
  --assignee $TEAM_A_GROUP_ID \
  --role "Azure Kubernetes Service Cluster User Role" \
  --scope $AKS_CLUSTER_ID

# Create Team A User
az ad user create \
  --display-name "AKS TEAM A MEMBER" \
  --user-principal-name team-a@MngEnv673277.onmicrosoft.com \
  --password @AKSrbac123 
TEAM_A_AKS_USER_OBJECT_ID="73c8305b-a644-4090-bba0-b9cea0974968"

# Associate Dev User to Dev AKS Group
az ad group member add --group team-1 --member-id $TEAM_A_AKS_USER_OBJECT_ID

kubectl apply -f - <<EOF
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: team-1-user-full-access-role
  namespace: team-1
rules:
- apiGroups: ["", "extensions", "apps"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["batch"]
  resources:
  - jobs
  - cronjobs
  verbs: ["*"]
EOF

kubectl apply -f - <<EOF
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: team-1-user-access-rolebinding
  namespace: team-1
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: team-1-user-full-access-role
subjects:
- kind: Group
  namespace: team-a
  #name: groupObjectId
  name: "970a797e-443e-4e4c-80d5-b9832fe23bb0"  
EOF

# Verifying the Role and Role Binding
kubectl get role -n team-1
kubectl get rolebinding -n team-1

# List pods from Team A Namespace
kubectl get pods -n team-1

# List pods from QA Namespace
kubectl get pods -n team-b