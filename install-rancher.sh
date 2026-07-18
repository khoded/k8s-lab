#!/usr/bin/env bash
set -Eeuo pipefail

RANCHER_CONTAINER="rancher"
RANCHER_VOLUME="rancher-data"

log() {
  printf '\n\033[1;34m==> %s\033[0m\n' "$1"
}

fail() {
  printf '\n\033[1;31mERROR: %s\033[0m\n' "$1" >&2
  exit 1
}

if [[ $EUID -eq 0 ]]; then
  fail "Run this script as your normal Ubuntu user, not with sudo."
fi

log "Detecting the VM's active internet-facing IP"

DEFAULT_INTERFACE="$(
  ip route get 1.1.1.1 2>/dev/null |
    awk '{for (i=1; i<=NF; i++) if ($i=="dev") print $(i+1)}' |
    head -n1
)"

VM_IP="$(
  ip route get 1.1.1.1 2>/dev/null |
    awk '{for (i=1; i<=NF; i++) if ($i=="src") print $(i+1)}' |
    head -n1
)"

if [[ -z "${DEFAULT_INTERFACE}" || -z "${VM_IP}" ]]; then
  fail "Could not determine the active interface or VM IP."
fi

echo "Active interface: ${DEFAULT_INTERFACE}"
echo "Detected VM IP:   ${VM_IP}"

log "Checking internet connectivity"

if ! curl -fsI --connect-timeout 10 https://download.docker.com >/dev/null; then
  fail "Internet access is unavailable. Check the VM's default route first."
fi

log "Installing Docker prerequisites"

sudo apt-get update
sudo apt-get install -y ca-certificates curl

log "Configuring Docker's official Ubuntu repository"

sudo install -m 0755 -d /etc/apt/keyrings

sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc

sudo chmod a+r /etc/apt/keyrings/docker.asc

ARCH="$(dpkg --print-architecture)"
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"

echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable" |
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

log "Installing Docker Engine"

sudo apt-get update
sudo apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

sudo systemctl enable --now docker

log "Adding ${USER} to the docker group"

sudo usermod -aG docker "${USER}"

log "Testing Docker"

sudo docker run --rm hello-world >/dev/null

log "Creating persistent Rancher storage"

sudo docker volume create "${RANCHER_VOLUME}" >/dev/null

if sudo docker container inspect "${RANCHER_CONTAINER}" >/dev/null 2>&1; then
  log "Removing an existing Rancher container"
  sudo docker rm -f "${RANCHER_CONTAINER}" >/dev/null
fi

log "Starting Rancher Server"

sudo docker run -d \
  --name "${RANCHER_CONTAINER}" \
  --restart unless-stopped \
  --privileged \
  -p 80:80 \
  -p 443:443 \
  -v "${RANCHER_VOLUME}:/var/lib/rancher" \
  rancher/rancher:latest >/dev/null

log "Waiting for Rancher to become available"

READY=false

for attempt in $(seq 1 60); do
  if curl -ksSf --connect-timeout 5 https://127.0.0.1/ping 2>/dev/null |
    grep -q "pong"; then
    READY=true
    break
  fi

  if ! sudo docker ps --format '{{.Names}}' | grep -qx "${RANCHER_CONTAINER}"; then
    echo
    sudo docker logs --tail 100 "${RANCHER_CONTAINER}" || true
    fail "The Rancher container stopped unexpectedly."
  fi

  printf '.'
  sleep 5
done

echo

if [[ "${READY}" != "true" ]]; then
  sudo docker logs --tail 100 "${RANCHER_CONTAINER}" || true
  fail "Rancher did not become ready."
fi

BOOTSTRAP_PASSWORD="$(
  sudo docker logs "${RANCHER_CONTAINER}" 2>&1 |
    sed -n 's/.*Bootstrap Password: //p' |
    tail -n1
)"

if [[ -z "${BOOTSTRAP_PASSWORD}" ]]; then
  BOOTSTRAP_PASSWORD="$(
    sudo docker exec "${RANCHER_CONTAINER}" reset-password 2>/dev/null |
      sed -n 's/.*New password for default administrator (user-.*): //p' |
      tail -n1
  )"
fi

echo
echo "============================================================"
echo " Rancher installation completed"
echo "============================================================"
echo
echo "VM IP:              ${VM_IP}"
echo "Rancher URL:        https://${VM_IP}"
echo "Bootstrap password: ${BOOTSTRAP_PASSWORD:-Check: sudo docker logs rancher}"
echo
echo "Open the Rancher URL from your Mac browser."
echo "Accept the local self-signed certificate warning."
echo
echo "Reconnect to the VM before running Docker without sudo:"
echo "  exit"
echo "  multipass shell engaging-silverfish"
echo
echo "Then verify:"
echo "  docker ps"
echo "  curl -k https://localhost/ping"
echo "============================================================"
