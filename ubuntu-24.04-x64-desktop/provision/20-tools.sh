#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

USER_NAME="syselement"
MARKER="/var/lib/provision/20-tools.done"
LOG="/var/log/provision-20-tools.log"

mkdir -p /var/lib/provision
exec > >(tee -a "$LOG") 2>&1

if [[ -f "$MARKER" ]]; then
  echo "[20-tools] already applied: $MARKER"
  exit 0
fi

echo "[20-tools] start: $(date -Is)"

# Detect codename/arch for repos
CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
ARCH="$(dpkg --print-architecture)"

# --- Docker Engine (official repo) ---
echo "[20-tools] install docker"
install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi

cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable
EOF

apt-get update -y
apt-get install -y --no-install-recommends \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

# Add user to docker group (requires re-login to apply)
if id "$USER_NAME" >/dev/null 2>&1; then
  usermod -aG docker "$USER_NAME" || true
fi

# --- OpenTofu (official repo) ---
echo "[20-tools] install opentofu"
if [[ ! -f /etc/apt/keyrings/opentofu.gpg ]]; then
  curl -fsSL https://get.opentofu.org/opentofu.gpg | gpg --dearmor -o /etc/apt/keyrings/opentofu.gpg
  chmod a+r /etc/apt/keyrings/opentofu.gpg
fi

cat > /etc/apt/sources.list.d/opentofu.list <<EOF
deb [signed-by=/etc/apt/keyrings/opentofu.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main
EOF

apt-get update -y
apt-get install -y --no-install-recommends tofu

# --- Ansible (PPA) ---
echo "[20-tools] install ansible"
add-apt-repository --yes --update ppa:ansible/ansible
apt-get install -y --no-install-recommends ansible

# --- Packer (binary install) ---
echo "[20-tools] install packer"
PACKER_VERSION="1.14.3"
if ! command -v packer >/dev/null 2>&1 || [[ "$(packer --version 2>/dev/null || true)" != "$PACKER_VERSION" ]]; then
  tmpdir="$(mktemp -d)"
  pushd "$tmpdir" >/dev/null
  curl -fsSLO "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_${ARCH}.zip"
  unzip -o "packer_${PACKER_VERSION}_linux_${ARCH}.zip"
  install -m 0755 packer /usr/local/bin/packer
  popd >/dev/null
  rm -rf "$tmpdir"
fi

# --- VS Code (.deb) ---
echo "[20-tools] install vscode"
if ! command -v code >/dev/null 2>&1; then
  tmpdir="$(mktemp -d)"
  pushd "$tmpdir" >/dev/null
  curl -fsSLo code.deb "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
  apt-get install -y ./code.deb
  popd >/dev/null
  rm -rf "$tmpdir"
fi

# --- hygiene after installs ---
echo "[20-tools] apt cleanup"
apt-get -y autoremove --purge
apt-get -y clean
rm -rf /var/lib/apt/lists/*

# --- validate ---
echo "[20-tools] validate"
echo "tofu:    $(tofu --version | head -n1 || true)"
echo "packer:  $(packer --version || true)"
echo "ansible: $(ansible --version | head -n1 || true)"
echo "docker:  $(docker --version || true)"
echo "compose: $(docker compose version 2>/dev/null || true)"
echo "code:    $(code --version 2>/dev/null | head -n1 || true)"

echo "[20-tools] done: $(date -Is)"
touch "$MARKER"
