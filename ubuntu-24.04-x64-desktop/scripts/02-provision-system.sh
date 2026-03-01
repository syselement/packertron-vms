#!/usr/bin/env bash
#
# Install baseline + developer tools on Ubuntu 24.04 Desktop
#
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

USER_NAME="syselement"
SCRIPT_NAME="provision-system"
LOG_PREFIX="[${SCRIPT_NAME}]"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/var/log/${SCRIPT_NAME}-${RUN_ID}.log"
exec > >(tee "$LOG_FILE") 2>&1

# --- Logging setup ---
_ts() { date +'%F %T'; }
log()  { printf '[%s] %s %s\n' "$(_ts)" "$LOG_PREFIX" "$*"; }
warn() { printf '[%s] %s WARN: %s\n' "$(_ts)" "$LOG_PREFIX" "$*"; }

fetch_file() {
  local url="$1"
  local out="$2"
  local tries=3
  local i
  for i in $(seq 1 "$tries"); do
    if curl -fL --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 2 -o "$out" "$url"; then
      return 0
    fi
    warn "download failed (${i}/${tries}): ${url}"
    sleep 2
  done
  return 1
}

install_missing_packages() {
  local missing=()
  local pkg
  for pkg in "$@"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      missing+=("$pkg")
    fi
  done

  if ((${#missing[@]} == 0)); then
    log "all requested packages already installed"
    return 0
  fi

  log "install missing packages: ${missing[*]}"
  if ! apt-get install -y -qq --no-install-recommends "${missing[@]}"; then
    warn "failed installing some packages: ${missing[*]}"
    return 1
  fi
  return 0
}

setup_ansible_repo() {
  # Always attempt repo declaration so reruns refresh state.
  if ! add-apt-repository --yes ppa:ansible/ansible; then
    warn "ansible PPA setup failed"
  fi
}

setup_vscode_repo() {
  local key_tmp
  key_tmp="$(mktemp)"

  if fetch_file "https://packages.microsoft.com/keys/microsoft.asc" "$key_tmp"; then
    if gpg --dearmor < "$key_tmp" > /usr/share/keyrings/microsoft.gpg; then
      chmod a+r /usr/share/keyrings/microsoft.gpg
    else
      warn "failed to process Microsoft GPG key"
    fi
  else
    warn "failed to download Microsoft GPG key"
  fi
  rm -f "$key_tmp"

  cat > /etc/apt/sources.list.d/vscode.sources <<EOF
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF
  chmod a+r /etc/apt/sources.list.d/vscode.sources
}

setup_docker_repo() {
  if fetch_file "https://download.docker.com/linux/ubuntu/gpg" "/etc/apt/keyrings/docker.asc"; then
    chmod a+r /etc/apt/keyrings/docker.asc
  else
    warn "failed to download Docker GPG key"
  fi

  cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  chmod a+r /etc/apt/sources.list.d/docker.sources
}

setup_opentofu_repo() {
  local key_a key_b
  key_a="$(mktemp)"
  key_b="$(mktemp)"

  if fetch_file "https://get.opentofu.org/opentofu.gpg" "$key_a"; then
    cp "$key_a" /etc/apt/keyrings/opentofu.gpg
  else
    warn "failed to download OpenTofu key A"
  fi

  if fetch_file "https://packages.opentofu.org/opentofu/tofu/gpgkey" "$key_b"; then
    if gpg --no-tty --batch --dearmor < "$key_b" > /etc/apt/keyrings/opentofu-repo.gpg; then
      chmod a+r /etc/apt/keyrings/opentofu.gpg /etc/apt/keyrings/opentofu-repo.gpg
    else
      warn "failed to process OpenTofu key B"
    fi
  else
    warn "failed to download OpenTofu key B"
  fi

  rm -f "$key_a" "$key_b"

  cat > /etc/apt/sources.list.d/opentofu.list <<EOF
deb [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main
deb-src [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main
EOF
  chmod a+r /etc/apt/sources.list.d/opentofu.list
}

setup_hashicorp_repo() {
  local key_tmp
  key_tmp="$(mktemp)"

  if fetch_file "https://apt.releases.hashicorp.com/gpg" "$key_tmp"; then
    if gpg --dearmor < "$key_tmp" > /usr/share/keyrings/hashicorp-archive-keyring.gpg; then
      chmod a+r /usr/share/keyrings/hashicorp-archive-keyring.gpg
    else
      warn "failed to process HashiCorp GPG key"
    fi
  else
    warn "failed to download HashiCorp GPG key"
  fi
  rm -f "$key_tmp"

  cat > /etc/apt/sources.list.d/hashicorp.list <<EOF
deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main
EOF
  chmod a+r /etc/apt/sources.list.d/hashicorp.list
}

echo "################################"
echo "# Provision System"
echo "################################"
log "start: $(date -Is)"
START_TS="$(date +%s)"

CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
ARCH="$(dpkg --print-architecture)"
log "distro codename=${CODENAME} arch=${ARCH}"

# --- must be root ---
if [[ "${EUID}" -ne 0 ]]; then
  log "must run as root"
  exit 1
fi

if id "$USER_NAME" >/dev/null 2>&1; then
  log "running user-scoped commands as: ${USER_NAME}"
else
  log "user not found: ${USER_NAME}"
  exit 1
fi

# --- Expand LVM root to use all free space ---
log "expand LVM root to use all free space (if any)"
lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv || warn "LVM expand skipped or failed"

# --- Update system and install baseline packages ---
log "apt update / dist-upgrade"
apt-get update -y -qq || warn "apt update failed"
apt-get dist-upgrade -y -qq || warn "apt dist-upgrade failed"

log "install baseline packages (missing only)"
install_missing_packages \
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
  vim \
  wget || true

# --- Enable NTP ---
log "enable NTP"
timedatectl set-ntp true || true

# --- Add apt keyrings dir ---
install -m 0755 -d /etc/apt/keyrings

# --- Configure external repositories (always rewrite) ---
log "configure ansible repo"
setup_ansible_repo

log "configure vscode repo"
setup_vscode_repo

log "configure docker repo"
setup_docker_repo

log "configure opentofu repo"
setup_opentofu_repo

log "configure hashicorp repo"
setup_hashicorp_repo

# --- Install toolchain (missing only) ---
log "apt update (after adding repos)"
if ! apt-get update -y -qq; then
  warn "apt update after repo setup failed; continuing with best effort"
fi

log "install toolchain packages (missing only)"
install_missing_packages \
  ansible \
  code \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
  packer \
  tofu || true

# --- Docker post-install setup ---
if command -v docker >/dev/null 2>&1; then
  systemctl enable --now docker || warn "failed to enable/start docker"
  usermod -aG docker "$USER_NAME" || true
else
  warn "docker not installed; skipping docker service/user setup"
fi

# --- Cleanup ---
log "apt cleanup"
apt-get -y autoremove --purge || true
apt-get -y clean || true
rm -rf /var/lib/apt/lists/*

# --- Validate ---
log "validate"
echo "ansible: $(ansible --version | head -n1 || true)"
CODE_VER="$(sudo -u "$USER_NAME" -H bash -lc 'code --version 2>/dev/null | head -n1 || true')"
echo "code:    ${CODE_VER}"
echo "compose: $(docker compose version 2>/dev/null || true)"
echo "docker:  $(docker --version || true)"
echo "packer:  $(packer --version || true)"
echo "tofu:    $(tofu --version | head -n1 || true)"

# --- System info ---
log "system info"
echo "---uname---"
echo "$(uname -a || true)"
echo "---lsb---"
echo "$(lsb_release -a || true)"
echo "---disk---"
echo "$(lsblk || true)"
echo "$(df -h || true)"
echo "---mem---"
echo "$(free -h || true)"
echo "---cpu---"
echo "$(lscpu || true)"

# --- done ---
END_TS="$(date +%s)"
ELAPSED="$((END_TS - START_TS))"
log "done: $(date -Is)"
log "elapsed: $(printf '%02d:%02d:%02d' "$((ELAPSED / 3600))" "$((ELAPSED % 3600 / 60))" "$((ELAPSED % 60))")"
log "log file: ${LOG_FILE}"
log "run_id: ${RUN_ID}"
log "================= RUN END ================="

echo "################################"
echo "# System Provisioning Complete"
echo "[provision-system] rebooting in 5 seconds ..."
echo "################################"
sleep 5
sync
shutdown -r now
