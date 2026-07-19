#!/usr/bin/env bash
#
# Install baseline + developer tools on Ubuntu Desktop or Server
#
# Run:
# git clone https://github.com/syselement/packertron-vms.git && cd packertron-vms/scripts/ubuntu && sudo ./02-provision-system.sh
#

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

SCRIPT_DIR="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
)"

# shellcheck source=lib/ubuntu-context.sh
. "$SCRIPT_DIR/lib/ubuntu-context.sh"

SCRIPT_NAME="provision-system"
LOG_PREFIX="[${SCRIPT_NAME}]"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
REBOOT_AT_END="${REBOOT_AT_END:-true}"
EXPAND_LVM_ROOT="${EXPAND_LVM_ROOT:-true}"
LOG_FILE="/var/log/${SCRIPT_NAME}-${RUN_ID}.log"
APT_KEYRING_DIR="${PACKERTRON_APT_KEYRING_DIR:-/etc/apt/keyrings}"
SYSTEM_KEYRING_DIR="${PACKERTRON_SYSTEM_KEYRING_DIR:-/usr/share/keyrings}"
APT_SOURCES_DIR="${PACKERTRON_APT_SOURCES_DIR:-/etc/apt/sources.list.d}"
SYSTEMD_RUNTIME_DIR="${PACKERTRON_SYSTEMD_RUNTIME_DIR:-/run/systemd/system}"
ROOT_VG_NAME="${ROOT_VG_NAME:-ubuntu-vg}"
ROOT_LV_PATH="${ROOT_LV_PATH:-/dev/ubuntu-vg/ubuntu-lv}"
USER_NAME=""
ARCH=""

readonly -a BASELINE_PACKAGES=(
  build-essential
  ca-certificates
  curl
  git
  gnupg
  jq
  lsb-release
  net-tools
  openssh-client
  pipx
  python3-venv
  snapd
  software-properties-common
  sshpass
  tmux
  vim
  wget
)

readonly -a DOCKER_CONFLICT_PACKAGES=(
  containerd
  docker-compose
  docker-compose-v2
  docker-doc
  docker.io
  podman-docker
  runc
)

readonly -a TOOLCHAIN_PACKAGES=(
  ansible
  code
  docker-ce
  docker-ce-cli
  containerd.io
  docker-buildx-plugin
  docker-compose-plugin
  packer
  tofu
)

readonly -a REQUIRED_TOOL_COMMANDS=(ansible code docker packer tofu)

# --- Logging setup ---
_ts() { date +'%F %T'; }
log() { printf '[%s] %s %s\n' "$(_ts)" "$LOG_PREFIX" "$*"; }
warn() { printf '[%s] %s WARN: %s\n' "$(_ts)" "$LOG_PREFIX" "$*"; }
die() {
  printf '[%s] %s ERROR: %s\n' "$(_ts)" "$LOG_PREFIX" "$*" >&2
  exit 1
}

fetch_file() {
  local url="$1"
  local out="$2"
  local tries=3
  local i
  for ((i = 1; i <= tries; i++)); do
    if curl \
      --fail \
      --show-error \
      --location \
      --connect-timeout 10 \
      --max-time 60 \
      --retry 2 \
      --retry-delay 2 \
      --output "$out" \
      "$url"; then
      return 0
    fi
    warn "download failed (${i}/${tries}): ${url}"
    sleep 2
  done
  return 1
}

install_missing_packages() {
  local -a missing=()
  local pkg
  for pkg in "$@"; do
    if [[ "$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)" != "install ok installed" ]]; then
      missing+=("$pkg")
    fi
  done

  if ((${#missing[@]} == 0)); then
    log "all requested packages already installed"
    return 0
  fi

  log "install missing packages: ${missing[*]}"
  apt-get \
    -o DPkg::Lock::Timeout=300 \
    install -y -qq --no-install-recommends "${missing[@]}"
}

install_file_if_changed() {
  local source_file="$1"
  local destination_file="$2"
  local mode="${3:-0644}"
  local destination_dir
  local temporary_file

  destination_dir="$(dirname -- "$destination_file")"
  install -d -m 0755 "$destination_dir"

  if [[ -f "$destination_file" ]] && cmp -s "$source_file" "$destination_file"; then
    log "already current: ${destination_file}"
    return 0
  fi

  temporary_file="$(mktemp "${destination_file}.tmp.XXXXXX")"
  if ! install -m "$mode" "$source_file" "$temporary_file"; then
    rm -f -- "$temporary_file"
    die "failed staging ${destination_file}"
  fi
  if ! mv -f -- "$temporary_file" "$destination_file"; then
    rm -f -- "$temporary_file"
    die "failed installing ${destination_file}"
  fi

  log "installed: ${destination_file}"
}

validate_signing_key() {
  local key_file="$1"
  local description="$2"

  gpg --batch --show-keys "$key_file" >/dev/null 2>&1 ||
    die "invalid ${description} signing key"
}

dearmor_signing_key() {
  local source_file="$1"
  local destination_file="$2"
  local description="$3"

  gpg \
    --batch \
    --yes \
    --dearmor \
    --output "$destination_file" \
    "$source_file" || die "failed processing ${description} signing key"
  validate_signing_key "$destination_file" "$description"
}

setup_ansible_repo() {
  local ppa="ppa:ansible/ansible"

  if grep -Rqs -- "ansible/ansible" "$APT_SOURCES_DIR" 2>/dev/null; then
    log "Ansible PPA already configured"
    return 0
  fi

  command -v add-apt-repository >/dev/null 2>&1 ||
    die "add-apt-repository is required to configure ${ppa}"
  add-apt-repository --yes --no-update "$ppa" ||
    die "failed configuring ${ppa}"
}

setup_vscode_repo() (
  set -Eeuo pipefail

  local temporary_dir
  temporary_dir="$(mktemp -d)"
  trap 'rm -rf -- "$temporary_dir"' EXIT

  fetch_file \
    "https://packages.microsoft.com/keys/microsoft.asc" \
    "$temporary_dir/microsoft.asc" || die "failed downloading Microsoft signing key"
  dearmor_signing_key \
    "$temporary_dir/microsoft.asc" \
    "$temporary_dir/microsoft.gpg" \
    "Microsoft"

  cat >"$temporary_dir/vscode.sources" <<EOF
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: ${SYSTEM_KEYRING_DIR}/microsoft.gpg
EOF
  install_file_if_changed "$temporary_dir/microsoft.gpg" "$SYSTEM_KEYRING_DIR/microsoft.gpg"
  install_file_if_changed "$temporary_dir/vscode.sources" "$APT_SOURCES_DIR/vscode.sources"
)

setup_docker_repo() (
  set -Eeuo pipefail

  local temporary_dir
  temporary_dir="$(mktemp -d)"
  trap 'rm -rf -- "$temporary_dir"' EXIT

  fetch_file \
    "https://download.docker.com/linux/ubuntu/gpg" \
    "$temporary_dir/docker.asc" || die "failed downloading Docker signing key"
  validate_signing_key "$temporary_dir/docker.asc" "Docker"

  cat >"$temporary_dir/docker.sources" <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: ${APT_KEYRING_DIR}/docker.asc
EOF
  install_file_if_changed "$temporary_dir/docker.asc" "$APT_KEYRING_DIR/docker.asc"
  install_file_if_changed "$temporary_dir/docker.sources" "$APT_SOURCES_DIR/docker.sources"
)

setup_opentofu_repo() (
  set -Eeuo pipefail

  local temporary_dir
  temporary_dir="$(mktemp -d)"
  trap 'rm -rf -- "$temporary_dir"' EXIT

  fetch_file \
    "https://get.opentofu.org/opentofu.gpg" \
    "$temporary_dir/opentofu.gpg" || die "failed downloading OpenTofu archive signing key"
  fetch_file \
    "https://packages.opentofu.org/opentofu/tofu/gpgkey" \
    "$temporary_dir/opentofu-repo.asc" || die "failed downloading OpenTofu repository signing key"
  validate_signing_key "$temporary_dir/opentofu.gpg" "OpenTofu archive"
  dearmor_signing_key \
    "$temporary_dir/opentofu-repo.asc" \
    "$temporary_dir/opentofu-repo.gpg" \
    "OpenTofu repository"

  cat >"$temporary_dir/opentofu.list" <<EOF
deb [signed-by=${APT_KEYRING_DIR}/opentofu.gpg,${APT_KEYRING_DIR}/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main
EOF
  install_file_if_changed "$temporary_dir/opentofu.gpg" "$APT_KEYRING_DIR/opentofu.gpg"
  install_file_if_changed "$temporary_dir/opentofu-repo.gpg" "$APT_KEYRING_DIR/opentofu-repo.gpg"
  install_file_if_changed "$temporary_dir/opentofu.list" "$APT_SOURCES_DIR/opentofu.list"
)

setup_hashicorp_repo() (
  set -Eeuo pipefail

  local temporary_dir
  temporary_dir="$(mktemp -d)"
  trap 'rm -rf -- "$temporary_dir"' EXIT

  fetch_file \
    "https://apt.releases.hashicorp.com/gpg" \
    "$temporary_dir/hashicorp.asc" || die "failed downloading HashiCorp signing key"
  dearmor_signing_key \
    "$temporary_dir/hashicorp.asc" \
    "$temporary_dir/hashicorp.gpg" \
    "HashiCorp"

  cat >"$temporary_dir/hashicorp.list" <<EOF
deb [arch=${ARCH} signed-by=${SYSTEM_KEYRING_DIR}/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${UBUNTU_CODENAME} main
EOF
  install_file_if_changed "$temporary_dir/hashicorp.gpg" "$SYSTEM_KEYRING_DIR/hashicorp-archive-keyring.gpg"
  install_file_if_changed "$temporary_dir/hashicorp.list" "$APT_SOURCES_DIR/hashicorp.list"
)

expand_root_lvm_if_present() {
  local free_extents

  case "$EXPAND_LVM_ROOT" in
    true) ;;
    false)
      log "LVM root expansion disabled"
      return 0
      ;;
    *) die "EXPAND_LVM_ROOT must be true or false" ;;
  esac

  if ! command -v lvs >/dev/null 2>&1 ||
    ! command -v vgs >/dev/null 2>&1 ||
    ! command -v lvextend >/dev/null 2>&1; then
    warn "LVM tools are unavailable; root expansion skipped"
    return 0
  fi

  if ! lvs "$ROOT_LV_PATH" >/dev/null 2>&1; then
    log "LVM root not present at ${ROOT_LV_PATH}; expansion skipped"
    return 0
  fi

  if ! free_extents="$(
    vgs --noheadings --nosuffix -o vg_free_count "$ROOT_VG_NAME" 2>/dev/null |
      tr -d '[:space:]'
  )"; then
    die "failed reading free extents from volume group ${ROOT_VG_NAME}"
  fi
  [[ "$free_extents" =~ ^[0-9]+$ ]] ||
    die "invalid free-extent count for ${ROOT_VG_NAME}: ${free_extents:-empty}"

  if ((free_extents == 0)); then
    log "LVM root already uses all free extents"
    return 0
  fi

  log "expanding ${ROOT_LV_PATH} by ${free_extents} free extents"
  lvextend -r -l +100%FREE "$ROOT_LV_PATH" ||
    die "failed expanding ${ROOT_LV_PATH}"
}

update_and_upgrade_system() {
  log "apt update / dist-upgrade"
  apt-get -o DPkg::Lock::Timeout=300 update -qq
  apt-get -o DPkg::Lock::Timeout=300 dist-upgrade -y -qq
}

configure_ntp() {
  local ntp_enabled

  log "enable NTP"
  if ! command -v timedatectl >/dev/null 2>&1; then
    warn "timedatectl is unavailable; NTP configuration skipped"
  elif ntp_enabled="$(timedatectl show --property=NTP --value 2>/dev/null)" &&
    [[ "$ntp_enabled" == "yes" ]]; then
    log "NTP is already enabled"
  elif ! timedatectl set-ntp true; then
    warn "could not enable NTP in this execution environment"
  else
    log "NTP enabled"
  fi
}

check_docker_package_conflicts() {
  local package
  local -a conflicts=()

  for package in "${DOCKER_CONFLICT_PACKAGES[@]}"; do
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null |
      grep -Fqx 'install ok installed'; then
      conflicts+=("$package")
    fi
  done

  ((${#conflicts[@]} == 0)) ||
    die "Docker CE conflicts with installed packages: ${conflicts[*]}; remove them explicitly before rerunning"
}

configure_docker() {
  local user_groups

  command -v docker >/dev/null 2>&1 ||
    die "Docker command is unavailable after package installation"
  getent group docker >/dev/null 2>&1 ||
    die "Docker group is unavailable after package installation"

  user_groups="$(id -nG "$USER_NAME")"
  if [[ " ${user_groups} " != *" docker "* ]]; then
    usermod -aG docker "$USER_NAME" ||
      die "failed adding ${USER_NAME} to the docker group"
    log "added ${USER_NAME} to the docker group; membership applies after login or reboot"
  else
    log "${USER_NAME} is already a member of the docker group"
  fi

  if [[ -d "$SYSTEMD_RUNTIME_DIR" ]]; then
    systemctl cat docker.service >/dev/null 2>&1 ||
      die "Docker systemd unit is unavailable after package installation"

    if ! systemctl is-enabled --quiet docker.service; then
      systemctl enable docker.service ||
        die "failed enabling Docker"
    fi
    if ! systemctl is-active --quiet docker.service; then
      systemctl start docker.service ||
        die "failed starting Docker"
    fi
    log "Docker service enabled and active"
  else
    warn "systemd is not operational; Docker service activation deferred"
  fi
}

validate_toolchain() {
  local command_name
  local code_version
  local compose_version
  local docker_version
  local packer_version
  local tofu_version

  for command_name in "${REQUIRED_TOOL_COMMANDS[@]}"; do
    command -v "$command_name" >/dev/null 2>&1 ||
      die "required command is unavailable after installation: ${command_name}"
  done

  log "validate toolchain"
  ansible --version 2>/dev/null | sed -n '1p' ||
    die "Ansible version check failed"

  code_version="$(sudo -u "$USER_NAME" -H code --version 2>/dev/null)" ||
    die "VS Code version check failed for ${USER_NAME}"
  printf 'code:    %s\n' "${code_version%%$'\n'*}"

  compose_version="$(docker compose version 2>/dev/null)" ||
    die "Docker Compose version check failed"
  printf 'compose: %s\n' "$compose_version"

  docker_version="$(docker --version 2>/dev/null)" ||
    die "Docker version check failed"
  printf 'docker:  %s\n' "$docker_version"

  packer_version="$(sudo -u "$USER_NAME" -H packer version 2>/dev/null)" ||
    die "Packer version check failed for ${USER_NAME}"
  printf 'packer:  %s\n' "${packer_version%%$'\n'*}"

  tofu_version="$(tofu --version 2>/dev/null)" ||
    die "OpenTofu version check failed"
  printf 'tofu:    %s\n' "${tofu_version%%$'\n'*}"
}

cleanup_apt() {
  log "apt cleanup"
  apt-get -o DPkg::Lock::Timeout=300 autoremove -y --purge
  apt-get -o DPkg::Lock::Timeout=300 clean
  rm -rf /var/lib/apt/lists/*
}

show_system_info() {
  log "system info"
  printf '%s\n' "---uname---"
  uname -a || true
  printf '%s\n' "---lsb---"
  lsb_release -a || true
  printf '%s\n' "---disk---"
  lsblk || true
  df -h || true
  printf '%s\n' "---mem---"
  free -h || true
  printf '%s\n' "---cpu---"
  lscpu || true
}

main() {
  local start_ts end_ts elapsed

  if [[ "${EUID}" -ne 0 ]]; then
    printf '[%s] ERROR must run as root\n' "$SCRIPT_NAME" >&2
    return 1
  fi

  initialize_ubuntu_context
  USER_NAME="$TARGET_USER"
  ARCH="$(dpkg --print-architecture)"

  exec > >(tee "$LOG_FILE") 2>&1

  printf '%s\n' "################################"
  printf '%s\n' "# Provision System"
  printf '%s\n' "################################"
  log "start: $(date -Is)"
  start_ts="$(date +%s)"

  log "distro version=${UBUNTU_VERSION_ID} codename=${UBUNTU_CODENAME} variant=${UBUNTU_VARIANT} variant_source=${UBUNTU_VARIANT_SOURCE} arch=${ARCH}"
  log "execution mode=${EXECUTION_MODE} context=${EXECUTION_CONTEXT} interactive=${EXECUTION_INTERACTIVE}"
  log "target user=${TARGET_USER} home=${TARGET_HOME}"

  expand_root_lvm_if_present
  update_and_upgrade_system

  log "install baseline packages (missing only)"
  install_missing_packages "${BASELINE_PACKAGES[@]}"

  configure_ntp
  check_docker_package_conflicts

  install -m 0755 -d "$APT_KEYRING_DIR" "$SYSTEM_KEYRING_DIR" "$APT_SOURCES_DIR"

  log "configure Ansible repository"
  setup_ansible_repo
  log "configure VS Code repository"
  setup_vscode_repo
  log "configure Docker repository"
  setup_docker_repo
  log "configure OpenTofu repository"
  setup_opentofu_repo
  log "configure HashiCorp repository"
  setup_hashicorp_repo

  log "apt update after repository configuration"
  apt-get -o DPkg::Lock::Timeout=300 update -qq

  log "install toolchain packages (missing only)"
  install_missing_packages "${TOOLCHAIN_PACKAGES[@]}"

  configure_docker
  cleanup_apt
  validate_toolchain
  show_system_info

  end_ts="$(date +%s)"
  elapsed="$((end_ts - start_ts))"
  log "done: $(date -Is)"
  log "elapsed: $(printf '%02d:%02d:%02d' "$((elapsed / 3600))" "$((elapsed % 3600 / 60))" "$((elapsed % 60))")"
  log "log file: ${LOG_FILE}"
  log "run_id: ${RUN_ID}"
  log "================= RUN END ================="

  printf '%s\n' "################################"
  printf '%s\n' "# System Provisioning Complete"
  printf '%s\n' "################################"

  if [[ "$REBOOT_AT_END" == "true" ]]; then
    printf '[%s] rebooting in 5 seconds...\n' "$SCRIPT_NAME"
    sleep 5
    sync
    shutdown -r now
  else
    printf '[%s] reboot deferred to orchestrator\n' "$SCRIPT_NAME"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
