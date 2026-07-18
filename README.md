```markdown
# k8s-lab

Kubernetes Cluster Management Toolkit

This repository provides a repeatable way to manage multiple Kubernetes clusters from a single Linux workstation or Multipass VM.

It supports:

- Rancher management clusters  
- Rancher downstream clusters  
- Rancher Desktop  
- K3s and RKE2  
- Development, staging, and production clusters  
- Any Kubernetes cluster with a reachable API server and valid kubeconfig  

The toolkit stores each cluster kubeconfig separately, creates a merged kubeconfig, and allows `kubectl`, `K9s`, `Helm`, and other Kubernetes tools to access all onboarded clusters.

---

## Repository Structure

```text
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
```

### Directory Purpose

| Directory                 | Purpose                                           |
|---------------------------|---------------------------------------------------|
| `cluster/kubeconfigs/`    | Stores one normalized kubeconfig per cluster      |
| `cluster/merged/`         | Stores the generated kubeconfig containing all    |
| `cluster/backups/`        | Stores previous kubeconfig versions for rollback  |
| `~/.kube/config`          | Active kubeconfig used by `kubectl`, `K9s`, `Helm`|

---

## Required Tools

Install the following tools in the Multipass VM:

- `kubectl`
- `helm`
- `k9s`
- `kubectx`
- `kubens`
- `stern`
- `jq`
- `yq`
- `curl`
- `git`

Verify installations:

```bash
kubectl version --client
helm version
k9s version
kubectx --version
kubens --version
stern --version
jq --version
yq --version
```

---

## Initial Setup

Create required directories:

```bash
mkdir -p ~/k8s-lab/cluster/{kubeconfigs,merged,backups}
```

Set secure permissions:

```bash
chmod 700 ~/k8s-lab/cluster
chmod 700 ~/k8s-lab/cluster/kubeconfigs
chmod 700 ~/k8s-lab/cluster/merged
chmod 700 ~/k8s-lab/cluster/backups
```

Make scripts executable:

```bash
chmod +x ~/k8s-lab/cluster/onboard-cluster.sh
chmod +x ~/k8s-lab/cluster/remove-cluster.sh
```

---

## Kubeconfig Security

Kubeconfig files can contain:

- Bearer tokens  
- Client private keys  
- Client certificates  
- Authentication plugins  
- Internal Kubernetes API addresses  

**Never commit real kubeconfig files to Git.**

Add this to `.gitignore`:

```gitignore
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
```

Recommended permissions:

```bash
chmod 700 ~/.kube
chmod 600 ~/.kube/config
chmod 600 ~/k8s-lab/cluster/kubeconfigs/*.yaml
```

Before pushing to Git:

```bash
git status
git diff --cached
git ls-files | grep -Ei 'kubeconfig|cluster/kubeconfigs|cluster/merged|cluster/backups'
```

Search for accidentally committed credentials:

```bash
git grep -nE 'client-key-data:|client-certificate-data:|token:|password:'
```

---

## Rancher Kubeconfig Behaviour

A kubeconfig downloaded from Rancher may contain multiple contexts, e.g.:

- `local`  
- `rancher`

or:

- `zeiss-corp-macbook-vm`  
- `rancher`

- The `rancher` context points to the Rancher API endpoint.
- The actual Kubernetes cluster context is normally:
  - `local` for the Rancher management cluster, or
  - a downstream cluster name such as `zeiss-corp-macbook-vm`.

The onboarding script should import **only** the actual Kubernetes cluster context and exclude the generic `rancher` context.

Otherwise, duplicate contexts can appear:

- `local`
- `rancher`
- `rancher-management-local`
- `rancher-management-rancher`

Desired result:

- `rancher-management`
- `zeiss-corp-macbook-vm`
- `development`
- `staging`
- `production`

---

## Inspecting a Downloaded Kubeconfig

List all contexts:

```bash
kubectl config get-contexts \
  --kubeconfig ~/Downloads/rancher-local.yml
```

List context names only:

```bash
kubectl config get-contexts \
  --kubeconfig ~/Downloads/rancher-local.yml \
  -o name
```

Show the current context:

```bash
kubectl config current-context \
  --kubeconfig ~/Downloads/rancher-local.yml
```

List configured API servers:

```bash
kubectl config view \
  --kubeconfig ~/Downloads/rancher-local.yml \
  -o jsonpath='{range .clusters[*]}{.name}{" => "}{.cluster.server}{"\n"}{end}'
```

---

## Onboarding a Cluster

Script usage:

```bash
onboard-cluster.sh <kubeconfig-file> <cluster-name> [--default]
```

Example:

```bash
~/k8s-lab/cluster/onboard-cluster.sh \
  ~/Downloads/rancher-local.yml \
  rancher-management \
  --default
```

- First argument: downloaded kubeconfig.
- Second argument: local name for the cluster.
- Script creates: `cluster/kubeconfigs/<cluster-name>.yaml` e.g.:

```text
cluster/kubeconfigs/rancher-management.yaml
```

The original downloaded file is not renamed; a normalized managed copy is created.

---

## Onboarding the Rancher Management Cluster

Download the local cluster kubeconfig from Rancher, then run:

```bash
~/k8s-lab/cluster/onboard-cluster.sh \
  ~/Downloads/rancher-local.yml \
  rancher-management \
  --default
```

Expected context:

```text
rancher-management
```

Verify:

```bash
kubectl config get-contexts
kubectl config current-context
kubectl get nodes
```

---

## Onboarding a Rancher Downstream Cluster

Download the downstream cluster kubeconfig from Rancher, then:

```bash
~/k8s-lab/cluster/onboard-cluster.sh \
  ~/Downloads/zeiss-corp-macbook-vm.yml \
  zeiss-corp-macbook-vm
```

Verify:

```bash
kubectl config get-contexts
```

Switch to it:

```bash
kubectl config use-context zeiss-corp-macbook-vm
```

Test access:

```bash
kubectl get nodes
kubectl get pods -A
```

---

## Onboarding Future Clusters

Development:

```bash
~/k8s-lab/cluster/onboard-cluster.sh \
  ~/Downloads/dev-kubeconfig.yml \
  development
```

Staging:

```bash
~/k8s-lab/cluster/onboard-cluster.sh \
  ~/Downloads/staging-kubeconfig.yml \
  staging
```

Production:

```bash
~/k8s-lab/cluster/onboard-cluster.sh \
  ~/Downloads/production-kubeconfig.yml \
  production
```

Set a newly onboarded cluster as default:

```bash
~/k8s-lab/cluster/onboard-cluster.sh \
  ~/Downloads/production-kubeconfig.yml \
  production \
  --default
```

---

## Listing Onboarded Clusters

List contexts:

```bash
kubectl config get-contexts
```

List context names only:

```bash
kubectl config get-contexts -o name
```

Show current context:

```bash
kubectl config current-context
```

List cluster records stored in kubeconfig:

```bash
kubectl config view \
  -o jsonpath='{range .clusters[*]}{.name}{"\n"}{end}'
```

List saved source kubeconfigs:

```bash
ls -lah ~/k8s-lab/cluster/kubeconfigs
```

List all cluster-management files:

```bash
find ~/k8s-lab/cluster \
  -maxdepth 2 \
  -type f \
  -print
```

---

## Switching Between Clusters

Using `kubectl`:

```bash
kubectl config use-context rancher-management
kubectl config use-context zeiss-corp-macbook-vm
kubectl config use-context development
kubectl config use-context staging
kubectl config use-context production
```

Using `kubectx`:

```bash
kubectx rancher-management
kubectx zeiss-corp-macbook-vm
kubectx development
kubectx staging
kubectx production
```

List available contexts:

```bash
kubectx
```

---

## Using K9s

Open the current cluster:

```bash
k9s
```

Open a specific cluster:

```bash
k9s --context rancher-management
k9s --context zeiss-corp-macbook-vm
k9s --context production
```

Switch contexts inside K9s:

```text
:contexts
```

Switch namespaces inside K9s:

```text
:namespaces
```

---

## Namespace Management

List namespaces:

```bash
kubectl get namespaces
```

Switch namespace:

```bash
kubens cattle-system
```

Return to default namespace:

```bash
kubens default
```

Run K9s in a namespace:

```bash
k9s --namespace cattle-system
```

---

## Common Kubernetes Commands

Check nodes:

```bash
kubectl get nodes -o wide
```

Check pods in all namespaces:

```bash
kubectl get pods -A
```

Check deployments:

```bash
kubectl get deployments -A
```

Check services:

```bash
kubectl get services -A
```

Check all common resources:

```bash
kubectl get all -A
```

Describe a resource:

```bash
kubectl describe pod <pod-name> -n <namespace>
```

Read logs:

```bash
kubectl logs <pod-name> -n <namespace>
```

Follow logs:

```bash
kubectl logs -f <pod-name> -n <namespace>
```

Execute a shell inside a pod:

```bash
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh
```

---

## Rancher Agent Commands

Check Rancher agents on a downstream cluster:

```bash
kubectl get pods -n cattle-system
```

Check the cluster agent:

```bash
kubectl get deployment \
  cattle-cluster-agent \
  -n cattle-system
```

Read cluster-agent logs:

```bash
kubectl logs \
  -n cattle-system \
  deployment/cattle-cluster-agent \
  --tail=100
```

Follow matching pod logs using Stern:

```bash
stern cattle-cluster-agent -n cattle-system
```

Healthy agent logs generally contain:

- `/ping is accessible`
- `Connecting to proxy`
- `Connected to proxy`

---

## Helm Usage

Always verify the current context before using Helm:

```bash
kubectl config current-context
```

List Helm releases:

```bash
helm list -A
```

Install a chart:

```bash
helm install <release-name> <chart> \
  --namespace <namespace> \
  --create-namespace
```

Upgrade a release:

```bash
helm upgrade <release-name> <chart> \
  --namespace <namespace>
```

Remove a release:

```bash
helm uninstall <release-name> \
  --namespace <namespace>
```

Target a specific cluster explicitly:

```bash
helm \
  --kube-context production \
  list -A
```

---

## Merged Kubeconfig

Each onboarded cluster has a separate source file:

```text
cluster/kubeconfigs/rancher-management.yaml
cluster/kubeconfigs/zeiss-corp-macbook-vm.yaml
cluster/kubeconfigs/development.yaml
cluster/kubeconfigs/production.yaml
```

The onboarding script combines them into:

```text
cluster/merged/config
```

Then copies the generated configuration to:

```text
~/.kube/config
```

This allows standard commands to work without manually setting `KUBECONFIG`:

```bash
kubectl config get-contexts
kubectx production
k9s --context staging
```

The merged file is generated data and can be rebuilt from the individual files in `cluster/kubeconfigs/`.

---

## Backups

Before replacing or rebuilding the active kubeconfig, the scripts should create backups under:

```text
cluster/backups/
```

Example backup filenames:

```text
config-20260718-201500.yaml
production-20260718-202100.yaml
development-removed-20260718-203000.yaml
```

List backups:

```bash
ls -lah ~/k8s-lab/cluster/backups
```

Restore a previous active kubeconfig:

```bash
cp \
  ~/k8s-lab/cluster/backups/config-<timestamp>.yaml \
  ~/.kube/config
```

Set secure permissions:

```bash
chmod 600 ~/.kube/config
```

Verify:

```bash
kubectl config get-contexts
```

---

## Removing a Cluster

Remove a locally onboarded cluster:

```bash
~/k8s-lab/cluster/remove-cluster.sh development
```

This should:

1. Back up the saved kubeconfig.  
2. Remove the cluster file from `cluster/kubeconfigs/`.  
3. Rebuild the merged kubeconfig.  
4. Update `~/.kube/config`.  
5. Display the remaining contexts.

Removing a local kubeconfig **does not** delete the actual Kubernetes cluster; it only removes access from the current workstation.

---

## Networking Requirements

The Multipass VM must be able to reach each Kubernetes API server referenced by its kubeconfig.

Inspect configured API servers:

```bash
grep -R 'server:' ~/k8s-lab/cluster/kubeconfigs
```

Test connectivity:

```bash
kubectl \
  --context production \
  get --raw=/version \
  --request-timeout=10s
```

Test API port directly:

```bash
nc -vz <api-server-host> <api-server-port>
```

Test HTTPS:

```bash
curl -kIv https://<api-server-host>:<api-server-port>
```

Avoid kubeconfig server addresses such as:

- `https://127.0.0.1:6443`
- `https://localhost:6443`
- `https://host.docker.internal:6443`

These may only work from the machine where the kubeconfig was generated. Use an IP or DNS name reachable from the Multipass VM.

---

## Rancher-Proxied Kubeconfigs

Rancher-generated kubeconfigs often use URLs such as:

```text
https://192.168.178.59/k8s/clusters/local
https://192.168.178.59/k8s/clusters/c-xxxxx
```

Communication path:

```text
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
```

These kubeconfigs depend on:

- Rancher Manager being available  
- Rancher URL being reachable  
- Token still being valid  
- Downstream cluster agent being connected  

---

## Token Expiration

Rancher-generated kubeconfigs may include a TTL, e.g.:

```yaml
ttl: 2592000
```

This represents:

- `2,592,000` seconds  
- `30` days  

When the token expires, commands may return:

- `Unauthorized`
- `You must be logged in to the server`

Download a new kubeconfig from Rancher and onboard it again using the same cluster name:

```bash
~/k8s-lab/cluster/onboard-cluster.sh \
  ~/Downloads/new-production.yml \
  production
```

The previous kubeconfig should be moved into the backups directory automatically.

---

## Troubleshooting

### Duplicate contexts

Example:

```text
local
rancher
rancher-management-local
rancher-management-rancher
```

This means both the original kubeconfig and the normalized kubeconfig were merged.

The onboarding script should only merge files from:

```text
cluster/kubeconfigs/
```

It should **not** merge directly from downloaded files or the previous `~/.kube/config`.

Delete unwanted contexts:

```bash
kubectl config delete-context local
kubectl config delete-context rancher
kubectl config delete-context rancher-management-rancher
```

Rename remaining context:

```bash
kubectl config rename-context \
  rancher-management-local \
  rancher-management
```

Verify:

```bash
kubectl config get-contexts
```

### No current context

```bash
kubectl config get-contexts
kubectl config use-context <context-name>
```

### Cluster is unreachable

Show the API URL for the current context:

```bash
kubectl config view \
  --minify \
  -o jsonpath='{.clusters[0].cluster.server}{"\n"}'
```

Check DNS:

```bash
getent hosts <api-server-host>
```

Check the port:

```bash
nc -vz <api-server-host> <port>
```

Test HTTPS:

```bash
curl -kIv https://<api-server-host>:<port>
```

### Certificate error

Example:

```text
x509: certificate is valid for another hostname
```

The kubeconfig API server address does not match the certificate SANs. Use the correct API hostname or regenerate the API certificate with the required IP or DNS name.

### Unauthorized

Example:

```text
You must be logged in to the server
```

The token or client certificate may have expired or been revoked. Download a fresh kubeconfig and onboard it again.

### K9s opens the wrong cluster

Check current context:

```bash
kubectl config current-context
```

Open required cluster explicitly:

```bash
k9s --context production
```

---

## Recommended Workflow

Before running any change:

```bash
kubectl config current-context
kubectl get nodes
```

Switch deliberately:

```bash
kubectx staging
```

Confirm:

```bash
kubectl config current-context
kubectl get nodes
```

For production operations, use explicit contexts:

```bash
kubectl \
  --context production \
  get pods -A
```

For Helm:

```bash
helm \
  --kube-context production \
  list -A
```

This reduces the risk of changing the wrong cluster.

---

## Useful Shell Aliases

Add to `~/.bashrc`:

```bash
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kgn='kubectl get nodes -o wide'
alias kctx='kubectx'
alias kns='kubens'
alias kcurrent='kubectl config current-context'
alias kcontexts='kubectl config get-contexts'
```

Reload:

```bash
source ~/.bashrc
```

---

## Quick Reference

Onboard a cluster:

```bash
~/k8s-lab/cluster/onboard-cluster.sh \
  <kubeconfig-file> \
  <cluster-name>
```

Onboard and set as default:

```bash
~/k8s-lab/cluster/onboard-cluster.sh \
  <kubeconfig-file> \
  <cluster-name> \
  --default
```

List clusters:

```bash
kubectl config get-contexts
```

Show current cluster:

```bash
kubectl config current-context
```

Switch cluster:

```bash
kubectx <cluster-name>
```

Open K9s:

```bash
k9s --context <cluster-name>
```

Test connectivity:

```bash
kubectl \
  --context <cluster-name> \
  get --raw=/version
```

Remove local cluster access:

```bash
~/k8s-lab/cluster/remove-cluster.sh \
  <cluster-name>
```

Check Rancher agent:

```bash
kubectl \
  --context <cluster-name> \
  get pods \
  -n cattle-system
```
```
