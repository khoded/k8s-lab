#!/usr/bin/env bash

set -euo pipefail

# Reload shell configuration
if [[ -f "$HOME/.bashrc" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.bashrc"
fi

echo "=== Kubernetes Tool Versions ==="

check_version() {
  local name="$1"
  shift

  echo
  echo "--- $name ---"

  if command -v "$name" >/dev/null 2>&1; then
    "$@" || echo "Warning: failed to get $name version"
  else
    echo "$name is not installed or not available in PATH"
  fi
}

check_version kubectl kubectl version --client
check_version helm helm version
check_version k9s k9s version
check_version stern stern --version
check_version yq yq --version
check_version rancher rancher --version
