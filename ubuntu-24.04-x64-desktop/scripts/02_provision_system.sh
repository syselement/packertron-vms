#!/usr/bin/env bash
#
# Install baseline + developer tools: Docker, OpenTofu, Ansible, Packer, VS Code
#
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

USER_NAME="syselement"

MARKER_DIR="/var/lib/provision"
MARKER="${MARKER_DIR}/provision-system.done"
LOG="/var/log/provision-system.log"

mkdir -p "$MARKER_DIR"
exec > >(tee -a "$LOG") 2>&1

trap 'rc=$?; echo "[provision-system] ERROR rc=${rc} at line ${LINENO}: ${BASH_COMMAND}" >&2; exit $rc' ERR

if [[ "${EUID}" -ne 0 ]]; then
  echo "[provision-system] must run as root (use Vagrant provisioner with privileged: true)" >&2
  exit 1
fi

if [[ -f "$MARKER" ]]; then
  echo "[provision-system] already applied: $MARKER"
  exit 0
fi

echo "[provision-system] start: $(date -Is)"

CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
ARCH="$(dpkg --print-architecture)"

echo "[provision-system] distro codename=${CODENAME} arch=${ARCH}"

# --- Base OS hygiene / deps ---
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
  python3 \
  python3-pip \
  python3-venv \
  software-properties-common \
  tmux \
  unzip \
  vim \
  wget \
  zip

# --- Enable NTP (best effort) ---
echo "[provision-system] enable NTP (best effort)"
timedatectl set-ntp true || true

# --- Add apt keyrings dir ---
install -m 0755 -d /etc/apt/keyrings

# --- Docker Engine (official repo) ---
echo "[provision-system] configure docker repo"
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi

cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable
EOF

# --- OpenTofu (official repo) ---
echo "[provision-system] configure opentofu repo"
if [[ ! -f /etc/apt/keyrings/opentofu.gpg ]]; then
  curl -fsSL https://get.opentofu.org/opentofu.gpg | gpg --dearmor -o /etc/apt/keyrings/opentofu.gpg
  chmod a+r /etc/apt/keyrings/opentofu.gpg
fi

cat > /etc/apt/sources.list.d/opentofu.list <<EOF
deb [signed-by=/etc/apt/keyrings/opentofu.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main
EOF

# --- Ansible PPA ---
echo "[provision-system] configure ansible repo"
# idempotent: add-apt-repository is safe to re-run, but we avoid repeated work
if ! grep -Rqs "^deb .*\bansible/ansible\b" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
  add-apt-repository --yes ppa:ansible/ansible
fi

# --- Install toolchain (single apt update for all repos) ---
echo "[provision-system] apt update (after adding repos)"
apt-get update -y

echo "[provision-system] install docker + tofu + ansible"
apt-get install -y --no-install-recommends \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
  tofu \
  ansible

systemctl enable --now docker

if id "$USER_NAME" >/dev/null 2>&1; then
  usermod -aG docker "$USER_NAME" || true
fi

# --- Packer (binary install, pinned) ---
echo "[provision-system] install packer (pinned)"
PACKER_VERSION="1.14.3"
NEED_PACKER="true"
if command -v packer >/dev/null 2>&1; then
  if [[ "$(packer --version 2>/dev/null || true)" == "$PACKER_VERSION" ]]; then
    NEED_PACKER="false"
  fi
fi

if [[ "$NEED_PACKER" == "true" ]]; then
  tmpdir="$(mktemp -d)"
  pushd "$tmpdir" >/dev/null
  curl -fsSLO "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_${ARCH}.zip"
  unzip -o "packer_${PACKER_VERSION}_linux_${ARCH}.zip"
  install -m 0755 packer /usr/local/bin/packer
  popd >/dev/null
  rm -rf "$tmpdir"
fi

# --- VS Code (.deb) ---
echo "[provision-system] install vscode"
if ! command -v code >/dev/null 2>&1; then
  if [[ "$ARCH" != "amd64" ]]; then
    echo "[provision-system] skipping vscode: only linux-deb-x64 is configured (arch=${ARCH})"
  else
    tmpdir="$(mktemp -d)"
    pushd "$tmpdir" >/dev/null
    curl -fsSLo code.deb "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
    apt-get install -y ./code.deb
    popd >/dev/null
    rm -rf "$tmpdir"
  fi
fi

# --- hygiene after installs ---
echo "[provision-system] apt cleanup"
apt-get -y autoremove --purge
apt-get -y clean
rm -rf /var/lib/apt/lists/*

# --- validate ---
echo "[provision-system] validate"
echo "tofu:    $(tofu --version | head -n1 || true)"
echo "packer:  $(packer --version || true)"
echo "ansible: $(ansible --version | head -n1 || true)"
echo "docker:  $(docker --version || true)"
echo "compose: $(docker compose version 2>/dev/null || true)"
echo "code:    $(code --version 2>/dev/null | head -n1 || true)"

touch "$MARKER"
echo "[provision-system] done: $(date -Is)"
echo "[provision-system] marker: $MARKER"
