#!/usr/bin/env bash
set -Eeuo pipefail

CLUSTER_HOME="${HOME}/k8s-lab/cluster"
CONFIG_DIR="${CLUSTER_HOME}/kubeconfigs"
MERGED_DIR="${CLUSTER_HOME}/merged"
BACKUP_DIR="${CLUSTER_HOME}/backups"
DEFAULT_CONFIG="${HOME}/.kube/config"
MERGED_CONFIG="${MERGED_DIR}/config"

BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'

log() {
  printf "\n${BLUE}==> %s${RESET}\n" "$1"
}

success() {
  printf "${GREEN}%s${RESET}\n" "$1"
}

warn() {
  printf "${YELLOW}WARNING: %s${RESET}\n" "$1"
}

fail() {
  printf "${RED}ERROR: %s${RESET}\n" "$1" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  $(basename "$0") <kubeconfig-file> <cluster-name> [--default]

Examples:
  $(basename "$0") ~/Downloads/local.yaml rancher-management
  $(basename "$0") ~/Downloads/desktop.yaml rancher-desktop --default
  $(basename "$0") /tmp/prod-kubeconfig.yaml production
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    fail "Required command not found: $1"
}

sanitize_name() {
  local name="$1"

  printf '%s' "$name" |
    tr '[:upper:]' '[:lower:]' |
    sed -E \
      -e 's/[^a-z0-9._-]+/-/g' \
      -e 's/^-+//' \
      -e 's/-+$//'
}

validate_kubeconfig() {
  local file="$1"

  [[ -f "$file" ]] ||
    fail "Kubeconfig not found: $file"

  [[ -s "$file" ]] ||
    fail "Kubeconfig is empty: $file"

  KUBECONFIG="$file" \
    kubectl config view --raw >/dev/null 2>&1 ||
    fail "Invalid kubeconfig: $file"

  local contexts
  contexts="$(
    KUBECONFIG="$file" \
      kubectl config get-contexts -o name
  )"

  [[ -n "$contexts" ]] ||
    fail "No contexts found in kubeconfig: $file"
}

rename_all_entries() {
  local file="$1"
  local prefix="$2"

  mapfile -t contexts < <(
    KUBECONFIG="$file" \
      kubectl config get-contexts -o name
  )

  mapfile -t clusters < <(
    KUBECONFIG="$file" \
      kubectl config view \
      -o jsonpath='{range .clusters[*]}{.name}{"\n"}{end}'
  )

  mapfile -t users < <(
    KUBECONFIG="$file" \
      kubectl config view \
      -o jsonpath='{range .users[*]}{.name}{"\n"}{end}'
  )

  if [[ "${#contexts[@]}" -eq 1 ]]; then
    local old_context="${contexts[0]}"

    if [[ "$old_context" != "$prefix" ]]; then
      KUBECONFIG="$file" \
        kubectl config rename-context \
        "$old_context" \
        "$prefix" >/dev/null
    fi
  else
    for old_context in "${contexts[@]}"; do
      [[ -z "$old_context" ]] && continue

      local suffix
      suffix="$(sanitize_name "$old_context")"

      KUBECONFIG="$file" \
        kubectl config rename-context \
        "$old_context" \
        "${prefix}-${suffix}" >/dev/null
    done
  fi

  for old_cluster in "${clusters[@]}"; do
    [[ -z "$old_cluster" ]] && continue

    local new_cluster="${prefix}-cluster"

    if [[ "${#clusters[@]}" -gt 1 ]]; then
      new_cluster="${prefix}-cluster-$(sanitize_name "$old_cluster")"
    fi

    kubectl config \
      --kubeconfig "$file" \
      set-cluster "$new_cluster" \
      --server="$(
        kubectl config \
          --kubeconfig "$file" \
          view \
          --raw \
          -o jsonpath="{.clusters[?(@.name==\"${old_cluster}\")].cluster.server}"
      )" >/dev/null 2>&1 || true
  done

  # Context names are the important globally unique identifiers.
  # Cluster and user names may remain unchanged because flattening
  # preserves referenced data, but context collisions are prevented.
}

backup_existing_config() {
  if [[ -f "$DEFAULT_CONFIG" ]]; then
    local timestamp
    timestamp="$(date '+%Y%m%d-%H%M%S')"

    cp \
      "$DEFAULT_CONFIG" \
      "${BACKUP_DIR}/config-${timestamp}.yaml"

    chmod 600 \
      "${BACKUP_DIR}/config-${timestamp}.yaml"
  fi
}

merge_all_configs() {
  mapfile -t config_files < <(
    find "$CONFIG_DIR" \
      -maxdepth 1 \
      -type f \
      \( -name '*.yaml' -o -name '*.yml' \) \
      -print |
      sort
  )

  [[ "${#config_files[@]}" -gt 0 ]] ||
    fail "No kubeconfig files found in $CONFIG_DIR"

  local joined
  joined="$(
    IFS=:
    printf '%s' "${config_files[*]}"
  )"

  KUBECONFIG="$joined" \
    kubectl config view \
      --raw \
      --flatten > "$MERGED_CONFIG"

  chmod 600 "$MERGED_CONFIG"

  cp "$MERGED_CONFIG" "$DEFAULT_CONFIG"
  chmod 600 "$DEFAULT_CONFIG"
}

test_contexts() {
  mapfile -t contexts < <(
    kubectl \
      --kubeconfig "$DEFAULT_CONFIG" \
      config get-contexts -o name
  )

  for context in "${contexts[@]}"; do
    printf "\nTesting %-35s " "$context"

    if kubectl \
      --kubeconfig "$DEFAULT_CONFIG" \
      --context "$context" \
      get --raw='/version' \
      --request-timeout=10s >/dev/null 2>&1; then
      printf "${GREEN}reachable${RESET}\n"
    else
      printf "${YELLOW}unreachable${RESET}\n"
    fi
  done
}

require_command kubectl

[[ $# -ge 2 ]] || {
  usage
  exit 1
}

SOURCE_FILE="$1"
REQUESTED_NAME="$2"
DEFAULT_REQUESTED=false

if [[ "${3:-}" == "--default" ]]; then
  DEFAULT_REQUESTED=true
fi

CLUSTER_NAME="$(sanitize_name "$REQUESTED_NAME")"

[[ -n "$CLUSTER_NAME" ]] ||
  fail "Invalid cluster name: $REQUESTED_NAME"

mkdir -p \
  "$CONFIG_DIR" \
  "$MERGED_DIR" \
  "$BACKUP_DIR" \
  "${HOME}/.kube"

chmod 700 \
  "$CLUSTER_HOME" \
  "$CONFIG_DIR" \
  "$MERGED_DIR" \
  "$BACKUP_DIR" \
  "${HOME}/.kube"

SOURCE_FILE="$(
  realpath "$SOURCE_FILE"
)"

validate_kubeconfig "$SOURCE_FILE"

DESTINATION="${CONFIG_DIR}/${CLUSTER_NAME}.yaml"
TEMP_FILE="$(mktemp)"

trap 'rm -f "$TEMP_FILE"' EXIT

log "Preparing kubeconfig for ${CLUSTER_NAME}"

cp "$SOURCE_FILE" "$TEMP_FILE"
chmod 600 "$TEMP_FILE"

rename_all_entries "$TEMP_FILE" "$CLUSTER_NAME"

validate_kubeconfig "$TEMP_FILE"

if [[ -f "$DESTINATION" ]]; then
  timestamp="$(date '+%Y%m%d-%H%M%S')"

  cp \
    "$DESTINATION" \
    "${BACKUP_DIR}/${CLUSTER_NAME}-${timestamp}.yaml"

  warn "Replacing existing cluster configuration: ${CLUSTER_NAME}"
fi

cp "$TEMP_FILE" "$DESTINATION"
chmod 600 "$DESTINATION"

log "Backing up current merged kubeconfig"

backup_existing_config

log "Merging all registered clusters"

merge_all_configs

mapfile -t imported_contexts < <(
  KUBECONFIG="$DESTINATION" \
    kubectl config get-contexts -o name
)

if [[ "${#imported_contexts[@]}" -eq 0 ]]; then
  fail "No imported contexts found."
fi

PRIMARY_CONTEXT="${imported_contexts[0]}"

if [[ "$DEFAULT_REQUESTED" == true ]]; then
  log "Setting default context to ${PRIMARY_CONTEXT}"

  kubectl \
    --kubeconfig "$DEFAULT_CONFIG" \
    config use-context "$PRIMARY_CONTEXT" >/dev/null
fi

log "Registered contexts"

kubectl \
  --kubeconfig "$DEFAULT_CONFIG" \
  config get-contexts

log "Connectivity check"

test_contexts

echo
echo "============================================================"
echo " Cluster onboarded"
echo "============================================================"
echo
echo "Name:"
echo "  ${CLUSTER_NAME}"
echo
echo "Stored kubeconfig:"
echo "  ${DESTINATION}"
echo
echo "Imported context(s):"

for context in "${imported_contexts[@]}"; do
  echo "  ${context}"
done

echo
echo "Use cluster:"
echo "  kubectl config use-context ${PRIMARY_CONTEXT}"
echo
echo "Open with K9s:"
echo "  k9s --context ${PRIMARY_CONTEXT}"
echo
echo "All clusters:"
echo "  kubectl config get-contexts"
echo
echo "============================================================"
