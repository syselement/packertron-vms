#!/usr/bin/env bash
#
# Install baseline + developer tools on Ubuntu 24.04 Desktop
#
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
USER_NAME="syselement"
LOG="/var/log/provision-system.log"
exec > >(tee -a "$LOG") 2>&1

# --- must be root ---
if [[ "${EUID}" -ne 0 ]]; then
  echo "[provision-system] must run as root (use Vagrant provisioner with privileged: true)" >&2
  exit 1
fi

echo "################################"
echo "# Provision System"
echo "################################"
echo "[provision-system] start: $(date -Is)"
START_TS="$(date +%s)"

CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
ARCH="$(dpkg --print-architecture)"
echo "[provision-system] distro codename=${CODENAME} arch=${ARCH}"

# --- Update system and install baseline packages ---
echo "[provision-system] apt update / dist-upgrade"
apt-get update -y
apt-get dist-upgrade -y

echo "[provision-system] install baseline packages"
apt-get install -y --no-install-recommends \
  apt-transport-https \
  bash-completion \
  build-essential \
  ca-certificates \
  curl \
  git \
  gnupg \
  jq \
  lsb-release \
  net-tools \
  openssh-client \
  pipx \
  python3-venv \
  sshpass \
  software-properties-common \
  tmux \
  unzip \
  vim \
  wget \
  zip

# --- Enable NTP ---
echo "[provision-system] enable NTP (best effort)"
timedatectl set-ntp true || true

# --- Add apt keyrings dir ---
install -m 0755 -d /etc/apt/keyrings

# --- Ansible PPA ---
echo "[provision-system] configure ansible repo"
if ! grep -Rqs "^deb .*\bansible/ansible\b" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
  add-apt-repository --yes ppa:ansible/ansible
fi

# --- VS Code repo ---
echo "[provision-system] configure vscode repo"
if [[ ! -f /usr/share/keyrings/microsoft.gpg ]]; then
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft.gpg >/dev/null
  sudo chmod a+r /usr/share/keyrings/microsoft.gpg
fi
cat > /etc/apt/sources.list.d/vscode.sources <<EOF
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF
sudo chmod a+r /etc/apt/sources.list.d/vscode.sources

# --- Docker Engine repo ---
echo "[provision-system] configure docker repo"
if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
fi
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo chmod a+r /etc/apt/sources.list.d/docker.sources

# --- OpenTofu repo ---
echo "[provision-system] configure opentofu repo"
if [[ ! -f /etc/apt/keyrings/opentofu.gpg ]]; then
  curl -fsSL https://get.opentofu.org/opentofu.gpg | sudo tee /etc/apt/keyrings/opentofu.gpg >/dev/null
  curl -fsSL https://packages.opentofu.org/opentofu/tofu/gpgkey | sudo gpg --no-tty --batch --dearmor -o /etc/apt/keyrings/opentofu-repo.gpg >/dev/null
  sudo chmod a+r /etc/apt/keyrings/opentofu.gpg /etc/apt/keyrings/opentofu-repo.gpg
fi
cat > /etc/apt/sources.list.d/opentofu.list <<EOF
deb [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main
deb-src [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main
EOF
sudo chmod a+r /etc/apt/sources.list.d/opentofu.list

# --- Packer - HashiCorp repo ---
echo "[provision-system] configure hashicorp repo"
if [[ ! -f /usr/share/keyrings/hashicorp-archive-keyring.gpg ]]; then
  curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
fi
cat > /etc/apt/sources.list.d/hashicorp.list <<EOF
deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main
EOF
sudo chmod a+r /etc/apt/sources.list.d/hashicorp.list

# --- Install toolchain ---
echo "[provision-system] apt update (after adding repos)"
apt-get update -y
echo "[provision-system] install toolchain packages"
apt-get install -y --no-install-recommends \
  ansible \
  code \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
  packer \
  tofu

# --- Docker post-install setup ---
systemctl enable --now docker
if id "$USER_NAME" >/dev/null 2>&1; then
  usermod -aG docker "$USER_NAME" || true
fi

# --- Cleanup ---
echo "[provision-system] apt cleanup"
apt-get -y autoremove --purge
apt-get -y clean
rm -rf /var/lib/apt/lists/*

# --- Validate ---
echo "[provision-system] validate"
echo "ansible: $(ansible --version | head -n1 || true)"
CODE_VER="$(sudo -u "$USER_NAME" -H bash -lc 'code --version 2>/dev/null | head -n1 || true')"
echo "code:    ${CODE_VER}"
echo "compose: $(docker compose version 2>/dev/null || true)"
echo "docker:  $(docker --version || true)"
echo "packer:  $(packer --version || true)"
echo "tofu:    $(tofu --version | head -n1 || true)"

# --- done ---
echo "[provision-system] done: $(date -Is)"
END_TS="$(date +%s)"
ELAPSED="$((END_TS - START_TS))"
printf '[provision-system] elapsed: %02d:%02d:%02d\n' "$((ELAPSED / 3600))" "$((ELAPSED % 3600 / 60))" "$((ELAPSED % 60))"
echo "[provision-system] LOG: ${LOG}"
echo "################################"
echo "# Provision System Complete"
echo "[provision-system] rebooting"
reboot
echo "################################"
