# k8s-lab
Kubernetes Cluster Management Toolkit
This repository provides a repeatable way to manage multiple Kubernetes clusters from a single Linux workstation or Multipass VM.
It supports:
Rancher management clusters
Rancher downstream clusters
Rancher Desktop
K3s and RKE2
Development, staging, and production clusters
Any Kubernetes cluster with a reachable API server and valid kubeconfig
The toolkit stores each cluster kubeconfig separately, creates a merged kubeconfig, and allows kubectl, K9s, Helm, and other Kubernetes tools to access all onboarded clusters.

Repository Structure
k8s-lab/
├── cluster/
│   ├── onboard-cluster.sh
│   ├── remove-cluster.sh
│   ├── kubeconfigs/
│   │   └── .gitkeep
│   ├── merged/
│   │   └── .gitkeep
│   └── backups/
│       └── .gitkeep
├── .gitignore
└── README.md

Directory Purpose
Directory
Purpose
cluster/kubeconfigs/
Stores one normalized kubeconfig per onboarded cluster
cluster/merged/
Stores the generated kubeconfig containing all clusters
cluster/backups/
Stores previous kubeconfig versions for rollback
~/.kube/config
Active kubeconfig used by kubectl, K9s, Helm, and related tools


Required Tools
The following tools should be installed in the Multipass VM:
kubectl
helm
k9s
kubectx
kubens
stern
jq
yq
curl
git

Verify them:
kubectl version --client
helm version
k9s version
kubectx --version
kubens --version
stern --version
jq --version
yq --version


Initial Setup
Create the required directories:
mkdir -p ~/k8s-lab/cluster/{kubeconfigs,merged,backups}

Set secure permissions:
chmod 700 ~/k8s-lab/cluster
chmod 700 ~/k8s-lab/cluster/kubeconfigs
chmod 700 ~/k8s-lab/cluster/merged
chmod 700 ~/k8s-lab/cluster/backups

Make the scripts executable:
chmod +x ~/k8s-lab/cluster/onboard-cluster.sh
chmod +x ~/k8s-lab/cluster/remove-cluster.sh


Kubeconfig Security
Kubeconfig files can contain:
Bearer tokens
Client private keys
Client certificates
Authentication plugins
Internal Kubernetes API addresses
Never commit real kubeconfig files to Git.
Add this to .gitignore:
# Kubernetes credentials
.kube/

cluster/kubeconfigs/*
!cluster/kubeconfigs/.gitkeep

cluster/merged/*
!cluster/merged/.gitkeep

cluster/backups/*
!cluster/backups/.gitkeep

*.kubeconfig
*kubeconfig*.yaml
*kubeconfig*.yml

Recommended permissions:
chmod 700 ~/.kube
chmod 600 ~/.kube/config
chmod 600 ~/k8s-lab/cluster/kubeconfigs/*.yaml

Before pushing to Git:
git status
git diff --cached
git ls-files | grep -Ei 'kubeconfig|cluster/kubeconfigs|cluster/merged|cluster/backups'

Search for accidentally committed credentials:
git grep -nE 'client-key-data:|client-certificate-data:|token:|password:'


Rancher Kubeconfig Behaviour
A kubeconfig downloaded from Rancher may contain multiple contexts.
For example:
local
rancher

or:
zeiss-corp-macbook-vm
rancher

The rancher context points to the Rancher API endpoint.
The actual Kubernetes cluster context is normally:
local

for the Rancher management cluster, or a downstream cluster name such as:
zeiss-corp-macbook-vm

The onboarding script should import only the actual Kubernetes cluster context and exclude the generic rancher context.
Otherwise, duplicate contexts can appear:
local
rancher
rancher-management-local
rancher-management-rancher

The desired result is:
rancher-management
zeiss-corp-macbook-vm
development
staging
production


Inspecting a Downloaded Kubeconfig
List all contexts:
kubectl config get-contexts \
  --kubeconfig ~/Downloads/rancher-local.yml

List context names only:
kubectl config get-contexts \
  --kubeconfig ~/Downloads/rancher-local.yml \
  -o name

Show the current context:
kubectl config current-context \
  --kubeconfig ~/Downloads/rancher-local.yml

List configured API servers:
kubectl config view \
  --kubeconfig ~/Downloads/rancher-local.yml \
  -o jsonpath='{range .clusters[*]}{.name}{" => "}{.cluster.server}{"\n"}{end}'


Onboarding a Cluster
The onboarding script accepts:
onboard-cluster.sh <kubeconfig-file> <cluster-name> [--default]

Example:
~/k8s-lab/cluster/onboard-cluster.sh \
  ~/Downloads/rancher-local.yml \
  rancher-management \
  --default

The first argument is the downloaded kubeconfig.
The second argument is the name that will be used locally.
The script creates:
cluster/kubeconfigs/rancher-management.yaml

The original downloaded file is not renamed. A normalized managed copy is created.

Onboarding the Rancher Management Cluster
Download the local cluster kubeconfig from Rancher.
Then run:
~/k8s-lab/cluster/onboard-cluster.sh \
  ~/Downloads/rancher-local.yml \
  rancher-management \
  --default

Expected context:
rancher-management

Verify:
kubectl config get-contexts
kubectl config current-context
kubectl get nodes


Onboarding a Rancher Downstream Cluster
Download the downstream cluster kubeconfig from Rancher.
Example:
~/k8s-lab/cluster/onboard-cluster.sh \
  ~/Downloads/zeiss-corp-macbook-vm.yml \
  zeiss-corp-macbook-vm

Verify:
kubectl config get-contexts

Switch to it:
kubectl config use-context zeiss-corp-macbook-vm

Test access:
kubectl get nodes
kubectl get pods -A


Onboarding Future Clusters
Development
~/k8s-lab/cluster/onboard-cluster.sh \
  ~/Downloads/dev-kubeconfig.yml \
  development

Staging
~/k8s-lab/cluster/onboard-cluster.sh \
  ~/Downloads/staging-kubeconfig.yml \
  staging

Production
~/k8s-lab/cluster/onboard-cluster.sh \
  ~/Downloads/production-kubeconfig.yml \
  production

Set a newly onboarded cluster as the default:
~/k8s-lab/cluster/onboard-cluster.sh \
  ~/Downloads/production-kubeconfig.yml \
  production \
  --default


Listing Onboarded Clusters
List contexts:
kubectl config get-contexts

List context names only:
kubectl config get-contexts -o name

Show the current context:
kubectl config current-context

List the cluster records stored in the kubeconfig:
kubectl config view \
  -o jsonpath='{range .clusters[*]}{.name}{"\n"}{end}'

List saved source kubeconfigs:
ls -lah ~/k8s-lab/cluster/kubeconfigs

List all cluster-management files:
find ~/k8s-lab/cluster \
  -maxdepth 2 \
  -type f \
  -print


Switching Between Clusters
Using kubectl:
kubectl config use-context rancher-management
kubectl config use-context zeiss-corp-macbook-vm
kubectl config use-context development
kubectl config use-context staging
kubectl config use-context production

Using kubectx:
kubectx rancher-management
kubectx zeiss-corp-macbook-vm
kubectx development
kubectx staging
kubectx production

List available contexts:
kubectx


Using K9s
Open the current cluster:
k9s

Open a specific cluster:
k9s --context rancher-management

k9s --context zeiss-corp-macbook-vm

k9s --context production

Switch contexts inside K9s:
:contexts

Switch namespaces inside K9s:
:namespaces


Namespace Management
List namespaces:
kubectl get namespaces

Switch namespace:
kubens cattle-system

Return to the default namespace:
kubens default

Run K9s in a namespace:
k9s --namespace cattle-system


Common Kubernetes Commands
Check nodes:
kubectl get nodes -o wide

Check pods in all namespaces:
kubectl get pods -A

Check deployments:
kubectl get deployments -A

Check services:
kubectl get services -A

Check all common resources:
kubectl get all -A

Describe a resource:
kubectl describe pod <pod-name> \
  -n <namespace>

Read logs:
kubectl logs <pod-name> \
  -n <namespace>

Follow logs:
kubectl logs -f <pod-name> \
  -n <namespace>

Execute a shell inside a pod:
kubectl exec -it <pod-name> \
  -n <namespace> \
  -- /bin/sh


Rancher Agent Commands
Check Rancher agents on a downstream cluster:
kubectl get pods \
  -n cattle-system

Check the cluster agent:
kubectl get deployment \
  cattle-cluster-agent \
  -n cattle-system

Read cluster-agent logs:
kubectl logs \
  -n cattle-system \
  deployment/cattle-cluster-agent \
  --tail=100

Follow matching pod logs using Stern:
stern cattle-cluster-agent \
  -n cattle-system

Healthy agent logs generally contain:
/ping is accessible
Connecting to proxy
Connected to proxy


Helm Usage
Always verify the current context before using Helm:
kubectl config current-context

List Helm releases:
helm list -A

Install a chart:
helm install <release-name> <chart> \
  --namespace <namespace> \
  --create-namespace

Upgrade a release:
helm upgrade <release-name> <chart> \
  --namespace <namespace>

Remove a release:
helm uninstall <release-name> \
  --namespace <namespace>

Target a specific cluster explicitly:
helm \
  --kube-context production \
  list -A


Merged Kubeconfig
Each onboarded cluster has a separate source file:
cluster/kubeconfigs/rancher-management.yaml
cluster/kubeconfigs/zeiss-corp-macbook-vm.yaml
cluster/kubeconfigs/development.yaml
cluster/kubeconfigs/production.yaml

The onboarding script combines them into:
cluster/merged/config

It then copies the generated configuration to:
~/.kube/config

This allows standard commands to work without manually setting the KUBECONFIG environment variable:
kubectl config get-contexts
kubectx production
k9s --context staging

The merged file is generated data and can be rebuilt from the individual files in cluster/kubeconfigs/.

Backups
Before replacing or rebuilding the active kubeconfig, the scripts should create backups under:
cluster/backups/

Example:
config-20260718-201500.yaml
production-20260718-202100.yaml
development-removed-20260718-203000.yaml

List backups:
ls -lah ~/k8s-lab/cluster/backups

Restore a previous active kubeconfig:
cp \
  ~/k8s-lab/cluster/backups/config-<timestamp>.yaml \
  ~/.kube/config

Set secure permissions:
chmod 600 ~/.kube/config

Verify:
kubectl config get-contexts


Removing a Cluster
Remove a locally onboarded cluster:
~/k8s-lab/cluster/remove-cluster.sh development

This should:
Back up the saved kubeconfig
Remove the cluster file from cluster/kubeconfigs/
Rebuild the merged kubeconfig
Update ~/.kube/config
Display the remaining contexts
Removing a local kubeconfig does not delete the actual Kubernetes cluster.
It only removes access to that cluster from the current workstation.

Networking Requirements
The Multipass VM must be able to reach each Kubernetes API server referenced by its kubeconfig.
Inspect the configured API servers:
grep -R 'server:' \
  ~/k8s-lab/cluster/kubeconfigs

Test connectivity:
kubectl \
  --context production \
  get --raw=/version \
  --request-timeout=10s

Test the API port directly:
nc -vz <api-server-host> <api-server-port>

Test HTTPS:
curl -kIv \
  https://<api-server-host>:<api-server-port>

Avoid kubeconfig server addresses such as:
https://127.0.0.1:6443
https://localhost:6443
https://host.docker.internal:6443

These addresses may only work from the machine where the kubeconfig was generated.
Use an IP address or DNS name reachable from the Multipass VM.

Rancher-Proxied Kubeconfigs
Rancher-generated kubeconfigs often use URLs such as:
https://192.168.178.59/k8s/clusters/local

or:
https://192.168.178.59/k8s/clusters/c-xxxxx

This means kubectl connects to Rancher first.
Rancher then proxies the request to the target cluster.
The communication path is:
kubectl
   |
   v
Rancher Manager
   |
   v
Rancher cluster agent
   |
   v
Downstream Kubernetes cluster

These kubeconfigs depend on:
Rancher Manager being available
The Rancher URL being reachable
The token still being valid
The downstream cluster agent being connected

Token Expiration
Rancher-generated kubeconfigs may include a TTL.
Example:
ttl: 2592000

This represents:
2,592,000 seconds
30 days

When the token expires, commands may return:
Unauthorized

or:
You must be logged in to the server

Download a new kubeconfig from Rancher and onboard it again using the same cluster name:
~/k8s-lab/cluster/onboard-cluster.sh \
  ~/Downloads/new-production.yml \
  production

The previous kubeconfig should be moved into the backups directory automatically.

Troubleshooting
Duplicate contexts
Example:
local
rancher
rancher-management-local
rancher-management-rancher

This means both the original kubeconfig and the normalized kubeconfig were merged.
The onboarding script should only merge files from:
cluster/kubeconfigs/

It should not merge directly from downloaded files or the previous ~/.kube/config.
Delete unwanted contexts:
kubectl config delete-context local
kubectl config delete-context rancher
kubectl config delete-context rancher-management-rancher

Rename the remaining context:
kubectl config rename-context \
  rancher-management-local \
  rancher-management

Verify:
kubectl config get-contexts


No current context
kubectl config get-contexts
kubectl config use-context <context-name>


Cluster is unreachable
Show the API URL for the current context:
kubectl config view \
  --minify \
  -o jsonpath='{.clusters[0].cluster.server}{"\n"}'

Check DNS:
getent hosts <api-server-host>

Check the port:
nc -vz <api-server-host> <port>

Test HTTPS:
curl -kIv https://<api-server-host>:<port>


Certificate error
Example:
x509: certificate is valid for another hostname

The kubeconfig API server address does not match the certificate Subject Alternative Names.
Use the correct API hostname or regenerate the API certificate with the required IP or DNS name.

Unauthorized
Example:
You must be logged in to the server

The token or client certificate may have expired or been revoked.
Download a fresh kubeconfig and onboard it again.

K9s opens the wrong cluster
Check the current context:
kubectl config current-context

Open the required cluster explicitly:
k9s --context production


Recommended Workflow
Before running any change:
kubectl config current-context
kubectl get nodes

Switch deliberately:
kubectx staging

Confirm:
kubectl config current-context
kubectl get nodes

For production operations, use explicit contexts:
kubectl \
  --context production \
  get pods -A

For Helm:
helm \
  --kube-context production \
  list -A

This reduces the risk of changing the wrong cluster.

Useful Shell Aliases
Add to ~/.bashrc:
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kgn='kubectl get nodes -o wide'
alias kctx='kubectx'
alias kns='kubens'
alias kcurrent='kubectl config current-context'
alias kcontexts='kubectl config get-contexts'

Reload:
source ~/.bashrc


Quick Reference
Onboard a cluster:
~/k8s-lab/cluster/onboard-cluster.sh \
  <kubeconfig-file> \
  <cluster-name>

Onboard and set as default:
~/k8s-lab/cluster/onboard-cluster.sh \
  <kubeconfig-file> \
  <cluster-name> \
  --default

List clusters:
kubectl config get-contexts

Show current cluster:
kubectl config current-context

Switch cluster:
kubectx <cluster-name>

Open K9s:
k9s --context <cluster-name>

Test connectivity:
kubectl \
  --context <cluster-name> \
  get --raw=/version

Remove local cluster access:
~/k8s-lab/cluster/remove-cluster.sh \
  <cluster-name>

Check Rancher agent:
kubectl \
  --context <cluster-name> \
  get pods \
  -n cattle-system


