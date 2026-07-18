#!/usr/bin/env bash
set -Eeuo pipefail

BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'

log() {
  printf "\n${BLUE}==> %s${RESET}\n" "$1"
}

warn() {
  printf "${YELLOW}WARNING: %s${RESET}\n" "$1"
}

fail() {
  printf "${RED}ERROR: %s${RESET}\n" "$1" >&2
  exit 1
}

install_binary() {
  local source_file="$1"
  local target_name="$2"

  sudo install \
    -o root \
    -g root \
    -m 0755 \
    "$source_file" \
    "/usr/local/bin/$target_name"
}

latest_github_tag() {
  local repository="$1"

  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${repository}/releases/latest" |
    jq -r '.tag_name'
}

github_asset_url() {
  local repository="$1"
  local pattern="$2"

  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${repository}/releases/latest" |
    jq -r --arg pattern "$pattern" '
      .assets[]
      | select(.name | test($pattern))
      | .browser_download_url
    ' |
    head -n1
}

if [[ $EUID -eq 0 ]]; then
  fail "Run this script as your normal Ubuntu user, not with sudo."
fi

case "$(uname -m)" in
  x86_64)
    GO_ARCH="amd64"
    K9S_ARCH="amd64"
    HELM_ARCH="amd64"
    YQ_ARCH="amd64"
    STERN_ARCH="amd64"
    RANCHER_ARCH="amd64"
    ;;
  aarch64 | arm64)
    GO_ARCH="arm64"
    K9S_ARCH="arm64"
    HELM_ARCH="arm64"
    YQ_ARCH="arm64"
    STERN_ARCH="arm64"
    RANCHER_ARCH="arm64"
    ;;
  *)
    fail "Unsupported architecture: $(uname -m)"
    ;;
esac

WORKDIR="$(mktemp -d)"

cleanup() {
  rm -rf "$WORKDIR"
}

trap cleanup EXIT

log "Installing base packages"

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  bash-completion \
  ca-certificates \
  curl \
  dnsutils \
  fzf \
  git \
  gnupg \
  jq \
  less \
  make \
  netcat-openbsd \
  openssl \
  procps \
  ripgrep \
  tar \
  unzip \
  vim \
  wget

log "Installing kubectl"

KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
KUBECTL_URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${GO_ARCH}/kubectl"

curl -fsSL "$KUBECTL_URL" -o "$WORKDIR/kubectl"
curl -fsSL "${KUBECTL_URL}.sha256" -o "$WORKDIR/kubectl.sha256"

echo "$(cat "$WORKDIR/kubectl.sha256")  $WORKDIR/kubectl" |
  sha256sum --check --status ||
  fail "kubectl checksum validation failed"

install_binary "$WORKDIR/kubectl" kubectl

log "Installing Helm"

HELM_VERSION="$(latest_github_tag helm/helm)"
HELM_ARCHIVE="helm-${HELM_VERSION}-linux-${HELM_ARCH}.tar.gz"

curl -fsSL \
  "https://get.helm.sh/${HELM_ARCHIVE}" \
  -o "$WORKDIR/$HELM_ARCHIVE"

tar -xzf "$WORKDIR/$HELM_ARCHIVE" -C "$WORKDIR"

install_binary \
  "$WORKDIR/linux-${HELM_ARCH}/helm" \
  helm

log "Installing K9s"

K9S_VERSION="$(latest_github_tag derailed/k9s)"
K9S_ARCHIVE="k9s_Linux_${K9S_ARCH}.tar.gz"

curl -fsSL \
  "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/${K9S_ARCHIVE}" \
  -o "$WORKDIR/$K9S_ARCHIVE"

mkdir -p "$WORKDIR/k9s"
tar -xzf "$WORKDIR/$K9S_ARCHIVE" -C "$WORKDIR/k9s"

install_binary "$WORKDIR/k9s/k9s" k9s

log "Installing yq"

YQ_VERSION="$(latest_github_tag mikefarah/yq)"

curl -fsSL \
  "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${YQ_ARCH}" \
  -o "$WORKDIR/yq"

install_binary "$WORKDIR/yq" yq

log "Installing Stern"

STERN_VERSION="$(latest_github_tag stern/stern)"
STERN_ARCHIVE="stern_${STERN_VERSION#v}_linux_${STERN_ARCH}.tar.gz"

curl -fsSL \
  "https://github.com/stern/stern/releases/download/${STERN_VERSION}/${STERN_ARCHIVE}" \
  -o "$WORKDIR/$STERN_ARCHIVE"

mkdir -p "$WORKDIR/stern"
tar -xzf "$WORKDIR/$STERN_ARCHIVE" -C "$WORKDIR/stern"

install_binary "$WORKDIR/stern/stern" stern

log "Installing kubectx and kubens"

KUBECTX_VERSION="$(latest_github_tag ahmetb/kubectx)"

curl -fsSL \
  "https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubectx_${KUBECTX_VERSION}_linux_${GO_ARCH}.tar.gz" \
  -o "$WORKDIR/kubectx.tar.gz"

curl -fsSL \
  "https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubens_${KUBECTX_VERSION}_linux_${GO_ARCH}.tar.gz" \
  -o "$WORKDIR/kubens.tar.gz"

mkdir -p "$WORKDIR/kubectx" "$WORKDIR/kubens"

tar -xzf "$WORKDIR/kubectx.tar.gz" -C "$WORKDIR/kubectx"
tar -xzf "$WORKDIR/kubens.tar.gz" -C "$WORKDIR/kubens"

install_binary "$WORKDIR/kubectx/kubectx" kubectx
install_binary "$WORKDIR/kubens/kubens" kubens

log "Installing Rancher CLI"

RANCHER_URL="$(
  github_asset_url \
    rancher/cli \
    "rancher-linux-${RANCHER_ARCH}.*\\.tar\\.gz$"
)"

if [[ -n "$RANCHER_URL" && "$RANCHER_URL" != "null" ]]; then
  curl -fsSL "$RANCHER_URL" -o "$WORKDIR/rancher-cli.tar.gz"

  mkdir -p "$WORKDIR/rancher-cli"
  tar -xzf \
    "$WORKDIR/rancher-cli.tar.gz" \
    -C "$WORKDIR/rancher-cli"

  RANCHER_BINARY="$(
    find "$WORKDIR/rancher-cli" \
      -type f \
      -name rancher \
      | head -n1
  )"

  if [[ -n "$RANCHER_BINARY" ]]; then
    install_binary "$RANCHER_BINARY" rancher
  else
    warn "Rancher CLI archive did not contain a rancher binary."
  fi
else
  warn "Could not locate a compatible Rancher CLI release."
  warn "You can download the matching CLI from the Rancher UI later."
fi

log "Creating Kubernetes configuration directories"

mkdir -p \
  "$HOME/.kube" \
  "$HOME/.config/k9s"

chmod 700 "$HOME/.kube"

log "Installing Bash completions"

sudo mkdir -p /etc/bash_completion.d

kubectl completion bash |
  sudo tee /etc/bash_completion.d/kubectl >/dev/null

helm completion bash |
  sudo tee /etc/bash_completion.d/helm >/dev/null

k9s completion bash |
  sudo tee /etc/bash_completion.d/k9s >/dev/null

if command -v rancher >/dev/null 2>&1; then
  rancher completion bash 2>/dev/null |
    sudo tee /etc/bash_completion.d/rancher >/dev/null ||
    true
fi

log "Adding shell aliases"

SHELL_CONFIG="$HOME/.bashrc"
START_MARKER="# BEGIN KUBERNETES TOOLKIT"
END_MARKER="# END KUBERNETES TOOLKIT"

if grep -qF "$START_MARKER" "$SHELL_CONFIG" 2>/dev/null; then
  sed -i \
    "/$START_MARKER/,/$END_MARKER/d" \
    "$SHELL_CONFIG"
fi

cat >> "$SHELL_CONFIG" <<'EOF'

# BEGIN KUBERNETES TOOLKIT
source /usr/share/bash-completion/bash_completion 2>/dev/null || true

alias k='kubectl'
alias kg='kubectl get'
alias kd='kubectl describe'
alias kdel='kubectl delete'
alias ka='kubectl apply -f'
alias kaf='kubectl apply -f'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods --all-namespaces'
alias kgpw='kubectl get pods --watch'
alias kgs='kubectl get services'
alias kgd='kubectl get deployments'
alias kgn='kubectl get nodes -o wide'
alias kga='kubectl get all'
alias kgaa='kubectl get all --all-namespaces'
alias kctx='kubectx'
alias kns='kubens'
alias klogs='kubectl logs'
alias kexec='kubectl exec -it'
alias kuse='kubectl config use-context'
alias kcontexts='kubectl config get-contexts'

complete -o default -F __start_kubectl k
# END KUBERNETES TOOLKIT
EOF

log "Checking installed tools"

printf "\n%-18s %s\n" "Tool" "Version"
printf "%-18s %s\n" "------------------" "------------------------------"

printf "%-18s %s\n" \
  "kubectl" \
  "$(kubectl version --client --output=yaml 2>/dev/null |
      yq '.clientVersion.gitVersion')"

printf "%-18s %s\n" \
  "helm" \
  "$(helm version --short 2>/dev/null)"

printf "%-18s %s\n" \
  "k9s" \
  "$(k9s version --short 2>/dev/null || k9s version 2>/dev/null |
      head -n1)"

printf "%-18s %s\n" \
  "yq" \
  "$(yq --version 2>/dev/null)"

printf "%-18s %s\n" \
  "stern" \
  "$(stern --version 2>/dev/null)"

printf "%-18s %s\n" \
  "kubectx" \
  "$(kubectx --version 2>/dev/null || echo installed)"

printf "%-18s %s\n" \
  "kubens" \
  "$(kubens --version 2>/dev/null || echo installed)"

if command -v rancher >/dev/null 2>&1; then
  printf "%-18s %s\n" \
    "rancher" \
    "$(rancher --version 2>/dev/null)"
else
  printf "%-18s %s\n" \
    "rancher" \
    "not installed"
fi

echo
echo "============================================================"
echo " Kubernetes toolkit installation completed"
echo "============================================================"
echo
echo "Reload your shell:"
echo "  source ~/.bashrc"
echo
echo "The tools are installed, but kubectl still needs kubeconfig."
echo
echo "Recommended kubeconfig location:"
echo "  ~/.kube/config"
echo
echo "After adding kubeconfig:"
echo "  kubectl config get-contexts"
echo "  kubectl get nodes"
echo "  k9s"
echo
echo "Rancher Manager container shortcut:"
echo "  sudo docker exec rancher kubectl get nodes"
echo
echo "============================================================"
