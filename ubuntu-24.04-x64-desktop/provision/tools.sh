#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

MARKER="/var/lib/provision/phase1-tools.done"
mkdir -p /var/lib/provision
if [ -f "$MARKER" ]; then
  echo "[phase1] already provisioned: $MARKER"
  exit 0
fi

echo "[phase1] base packages"
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl wget gnupg lsb-release unzip zip jq git \
  software-properties-common apt-transport-https \
  build-essential python3 python3-venv python3-pip

# --- Docker Engine (official repo) ---
echo "[phase1] install docker engine"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
ARCH="$(dpkg --print-architecture)"
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

# Add your user to docker group (requires re-login to take effect)
usermod -aG docker syselement || true

# --- OpenTofu (official .deb repo) ---
echo "[phase1] install opentofu"
curl -fsSL https://get.opentofu.org/opentofu.gpg | gpg --dearmor -o /etc/apt/keyrings/opentofu.gpg
chmod a+r /etc/apt/keyrings/opentofu.gpg
echo "deb [signed-by=/etc/apt/keyrings/opentofu.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main" \
  > /etc/apt/sources.list.d/opentofu.list
apt-get update -y
apt-get install -y --no-install-recommends tofu

# --- Ansible (official PPA for Ubuntu) ---
echo "[phase1] install ansible"
add-apt-repository --yes --update ppa:ansible/ansible
apt-get install -y --no-install-recommends ansible

# --- Packer (recommended: precompiled binary) ---
echo "[phase1] install packer"
PACKER_VERSION="1.14.3"
tmpdir="$(mktemp -d)"
cd "$tmpdir"
curl -fsSLO "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip"
unzip -o "packer_${PACKER_VERSION}_linux_amd64.zip"
install -m 0755 packer /usr/local/bin/packer
cd /
rm -rf "$tmpdir"

# --- VS Code (official .deb install method) ---
echo "[phase1] install vscode"
tmpdir="$(mktemp -d)"
cd "$tmpdir"
curl -fsSLo code.deb "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
apt-get install -y ./code.deb
cd /
rm -rf "$tmpdir"

# Quick validation
echo "[phase1] validate"
tofu --version | head -n 1 || true
packer --version || true
ansible --version | head -n 1 || true
docker --version || true
code --version | head -n 1 || true

touch "$MARKER"
echo "[phase1] done"