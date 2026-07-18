#!/usr/bin/env bash
set -Eeuo pipefail

CLUSTER_HOME="${HOME}/k8s-lab/cluster"
CONFIG_DIR="${CLUSTER_HOME}/kubeconfigs"
MERGED_DIR="${CLUSTER_HOME}/merged"
BACKUP_DIR="${CLUSTER_HOME}/backups"
DEFAULT_CONFIG="${HOME}/.kube/config"
MERGED_CONFIG="${MERGED_DIR}/config"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ $# -eq 1 ]] ||
  fail "Usage: $(basename "$0") <cluster-name>"

CLUSTER_NAME="$(
  printf '%s' "$1" |
    tr '[:upper:]' '[:lower:]' |
    sed -E \
      -e 's/[^a-z0-9._-]+/-/g' \
      -e 's/^-+//' \
      -e 's/-+$//'
)"

TARGET="${CONFIG_DIR}/${CLUSTER_NAME}.yaml"

[[ -f "$TARGET" ]] ||
  fail "Cluster not found: ${CLUSTER_NAME}"

mkdir -p "$BACKUP_DIR" "$MERGED_DIR" "${HOME}/.kube"

timestamp="$(date '+%Y%m%d-%H%M%S')"

cp \
  "$TARGET" \
  "${BACKUP_DIR}/${CLUSTER_NAME}-removed-${timestamp}.yaml"

rm -f "$TARGET"

mapfile -t files < <(
  find "$CONFIG_DIR" \
    -maxdepth 1 \
    -type f \
    \( -name '*.yaml' -o -name '*.yml' \) \
    -print |
    sort
)

if [[ "${#files[@]}" -eq 0 ]]; then
  rm -f "$MERGED_CONFIG" "$DEFAULT_CONFIG"
  echo "Removed ${CLUSTER_NAME}. No clusters remain."
  exit 0
fi

joined="$(
  IFS=:
  printf '%s' "${files[*]}"
)"

KUBECONFIG="$joined" \
  kubectl config view \
    --raw \
    --flatten > "$MERGED_CONFIG"

chmod 600 "$MERGED_CONFIG"

cp "$MERGED_CONFIG" "$DEFAULT_CONFIG"
chmod 600 "$DEFAULT_CONFIG"

echo "Removed cluster: ${CLUSTER_NAME}"
kubectl config get-contexts
