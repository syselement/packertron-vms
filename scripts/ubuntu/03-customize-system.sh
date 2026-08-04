#!/usr/bin/env bash
#
# Customize Ubuntu Desktop or Server
#
# Manual run without reboot from a fresh clone (one line):
# git clone https://github.com/syselement/packertron-vms.git && cd packertron-vms/scripts/ubuntu && sudo env REBOOT_AT_END=false ./03-customize-system.sh
#
# Manual rerun without reboot from the repository root:
# cd scripts/ubuntu && sudo env REBOOT_AT_END=false ./03-customize-system.sh
#
# Notes:
# - Run as root.
# - Console output is colorized when interactive.
# - Log output is written to /var/log/customize-system-<run_id>.log without ANSI escapes.
# - GNOME preferences are written immediately for USER_NAME through GSettings.
#

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
)"

# shellcheck source=lib/ubuntu-context.sh
. "$SCRIPT_DIR/lib/ubuntu-context.sh"
# shellcheck source=lib/apt-transaction.sh
. "$SCRIPT_DIR/lib/apt-transaction.sh"

# -----------------------------------------------------------------------------
# Configuration and package manifests
# -----------------------------------------------------------------------------

SCRIPT_NAME="customize-system"
LOG_PREFIX="[${SCRIPT_NAME}]"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
REBOOT_AT_END="${REBOOT_AT_END:-true}"
LOG_FILE="/var/log/${SCRIPT_NAME}-${RUN_ID}.log"
APT_SOURCES_CHANGED=false
STARSHIP_INSTALL_URL="${STARSHIP_INSTALL_URL:-https://starship.rs/install.sh}"
SYSTEM_KEYRING_DIR="${PACKERTRON_SYSTEM_KEYRING_DIR:-/usr/share/keyrings}"
APT_SOURCES_DIR="${PACKERTRON_APT_SOURCES_DIR:-/etc/apt/sources.list.d}"
APT_TRUSTED_KEY_DIR="${PACKERTRON_APT_TRUSTED_KEY_DIR:-/etc/apt/trusted.gpg.d}"
SYSTEMD_RUNTIME_DIR="${PACKERTRON_SYSTEMD_RUNTIME_DIR:-/run/systemd/system}"
KVM_DEVICE="${PACKERTRON_KVM_DEVICE:-/dev/kvm}"
APT_TRANSACTION_DIR="${PACKERTRON_APT_TRANSACTION_DIR:-/var/lib/packertron-apt-transactions/customize-system}"
HOMEBREW_PREFIX="${PACKERTRON_HOMEBREW_PREFIX:-/home/linuxbrew/.linuxbrew}"
HOMEBREW_INSTALL_URL="${HOMEBREW_INSTALL_URL:-https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh}"

readonly -a APT_BOOTSTRAP_PACKAGES=(
    ca-certificates
    curl
    gnupg
    lsb-release
)

readonly -a COMMON_PACKAGES=(
    7zip
    7zip-rar
    aptitude
    arp-scan
    bash-completion
    bat
    bats
    btop
    build-essential
    cockpit
    docker-ctop
    duf
    eza
    fastfetch
    fd-find
    fontconfig
    gdu
    git
    gping
    htop
    iftop
    imagemagick
    ipcalc
    iperf3
    jq
    lm-sensors
    nano
    net-tools
    nload
    nmap
    npm
    openjdk-21-jre-headless
    pipx
    plocate
    s-tui
    shellcheck
    shfmt
    speedtest-cli
    sshpass
    stress
    sysstat
    tailscale
    tmux
    tor
    tree
    ugrep
    unzip
    vim
    wget
    whois
    wireguard
    zsh
)

readonly -a RELEASE_OPTIONAL_PACKAGES=(
    rdap
)

readonly -a DESKTOP_PACKAGES=(
    brave-browser
    dbeaver-ce
    filezilla
    flatpak
    fonts-noto-color-emoji
    gnome-shell-extension-manager
    gnome-shell-extensions
    gnome-system-monitor
    gnome-tweaks
    meld
    mullvad-vpn
    qbittorrent
    sublime-text
    terminator
    typora
    vlc
    xclip
)

readonly -a FLATPAK_PACKAGES=(
    com.bitwarden.desktop
    com.obsproject.Studio
    de.swsnr.turnon
    io.ente.auth
    io.github.sigmasd.pingmonitor
    org.cryptomator.Cryptomator
    org.gnome.Boxes
)

readonly -a VIRTUALIZATION_HOST_PACKAGES=(
    cockpit-machines
    cpu-checker
    libvirt-daemon-system
)

readonly -a VIRTUALIZATION_DESKTOP_PACKAGES=(
    virt-manager
)

# -----------------------------------------------------------------------------
# Runtime and logging
# -----------------------------------------------------------------------------

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "[${SCRIPT_NAME}] ERROR must run as root (use: sudo bash $0)" >&2
        exit 1
    fi
}

USER_NAME=""
VERSION_ID=""
CODENAME=""
ARCH=""
t_bold=""
t_dim=""
t_cyan=""
t_green=""
t_yellow=""
t_red=""
t_reset=""

initialize_runtime() {
    require_root

    # Console keeps ANSI colors, while the log file stores plain text.
    if [[ -t 1 && "${TERM:-dumb}" != "dumb" && -z "${NO_COLOR+x}" ]]; then
        t_bold=$'\e[1m'
        t_dim=$'\e[2m'
        t_cyan=$'\e[36m'
        t_green=$'\e[32m'
        t_yellow=$'\e[33m'
        t_red=$'\e[31m'
        t_reset=$'\e[0m'
    fi
    install -m 0600 /dev/null "$LOG_FILE"
    exec > >(tee >(sed -u -r 's/\x1B\[[0-9;]*[[:alpha:]]//g' >"$LOG_FILE")) 2>&1

    initialize_ubuntu_context
    USER_NAME="$TARGET_USER"
    VERSION_ID="$UBUNTU_VERSION_ID"
    CODENAME="$UBUNTU_CODENAME"
    ARCH="$(dpkg --print-architecture)"
}

_ts() { date +'%F %T'; }
log() {
    local level="$1"
    local level_color="$2"
    shift 2

    local message="$*"
    local ts

    ts="$(_ts)"
    printf '%s %s %s%-5s%s %s\n' \
        "[$ts]" \
        "$LOG_PREFIX" \
        "$level_color" \
        "$level" \
        "$t_reset" \
        "$message"
}
section() {
    printf '\n'
    log "STEP" "${t_cyan}${t_bold}" "==================== $* ===================="
}
info() { log "INFO" "$t_dim" "$@"; }
ok() { log "OK" "${t_green}${t_bold}" "$@"; }
warn() { log "WARN" "${t_yellow}${t_bold}" "$@"; }
error() { log "ERROR" "${t_red}${t_bold}" "$@"; }
manual_step() {
    printf '\n'
    log "STEP" "${t_cyan}${t_bold}" "--- $* ---"
}
manual_line() { printf '    %s\n' "$*"; }
manual_item() { printf '    • %s\n' "$*"; }
manual_command() { printf '      $ %s\n' "$*"; }
die() {
    error "$*"
    exit 1
}

# -----------------------------------------------------------------------------
# User context and command helpers
# -----------------------------------------------------------------------------

# Functions declared with (...) intentionally isolate traps, temporary
# directories, working-directory changes, and local shell options.

user_home() {
    local account="$1"
    getent passwd "$account" | cut -d: -f6
}

run_as_target_user() {
    [[ -n "${TARGET_USER:-}" ]] || die "target user is not initialized"
    [[ -n "${TARGET_HOME:-}" && "$TARGET_HOME" == /* ]] ||
        die "target home is not initialized"
    [[ "${TARGET_UID:-}" =~ ^[0-9]+$ ]] || die "target UID is not initialized"
    [[ -n "${TARGET_GROUP:-}" ]] || die "target group is not initialized"
    (($# > 0)) || die "run_as_target_user requires a command"

    sudo -u "$TARGET_USER" -g "$TARGET_GROUP" -H env \
        HOME="$TARGET_HOME" \
        USER="$TARGET_USER" \
        LOGNAME="$TARGET_USER" \
        TARGET_USER="$TARGET_USER" \
        TARGET_HOME="$TARGET_HOME" \
        TARGET_UID="$TARGET_UID" \
        TARGET_GROUP="$TARGET_GROUP" \
        "$@"
}

verify_target_ownership() {
    local description="$2"
    local path="$1"
    local owner owner_group

    [[ -e "$path" ]] || die "${description} is missing: ${path}"
    owner="$(stat -Lc '%U' "$path")"
    owner_group="$(stat -Lc '%G' "$path")"
    [[ "$owner" == "$TARGET_USER" && "$owner_group" == "$TARGET_GROUP" ]] ||
        die "unexpected ${description} ownership: ${owner}:${owner_group}; expected ${TARGET_USER}:${TARGET_GROUP}"
}

run_apt_get() {
    DEBIAN_FRONTEND=noninteractive apt-get \
        -o DPkg::Lock::Timeout=300 \
        -o Acquire::Retries=3 \
        -o Acquire::http::Timeout=30 \
        -o Acquire::https::Timeout=30 \
        "$@"
}

run_quiet_command() (
    local description="$1"
    local line
    local output_file
    local status
    shift

    output_file="$(mktemp)"
    trap 'rm -f -- "$output_file"' EXIT

    if "$@" >"$output_file" 2>&1; then
        return 0
    else
        status=$?
    fi

    while IFS= read -r line; do
        error "${description}: ${line}"
    done <"$output_file"
    return "$status"
)

# -----------------------------------------------------------------------------
# Downloads, packages, and managed files
# -----------------------------------------------------------------------------

fetch_file() {
    local destination_file="$2"
    local url="$1"

    curl \
        --fail \
        --show-error \
        --silent \
        --location \
        --connect-timeout 10 \
        --max-time 180 \
        --speed-limit 1024 \
        --speed-time 30 \
        --retry 2 \
        --retry-delay 2 \
        --output "$destination_file" \
        "$url"
}

validate_zip_archive() {
    local archive_file="$1"
    local description="$2"
    local entry

    [[ -s "$archive_file" ]] || die "downloaded ${description} archive is empty"
    unzip -tq "$archive_file" >/dev/null ||
        die "downloaded ${description} archive is invalid"

    while IFS= read -r entry; do
        if [[ "$entry" == /* || "$entry" == ../* || "$entry" == */.. || "$entry" == */../* ]]; then
            die "downloaded ${description} archive contains an unsafe path: ${entry}"
        fi
    done < <(unzip -Z1 "$archive_file")
}

validate_gnome_extension_archive() {
    local archive_file="$1"
    local expected_uuid="$2"
    local actual_uuid

    actual_uuid="$(unzip -p "$archive_file" metadata.json 2>/dev/null | jq -r '.uuid // empty')" ||
        die "GNOME extension archive does not contain valid metadata"
    [[ "$actual_uuid" == "$expected_uuid" ]] ||
        die "unexpected GNOME extension UUID: ${actual_uuid:-missing}; expected ${expected_uuid}"
}

verify_github_asset_digest() {
    local asset_file="$1"
    local published_digest="$2"
    local description="$3"
    local actual_digest
    local expected_digest

    if [[ ! "$published_digest" =~ ^sha256:([[:xdigit:]]{64})$ ]]; then
        warn "GitHub did not provide a SHA-256 digest for ${description}; relying on format validation"
        return
    fi

    expected_digest="${BASH_REMATCH[1],,}"
    actual_digest="$(sha256sum "$asset_file")"
    actual_digest="${actual_digest%% *}"
    [[ "$actual_digest" == "$expected_digest" ]] ||
        die "SHA-256 verification failed for ${description}"
}

fetch_latest_github_release_metadata() {
    local repository="$1"
    local metadata_file="$2"
    local description="$3"

    fetch_file "https://api.github.com/repos/${repository}/releases/latest" "$metadata_file" ||
        die "failed downloading ${description} release metadata"
}

fetch_github_asset_from_metadata() {
    local match_type="$1"
    local asset_pattern="$2"
    local destination_file="$3"
    local metadata_file="$4"
    local description="$5"
    local asset_count asset_digest asset_url jq_filter

    # shellcheck disable=SC2016 # $pattern is expanded by jq.
    case "$match_type" in
        exact) jq_filter='.name == $pattern' ;;
        suffix) jq_filter='.name | endswith($pattern)' ;;
        *) die "unsupported GitHub asset match type: ${match_type}" ;;
    esac

    asset_count="$(
        jq --arg pattern "$asset_pattern" \
            "[.assets[] | select(${jq_filter})] | length" \
            "$metadata_file"
    )"
    [[ "$asset_count" == "1" ]] ||
        die "expected one ${description} release asset matching ${asset_pattern}, found ${asset_count}"

    asset_url="$(
        jq -r --arg pattern "$asset_pattern" \
            ".assets[] | select(${jq_filter}) | .browser_download_url" \
            "$metadata_file"
    )"
    asset_digest="$(
        jq -r --arg pattern "$asset_pattern" \
            ".assets[] | select(${jq_filter}) | .digest // empty" \
            "$metadata_file"
    )"
    [[ "$asset_url" == https://github.com/* ]] ||
        die "unexpected ${description} release asset URL"

    fetch_file "$asset_url" "$destination_file" ||
        die "failed downloading ${description}"
    verify_github_asset_digest "$destination_file" "$asset_digest" "$description"
}

fetch_latest_github_asset() {
    local repository="$1"
    local match_type="$2"
    local asset_pattern="$3"
    local destination_file="$4"
    local metadata_file="$5"
    local description="$6"

    fetch_latest_github_release_metadata "$repository" "$metadata_file" "$description"
    fetch_github_asset_from_metadata \
        "$match_type" \
        "$asset_pattern" \
        "$destination_file" \
        "$metadata_file" \
        "$description"
}

validate_debian_package() {
    local deb_file="$1"
    local expected_package="$2"
    local description="$3"
    local package_architecture package_name package_version

    [[ -s "$deb_file" ]] || die "downloaded ${description} package is empty"
    dpkg-deb --info "$deb_file" >/dev/null 2>&1 ||
        die "downloaded ${description} package is invalid"

    package_name="$(dpkg-deb -f "$deb_file" Package)"
    package_architecture="$(dpkg-deb -f "$deb_file" Architecture)"
    package_version="$(dpkg-deb -f "$deb_file" Version)"

    [[ "$package_name" == "$expected_package" ]] ||
        die "unexpected ${description} package name: ${package_name}; expected ${expected_package}"
    [[ "$package_architecture" == "$ARCH" || "$package_architecture" == "all" ]] ||
        die "unexpected ${description} package architecture: ${package_architecture}; expected ${ARCH}"
    [[ -n "$package_version" ]] ||
        die "downloaded ${description} package does not declare a version"
}

install_debian_package() {
    local deb_file="$1"
    local package_name="$2"
    local description="$3"
    local installed_version package_version

    validate_debian_package "$deb_file" "$package_name" "$description"
    package_version="$(dpkg-deb -f "$deb_file" Version)"
    installed_version="$(dpkg-query -W -f='${Version}' "$package_name" 2>/dev/null || true)"

    if [[ -n "$installed_version" ]] &&
        dpkg --compare-versions "$installed_version" ge "$package_version"; then
        info "${description} ${installed_version} already installed, skipping"
        return
    fi

    info "installing ${description} ${package_version}"
    run_quiet_command "${description} installation failed" \
        run_apt_get install -y -qq "$deb_file" ||
        die "failed installing ${description} ${package_version}"

    installed_version="$(dpkg-query -W -f='${Version}' "$package_name" 2>/dev/null || true)"
    if [[ -z "$installed_version" ]] ||
        ! dpkg --compare-versions "$installed_version" ge "$package_version"; then
        die "${description} installation could not be verified"
    fi
    ok "${description} ${installed_version} installed"
}

install_downloaded_debian_package() (
    set -Eeuo pipefail

    local url="$1"
    local package_name="$2"
    local description="$3"
    local temporary_dir

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    info "downloading ${description}"
    fetch_file "$url" "$temporary_dir/package.deb" ||
        die "failed downloading ${description}"
    install_debian_package "$temporary_dir/package.deb" "$package_name" "$description"
)

install_latest_github_debian_package() (
    set -Eeuo pipefail

    local repository="$1"
    local asset_suffix="$2"
    local package_name="$3"
    local description="$4"
    local installed_version release_tag release_version
    local temporary_dir

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    info "checking latest ${description} GitHub release"
    fetch_latest_github_release_metadata \
        "$repository" \
        "$temporary_dir/release.json" \
        "$description"
    release_tag="$(jq -r '.tag_name // empty' "$temporary_dir/release.json")"
    release_version="${release_tag#v}"
    [[ "$release_version" =~ ^[0-9]+(\.[0-9]+)+$ ]] ||
        die "unexpected ${description} release tag: ${release_tag:-missing}"

    installed_version="$(dpkg-query -W -f='${Version}' "$package_name" 2>/dev/null || true)"
    if [[ -n "$installed_version" ]] &&
        dpkg --compare-versions "$installed_version" ge "$release_version"; then
        info "${description} ${installed_version} already matches latest release ${release_version}, skipping download"
        return
    fi

    info "downloading ${description} package"
    fetch_github_asset_from_metadata \
        "suffix" \
        "$asset_suffix" \
        "$temporary_dir/package.deb" \
        "$temporary_dir/release.json" \
        "${description} package"
    install_debian_package "$temporary_dir/package.deb" "$package_name" "$description"
)

install_target_config_file() {
    local source_file="$1"
    local destination_file="$2"
    local description="$3"
    local backup_file="${destination_file}.packertron.bak"
    local destination_dir
    local destination_group=""
    local destination_mode=""
    local destination_owner=""
    local staged_file

    [[ -f "$source_file" ]] || die "expected ${description} configuration is missing"
    [[ ! -L "$destination_file" ]] ||
        die "refusing to replace symlinked ${description} configuration: ${destination_file}"

    destination_dir="$(dirname -- "$destination_file")"
    install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$destination_dir"

    if [[ -f "$destination_file" ]]; then
        destination_owner="$(stat -Lc '%U' "$destination_file")"
        destination_group="$(stat -Lc '%G' "$destination_file")"
        destination_mode="$(stat -Lc '%a' "$destination_file")"

        if cmp -s -- "$source_file" "$destination_file" &&
            [[ "$destination_owner" == "$TARGET_USER" &&
                "$destination_group" == "$TARGET_GROUP" &&
                "$destination_mode" == "644" ]]; then
            info "${description} already configured, skipping"
            return
        fi

        if ! cmp -s -- "$source_file" "$destination_file" &&
            [[ ! -e "$backup_file" ]]; then
            install \
                -o "$TARGET_USER" \
                -g "$TARGET_GROUP" \
                -m 0644 \
                "$destination_file" \
                "$backup_file"
            info "preserved previous ${description} configuration: ${backup_file}"
        fi
    fi

    staged_file="$(mktemp "${destination_dir}/.packertron-config.XXXXXX")"
    if ! install \
        -o "$TARGET_USER" \
        -g "$TARGET_GROUP" \
        -m 0644 \
        "$source_file" \
        "$staged_file"; then
        rm -f -- "$staged_file"
        die "failed staging ${description} configuration"
    fi

    if ! mv -f -- "$staged_file" "$destination_file"; then
        rm -f -- "$staged_file"
        die "failed activating ${description} configuration"
    fi

    cmp -s -- "$source_file" "$destination_file" ||
        die "${description} configuration could not be verified"
    verify_target_ownership "$destination_file" "${description} configuration"
    [[ "$(stat -Lc '%a' "$destination_file")" == "644" ]] ||
        die "unexpected ${description} configuration permissions"

    ok "${description} configured"
}

validate_openpgp_key() {
    local description="$2"
    local expected_fingerprint="${3:-}"
    local fingerprint
    local key_file="$1"

    if ! fingerprint="$(
        gpg --batch --show-keys --with-colons "$key_file" 2>/dev/null |
            awk -F: '$1 == "fpr" { print toupper($10); exit }'
    )" || [[ -z "$fingerprint" ]]; then
        die "invalid ${description} signing key"
    fi

    expected_fingerprint="${expected_fingerprint//[[:space:]]/}"
    expected_fingerprint="${expected_fingerprint^^}"
    if [[ -n "$expected_fingerprint" && "$fingerprint" != "$expected_fingerprint" ]]; then
        die "unexpected ${description} signing-key fingerprint: ${fingerprint}"
    fi
}

dearmor_openpgp_key() {
    local description="$3"
    local destination_file="$2"
    local source_file="$1"

    gpg \
        --batch \
        --yes \
        --dearmor \
        --output "$destination_file" \
        "$source_file" || die "failed processing ${description} signing key"
}

validate_repository_source() {
    local expected_key_file="$3"
    local expected_uri="$2"
    local source_file="$1"

    grep -Fq -- "$expected_uri" "$source_file" ||
        die "repository definition does not contain expected URI: ${expected_uri}"
    grep -Fq -- "$expected_key_file" "$source_file" ||
        die "repository definition does not reference expected signing key: ${expected_key_file}"
}

apply_repository_setup() {
    local setup_function="$1"
    local status

    if "$setup_function"; then
        return 0
    else
        status=$?
    fi

    if ((status == 10)); then
        APT_SOURCES_CHANGED=true
        return 0
    fi

    return "$status"
}

install_package_array() {
    local description="$1"
    shift
    local package
    local -a missing=()
    local -a packages=("$@")

    if ((${#packages[@]} == 0)); then
        info "${description}: no packages requested, skipping"
        return 0
    fi

    for package in "${packages[@]}"; do
        if [[ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)" != "install ok installed" ]]; then
            missing+=("$package")
        fi
    done

    if ((${#missing[@]} == 0)); then
        info "${description}: all packages already installed"
        return 0
    fi

    info "installing ${#missing[@]} missing ${description} packages: ${missing[*]}"
    if ! run_apt_get install -y -qq "${missing[@]}"; then
        die "failed installing ${description} packages: ${missing[*]}"
    fi
    ok "${description} package installation completed"
}

install_available_package_array() {
    local description="$1"
    shift
    local package
    local -a available=()

    for package in "$@"; do
        if apt-cache show "$package" >/dev/null 2>&1; then
            available+=("$package")
        else
            info "${package} is unavailable for Ubuntu ${VERSION_ID}; skipping"
        fi
    done

    ((${#available[@]} > 0)) || return 0
    install_package_array "$description" "${available[@]}"
}

# -----------------------------------------------------------------------------
# Virtualization and system services
# -----------------------------------------------------------------------------

virtualization_qemu_package() {
    case "$ARCH" in
        amd64) printf 'qemu-system-x86\n' ;;
        arm64 | armhf) printf 'qemu-system-arm\n' ;;
        *) return 1 ;;
    esac
}

install_virtualization_stack() {
    local qemu_package
    local -a packages=("${VIRTUALIZATION_HOST_PACKAGES[@]}")

    qemu_package="$(virtualization_qemu_package)" ||
        die "virtualization is not configured for architecture ${ARCH}"
    packages+=("$qemu_package")

    if [[ "$UBUNTU_VARIANT" == "desktop" ]]; then
        packages+=("${VIRTUALIZATION_DESKTOP_PACKAGES[@]}")
    fi

    install_package_array "virtualization" "${packages[@]}"
}

configure_system_socket() {
    local unit="$1"
    local description="$2"
    local changed=false

    command -v systemctl >/dev/null 2>&1 ||
        die "systemctl is required to configure ${description}"
    systemctl cat "$unit" >/dev/null 2>&1 ||
        die "${description} socket unit is not available after package installation"

    if ! systemctl is-enabled --quiet "$unit"; then
        systemctl enable "$unit" >/dev/null ||
            die "failed enabling ${description} socket"
        changed=true
    fi

    if [[ ! -d "$SYSTEMD_RUNTIME_DIR" ]]; then
        warn "systemd is not running; ${description} socket activation is deferred until boot"
        return
    fi

    if ! systemctl is-active --quiet "$unit"; then
        systemctl start "$unit" ||
            die "failed starting ${description} socket"
        changed=true
    fi

    if [[ "$changed" == true ]]; then
        ok "${description} socket enabled and active"
    else
        info "${description} socket already enabled and active"
    fi
}

configure_cockpit_socket() {
    configure_system_socket "cockpit.socket" "Cockpit"
}

configure_libvirt() {
    local user_groups

    getent group libvirt >/dev/null 2>&1 ||
        die "libvirt group is unavailable after package installation"
    user_groups="$(id -nG "$TARGET_USER")" ||
        die "failed reading group membership for ${TARGET_USER}"

    if [[ " ${user_groups} " == *" libvirt "* ]]; then
        info "${TARGET_USER} is already a member of the libvirt group"
    else
        usermod -aG libvirt "$TARGET_USER" ||
            die "failed adding ${TARGET_USER} to the libvirt group"
        ok "added ${TARGET_USER} to the libvirt group; membership applies after login or reboot"
    fi

    configure_system_socket "libvirtd.socket" "Libvirt"
}

validate_virtualization_stack() {
    local network_info

    if [[ -c "$KVM_DEVICE" ]] ||
        { command -v kvm-ok >/dev/null 2>&1 && kvm-ok >/dev/null 2>&1; }; then
        ok "KVM hardware acceleration is available"
    else
        warn "KVM hardware acceleration is unavailable; enable virtualization or nested virtualization if required"
    fi

    if [[ ! -d "$SYSTEMD_RUNTIME_DIR" ]]; then
        warn "systemd is not running; libvirt connection validation is deferred until boot"
        return
    fi

    command -v virsh >/dev/null 2>&1 ||
        die "virsh is unavailable after libvirt installation"
    if ! virsh --connect qemu:///system list --all >/dev/null 2>&1; then
        die "cannot connect to the local qemu:///system libvirt service"
    fi
    ok "local qemu:///system libvirt connection verified"

    if [[ "$UBUNTU_VARIANT" == "desktop" ]]; then
        command -v virt-manager >/dev/null 2>&1 ||
            die "virt-manager is unavailable after Desktop virtualization installation"
        ok "Virtual Machine Manager installation verified"
    fi

    if network_info="$(virsh --connect qemu:///system net-info default 2>/dev/null)"; then
        if grep -Eq '^Active:[[:space:]]+yes$' <<<"$network_info"; then
            info "libvirt default network is active"
        else
            warn "libvirt default network is defined but inactive; network state was not changed"
        fi
    else
        warn "libvirt default network is not defined; network state was not changed"
    fi
}

install_flatpak_package_array() {
    local description="$1"
    shift

    local packages=("$@")
    local missing=()
    local app

    if [[ "$UBUNTU_VARIANT" != "desktop" ]]; then
        info "${description}: desktop-only, skipping"
        return
    fi

    command -v flatpak >/dev/null 2>&1 || die "flatpak is required to install ${description}"

    flatpak remotes --system --columns=name | grep -qx flathub || die "system-wide Flathub remote is not configured"

    if ((${#packages[@]} == 0)); then
        info "${description}: no packages requested, skipping"
        return
    fi

    for app in "${packages[@]}"; do
        if flatpak info --system "$app" >/dev/null 2>&1; then
            info "${app} already installed"
        else
            missing+=("$app")
        fi
    done

    if ((${#missing[@]} == 0)); then
        info "${description}: all packages already installed"
        return
    fi

    info "installing ${#missing[@]} ${description} packages"
    flatpak install --system --noninteractive -y flathub "${missing[@]}"

    for app in "${missing[@]}"; do
        flatpak info --system "$app" >/dev/null 2>&1 || die "Flatpak installation could not be verified: ${app}"
    done

    ok "${description} package installation completed"
}

# -----------------------------------------------------------------------------
# GNOME and target-user configuration
# -----------------------------------------------------------------------------

write_file_if_changed() {
    local source_file="$1"
    local destination_file="$2"
    local destination_directory
    local temporary_file

    if [[ -f "$destination_file" ]] && cmp -s "$source_file" "$destination_file"; then
        return 1
    fi

    apt_transaction_record_file "$destination_file"

    destination_directory="$(dirname -- "$destination_file")"
    install -d -m 0755 "$destination_directory"
    temporary_file="$(mktemp "${destination_file}.tmp.XXXXXX")"

    if ! install -m 0644 "$source_file" "$temporary_file"; then
        rm -f -- "$temporary_file"
        die "failed staging ${destination_file}"
    fi
    if ! mv -f -- "$temporary_file" "$destination_file"; then
        rm -f -- "$temporary_file"
        die "failed installing ${destination_file}"
    fi

    return 0
}

# Get the user's D-Bus session bus socket.
gnome_user_bus_available() {
    [[ -S "/run/user/${TARGET_UID}/bus" ]]
}

# Run a command as the desktop user on their real per-user D-Bus when one
# exists. This is essential when the script is launched with sudo from a live
# GNOME session: using an isolated dbus-run-session there can race with the
# already-running dconf service. For SSH/Vagrant provisioning before graphical
# login, fall back to a temporary session bus so GSettings can still persist.
run_as_gnome_user() {
    local runtime_dir="/run/user/${TARGET_UID}"

    if gnome_user_bus_available; then
        run_as_target_user env \
            XDG_RUNTIME_DIR="$runtime_dir" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime_dir}/bus" \
            "$@"
    else
        run_as_target_user dbus-run-session -- "$@"
    fi
}

apply_gnome_preferences() {
    local bus_mode

    if gnome_user_bus_available; then
        bus_mode="existing per-user D-Bus"
    else
        bus_mode="temporary D-Bus fallback"
    fi
    info "applying GNOME preferences via ${bus_mode}"

    if ! run_as_gnome_user bash -s -- "file://${TARGET_HOME}/.config/background" <<'GNOME_SETTINGS'; then
set -uo pipefail

failures=0
wallpaper_uri="$1"

gsettings_with_schema_dir() {
  local schema_dir="$1"
  shift

  if [[ -n "$schema_dir" ]]; then
    gsettings --schemadir "$schema_dir" "$@"
  else
    gsettings "$@"
  fi
}

schema_exists() {
  local schema="$1"
  local schema_dir="${2:-}"

  # Process substitution avoids a pipefail/SIGPIPE false negative caused by
  # `gsettings list-schemas | grep -q`.
  grep -Fx -- "$schema" < <(gsettings_with_schema_dir "$schema_dir" list-schemas) >/dev/null
}

key_exists() {
  local schema="$1"
  local key="$2"
  local schema_dir="${3:-}"

  schema_exists "$schema" "$schema_dir" || return 1
  grep -Fx -- "$key" < <(gsettings_with_schema_dir "$schema_dir" list-keys "$schema") >/dev/null
}

gsetting_values_equal() {
  local expected="$1"
  local actual="$2"
  local number_re='^[-+]?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$'

  if [[ "$expected" =~ $number_re && "$actual" =~ $number_re ]]; then
    awk -v expected="$expected" -v actual="$actual" '
      BEGIN {
        delta = actual - expected
        if (delta < 0)
          delta = -delta

        expected_abs = expected < 0 ? -expected : expected
        actual_abs   = actual   < 0 ? -actual   : actual
        scale = expected_abs > actual_abs ? expected_abs : actual_abs

        if (scale < 1)
          scale = 1

        exit !(delta <= 1e-9 * scale)
      }
    '
  else
    [[ "$actual" == "$expected" ]]
  fi
}

set_gsetting() {
  local schema="$1"
  local key="$2"
  local value="$3"
  local persist_value="${4:-false}"
  local schema_dir="${5:-}"
  local actual

  if ! key_exists "$schema" "$key" "$schema_dir"; then
    printf '[gnome-settings] SKIP missing schema/key: %s %s\n' "$schema" "$key"
    return 0
  fi

  if [[ "$(gsettings_with_schema_dir "$schema_dir" writable "$schema" "$key" 2>/dev/null)" != "true" ]]; then
    printf '[gnome-settings] SKIP non-writable key: %s %s\n' "$schema" "$key"
    return 0
  fi

  actual="$(gsettings_with_schema_dir "$schema_dir" get "$schema" "$key")"
  if [[ "$persist_value" != true ]] && gsetting_values_equal "$value" "$actual"; then
    return 0
  fi

  if ! gsettings_with_schema_dir "$schema_dir" set "$schema" "$key" "$value"; then
    printf '[gnome-settings] ERROR failed: %s %s = %s\n' "$schema" "$key" "$value" >&2
    failures=$((failures + 1))
    return 0
  fi

  actual="$(gsettings_with_schema_dir "$schema_dir" get "$schema" "$key")"

  if ! gsetting_values_equal "$value" "$actual"; then
    printf '[gnome-settings] ERROR verify failed: %s %s; requested=%s actual=%s\n' "$schema" "$key" "$value" "$actual" >&2
    failures=$((failures + 1))
    return 0
  fi

  printf '[gnome-settings] SET %s %s = %s\n' "$schema" "$key" "$actual"
}

update_string_array() {
  local schema="$1"
  local key="$2"
  local action="$3"
  local item="$4"
  local current updated actual

  if ! key_exists "$schema" "$key"; then
    printf '[gnome-settings] SKIP missing schema/key: %s %s\n' "$schema" "$key"
    return 0
  fi

  current="$(gsettings get "$schema" "$key")"
  if ! updated="$(python3 - "$current" "$action" "$item" <<'PYTHON_ARRAY'
import ast
import sys

raw, action, item = sys.argv[1:]
if raw.startswith("@as "):
    raw = raw[4:]
values = list(ast.literal_eval(raw))

if action == "add":
    if item not in values:
        values.append(item)
elif action == "remove":
    values = [value for value in values if value != item]
else:
    raise SystemExit(f"unsupported action: {action}")

print("[" + ", ".join(repr(value) for value in values) + "]")
PYTHON_ARRAY
  )"; then
    printf '[gnome-settings] ERROR cannot parse/update %s %s\n' "$schema" "$key" >&2
    failures=$((failures + 1))
    return 0
  fi

  if [[ "$current" == "$updated" ]]; then
    return 0
  fi

  if ! gsettings set "$schema" "$key" "$updated"; then
    printf '[gnome-settings] ERROR failed updating: %s %s\n' "$schema" "$key" >&2
    failures=$((failures + 1))
    return 0
  fi

  actual="$(gsettings get "$schema" "$key")"
  printf '[gnome-settings] SET %s %s = %s\n' "$schema" "$key" "$actual"
}

# Appearance
set_gsetting org.gnome.desktop.interface color-scheme "'prefer-dark'"
set_gsetting org.gnome.desktop.interface document-font-name "'JetBrainsMono Nerd Font 11'"
set_gsetting org.gnome.desktop.interface font-name "'JetBrainsMono Nerd Font 11'"
set_gsetting org.gnome.desktop.interface gtk-theme "'Yaru-yellow-dark'"
set_gsetting org.gnome.desktop.interface monospace-font-name "'JetBrainsMono Nerd Font Mono 11'"
set_gsetting org.gnome.desktop.interface show-battery-percentage "true"
set_gsetting org.gnome.desktop.interface text-scaling-factor "1.1"

# Wallpaper
set_gsetting org.gnome.desktop.background picture-uri "'${wallpaper_uri}'"
set_gsetting org.gnome.desktop.background picture-uri-dark "'${wallpaper_uri}'"
set_gsetting org.gnome.desktop.background picture-options "'zoom'"
set_gsetting org.gnome.mutter workspaces-only-on-primary false

# Ubuntu Dock
set_gsetting org.gnome.shell.extensions.dash-to-dock click-action "'minimize-or-previews'"
set_gsetting org.gnome.shell.extensions.dash-to-dock dash-max-icon-size "34"
# Persist this override even when the pre-login schema default already matches.
set_gsetting org.gnome.shell.extensions.dash-to-dock dock-position "'BOTTOM'" true
set_gsetting org.gnome.shell.extensions.dash-to-dock extend-height "true"
set_gsetting org.gnome.shell.extensions.dash-to-dock show-trash "false"

# Power and lock screen
set_gsetting org.gnome.desktop.notifications show-in-lock-screen "false"
set_gsetting org.gnome.desktop.screensaver lock-delay "uint32 1800"
set_gsetting org.gnome.desktop.screensaver lock-enabled "true"
set_gsetting org.gnome.desktop.screensaver ubuntu-lock-on-suspend "true"
set_gsetting org.gnome.desktop.session idle-delay "uint32 1800"
set_gsetting org.gnome.system.location enabled "false"

# Display color / Night Light
set_gsetting org.gnome.settings-daemon.plugins.color night-light-enabled "true"
set_gsetting org.gnome.settings-daemon.plugins.color night-light-schedule-automatic "false"
set_gsetting org.gnome.settings-daemon.plugins.color night-light-schedule-from "18.0"
set_gsetting org.gnome.settings-daemon.plugins.color night-light-schedule-to "8.0"
set_gsetting org.gnome.settings-daemon.plugins.color night-light-temperature "uint32 4700"

# Mouse
set_gsetting org.gnome.desktop.peripherals.mouse accel-profile "'default'"
set_gsetting org.gnome.desktop.peripherals.mouse speed "-0.3"

# Sound
set_gsetting org.gnome.desktop.sound allow-volume-above-100-percent "true"

# Power
set_gsetting org.gnome.desktop.interface show-battery-percentage "true"
set_gsetting org.gnome.settings-daemon.plugins.power power-button-action "'suspend'"

# Ubuntu Desktop
set_gsetting org.gnome.shell.extensions.ding show-home "false"

# Notifications
set_gsetting org.gnome.desktop.notifications show-in-lock-screen "false"

# Mouse and Touchpad
# false = traditional scrolling; true = natural/reversed scrolling.
set_gsetting org.gnome.desktop.peripherals.touchpad natural-scroll "false"

# Dock favorites
set_gsetting org.gnome.shell favorite-apps \
  "['org.gnome.Nautilus.desktop', 'brave-browser.desktop', 'terminator.desktop', 'sublime_text.desktop', 'obsidian.desktop', 'code.desktop']"

# Enable System Monitor Panel on Ubuntu 26.04.
# Fall back to the packaged System Monitor extension on Ubuntu 24.04.
new_ext_uuid='system-monitor-panel@naimur'
old_ext_uuid='system-monitor@gnome-shell-extensions.gcampax.github.com'
hide_access_ext_uuid='hide-universal-access@akiirui.github.io'
dim_background_ext_uuid='dim-background-windows@stephane-13.github.com'
dim_background_schema='org.gnome.shell.extensions.dim-background-windows'
dim_background_ext_dir=''
dim_background_schema_dir=''

new_ext_installed=false
old_ext_installed=false
hide_access_ext_installed=false
dim_background_ext_installed=false

if [[ -d "/usr/share/gnome-shell/extensions/${new_ext_uuid}" ||
      -d "$HOME/.local/share/gnome-shell/extensions/${new_ext_uuid}" ]]; then
  new_ext_installed=true
fi

if [[ -d "/usr/share/gnome-shell/extensions/${old_ext_uuid}" ||
      -d "$HOME/.local/share/gnome-shell/extensions/${old_ext_uuid}" ]]; then
  old_ext_installed=true
fi

if [[ -d "/usr/share/gnome-shell/extensions/${hide_access_ext_uuid}" ||
      -d "$HOME/.local/share/gnome-shell/extensions/${hide_access_ext_uuid}" ]]; then
  hide_access_ext_installed=true
fi

if [[ -d "$HOME/.local/share/gnome-shell/extensions/${dim_background_ext_uuid}" ]]; then
  dim_background_ext_dir="$HOME/.local/share/gnome-shell/extensions/${dim_background_ext_uuid}"
elif [[ -d "/usr/share/gnome-shell/extensions/${dim_background_ext_uuid}" ]]; then
  dim_background_ext_dir="/usr/share/gnome-shell/extensions/${dim_background_ext_uuid}"
fi

if [[ -n "$dim_background_ext_dir" ]]; then
  dim_background_ext_installed=true
  dim_background_schema_dir="${dim_background_ext_dir}/schemas"
fi

if [[ "$new_ext_installed" == true ]]; then
  set_gsetting org.gnome.shell disable-user-extensions "false"
  # Disable the old packaged extension.
  update_string_array  org.gnome.shell enabled-extensions remove "$old_ext_uuid"
  update_string_array org.gnome.shell disabled-extensions add "$old_ext_uuid"
  # Enable the new extension.
  update_string_array org.gnome.shell enabled-extensions add "$new_ext_uuid"
  update_string_array org.gnome.shell disabled-extensions remove "$new_ext_uuid"

elif [[ "$old_ext_installed" == true ]]; then
  # Ubuntu 24.04 fallback.
  set_gsetting org.gnome.shell disable-user-extensions "false"
  update_string_array org.gnome.shell enabled-extensions add "$old_ext_uuid"
  update_string_array org.gnome.shell disabled-extensions remove "$old_ext_uuid"
else
  printf '[gnome-settings] SKIP no supported System Monitor extension installed\n'
fi

if [[ "$hide_access_ext_installed" == true ]]; then
  set_gsetting org.gnome.shell disable-user-extensions "false"
  update_string_array org.gnome.shell enabled-extensions add "$hide_access_ext_uuid"
  update_string_array org.gnome.shell disabled-extensions remove "$hide_access_ext_uuid"
else
  printf '[gnome-settings] SKIP Hide Universal Access extension is not installed\n'
fi

if [[ "$dim_background_ext_installed" == true ]]; then
  set_gsetting org.gnome.shell disable-user-extensions "false"
  update_string_array org.gnome.shell enabled-extensions add "$dim_background_ext_uuid"
  update_string_array org.gnome.shell disabled-extensions remove "$dim_background_ext_uuid"

  if [[ -d "$dim_background_schema_dir" ]]; then
    set_gsetting "$dim_background_schema" brightness "0.8" false "$dim_background_schema_dir"
    set_gsetting "$dim_background_schema" saturation "1.0" false "$dim_background_schema_dir"
  else
    printf '[gnome-settings] ERROR Dim Background Windows schema directory is missing: %s\n' "$dim_background_schema_dir" >&2
    failures=$((failures + 1))
  fi
else
  printf '[gnome-settings] SKIP Dim Background Windows extension is not installed\n'
fi

# Force a final read through the same backend before the process/session exits.
gsettings get org.gnome.shell favorite-apps >/dev/null

(( failures == 0 ))
GNOME_SETTINGS
        warn "one or more GNOME preferences failed; inspect the log above"
        return 1
    fi

    ok "GNOME preferences applied and verified"
}

install_gnome_extension_from_zip() (
    set -Eeuo pipefail

    local command_name
    local display_name="$1"
    local uuid="$2"
    local download_url="$3"
    local installed_uuid=""
    local metadata_file="${TARGET_HOME}/.local/share/gnome-shell/extensions/${uuid}/metadata.json"
    local temporary_dir

    command -v jq >/dev/null 2>&1 ||
        die "jq is required to inspect ${display_name}"

    if [[ -f "$metadata_file" ]] &&
        installed_uuid="$(jq -r '.uuid // empty' "$metadata_file" 2>/dev/null)" &&
        [[ "$installed_uuid" == "$uuid" ]]; then
        verify_target_ownership "$metadata_file" "${display_name} extension metadata"
        info "${display_name} extension already installed and verified, skipping"
        return
    elif [[ -f "$metadata_file" ]]; then
        warn "${display_name} extension metadata is incomplete; repairing installation"
    fi

    for command_name in curl gnome-extensions unzip; do
        command -v "$command_name" >/dev/null 2>&1 ||
            die "${command_name} is required to install ${display_name}"
    done

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT
    chmod 0755 "$temporary_dir"

    info "downloading ${display_name} extension"
    fetch_file "$download_url" "$temporary_dir/extension.zip" ||
        die "failed downloading ${display_name} extension"
    validate_zip_archive "$temporary_dir/extension.zip" "${display_name} extension"
    validate_gnome_extension_archive "$temporary_dir/extension.zip" "$uuid"
    chmod 0644 "$temporary_dir/extension.zip"

    run_quiet_command \
        "${display_name} extension installer" \
        run_as_target_user \
        gnome-extensions install --force "$temporary_dir/extension.zip" ||
        die "${display_name} extension installation failed"

    [[ -f "$metadata_file" ]] ||
        die "${display_name} extension installation could not be verified"
    installed_uuid="$(jq -r '.uuid // empty' "$metadata_file" 2>/dev/null)" ||
        die "${display_name} extension installed invalid metadata"
    [[ "$installed_uuid" == "$uuid" ]] ||
        die "${display_name} extension installed unexpected metadata"
    verify_target_ownership "$metadata_file" "${display_name} extension metadata"

    ok "${display_name} extension installed for ${TARGET_USER}"
)

compile_gnome_extension_schemas() {
    local display_name="$1"
    local uuid="$2"
    local extension_dir="${TARGET_HOME}/.local/share/gnome-shell/extensions/${uuid}"
    local schema_dir="${extension_dir}/schemas"
    local compiled_schema="${schema_dir}/gschemas.compiled"
    local schema_file
    local schemas_current=true
    local -a schema_files=("$schema_dir"/*.gschema.xml)

    [[ -f "${schema_files[0]}" ]] ||
        die "${display_name} extension does not provide a GSettings schema"

    if [[ ! -f "$compiled_schema" ]]; then
        schemas_current=false
    else
        for schema_file in "${schema_files[@]}"; do
            if [[ "$schema_file" -nt "$compiled_schema" ]]; then
                schemas_current=false
                break
            fi
        done
    fi

    if [[ "$schemas_current" == true ]]; then
        verify_target_ownership "$compiled_schema" "${display_name} compiled schema"
        info "${display_name} extension schemas already compiled"
        return
    fi

    command -v glib-compile-schemas >/dev/null 2>&1 ||
        die "glib-compile-schemas is required to configure ${display_name}"

    run_as_target_user glib-compile-schemas "$schema_dir" ||
        die "failed compiling ${display_name} extension schemas"
    [[ -f "$compiled_schema" ]] ||
        die "${display_name} extension schema compilation could not be verified"
    verify_target_ownership "$compiled_schema" "${display_name} compiled schema"
    ok "${display_name} extension schemas compiled"
}

install_dim_background_windows_extension() (
    set -Eeuo pipefail

    local account="$1"
    local download_url="https://extensions.gnome.org/download-extension/dim-background-windows@stephane-13.github.com.shell-extension.zip?version_tag=70012"

    [[ "$account" == "$TARGET_USER" ]] ||
        die "Dim Background Windows must be installed for the resolved target user"

    case "$VERSION_ID" in
        24.* | 26.*) ;;
        *)
            warn "Dim Background Windows installation not configured for Ubuntu ${VERSION_ID}"
            return
            ;;
    esac

    install_gnome_extension_from_zip \
        "Dim Background Windows" \
        "dim-background-windows@stephane-13.github.com" \
        "$download_url"

    compile_gnome_extension_schemas \
        "Dim Background Windows" \
        "dim-background-windows@stephane-13.github.com"
)

install_hide_universal_access_extension() (
    set -Eeuo pipefail

    local account="$1"
    local download_url=""

    [[ "$account" == "$TARGET_USER" ]] ||
        die "Hide Universal Access must be installed for the resolved target user"

    case "$VERSION_ID" in
        26.*)
            download_url="https://extensions.gnome.org/review/download/69554.shell-extension.zip"
            ;;
        24.*)
            download_url="https://extensions.gnome.org/review/download/52417.shell-extension.zip"
            ;;
        *)
            warn "Hide Universal Access installation not configured for Ubuntu ${VERSION_ID}"
            return
            ;;
    esac

    install_gnome_extension_from_zip \
        "Hide Universal Access" \
        "hide-universal-access@akiirui.github.io" \
        "$download_url"
)

install_system_monitor_panel_extension() (
    set -Eeuo pipefail

    local account="$1"
    local download_url="https://extensions.gnome.org/review/download/72725.shell-extension.zip"

    [[ "$account" == "$TARGET_USER" ]] ||
        die "System Monitor Panel must be installed for the resolved target user"

    case "$VERSION_ID" in
        26.*) ;;
        24.*)
            info "System Monitor Panel requires GNOME 48 or newer; skipping on Ubuntu ${VERSION_ID}"
            return
            ;;
        *)
            warn "System Monitor Panel installation not configured for Ubuntu ${VERSION_ID}"
            return
            ;;
    esac

    install_gnome_extension_from_zip \
        "System Monitor Panel" \
        "system-monitor-panel@naimur" \
        "$download_url"
)

enable_battery_health_preservation() {
    local device supported enabled
    local found_battery=false
    local enabled_count=0

    if ! command -v upower >/dev/null 2>&1; then
        warn "upower not found; cannot enable battery health preservation"
        return
    fi

    if ! command -v busctl >/dev/null 2>&1; then
        warn "busctl not found; cannot enable battery health preservation"
        return
    fi

    while IFS= read -r device; do
        [[ "$device" == */battery_* ]] || continue
        found_battery=true

        supported="$(
            busctl --system get-property \
                org.freedesktop.UPower \
                "$device" \
                org.freedesktop.UPower.Device \
                ChargeThresholdSupported 2>/dev/null || true
        )"

        if [[ "$supported" != "b true" ]]; then
            info "battery charge thresholds unsupported for ${device##*/}; skipping"
            continue
        fi

        if ! busctl --system call \
            org.freedesktop.UPower \
            "$device" \
            org.freedesktop.UPower.Device \
            EnableChargeThreshold b true >/dev/null; then
            warn "failed to enable battery health preservation for ${device##*/}"
            continue
        fi

        enabled="$(
            busctl --system get-property \
                org.freedesktop.UPower \
                "$device" \
                org.freedesktop.UPower.Device \
                ChargeThresholdEnabled 2>/dev/null || true
        )"

        if [[ "$enabled" == "b true" ]]; then
            ok "battery health preservation enabled for ${device##*/}"
            enabled_count=$((enabled_count + 1))
        else
            warn "battery health preservation could not be verified for ${device##*/}"
        fi
    done < <(upower -e 2>/dev/null || true)

    if [[ "$found_battery" == false ]]; then
        info "no system battery detected; skipping battery health preservation"
    elif ((enabled_count == 0)); then
        info "no battery supports UPower charge thresholds"
    fi
}

# -----------------------------------------------------------------------------
# Third-party repositories
# -----------------------------------------------------------------------------

ensure_fastfetch_ppa() {
    local ppa="ppa:zhangsongcui3371/fastfetch"
    local source_file

    case "$VERSION_ID" in
        24.*)
            if grep -Rqs "zhangsongcui3371/fastfetch" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
                info "fastfetch PPA already present"
                return
            fi

            if ! command -v add-apt-repository >/dev/null 2>&1; then
                die "add-apt-repository is required for the fastfetch PPA on Ubuntu ${VERSION_ID}"
            fi

            if add-apt-repository --yes --no-update "$ppa" >/dev/null 2>&1; then
                while IFS= read -r -d '' source_file; do
                    apt_transaction_record_created_file "$source_file"
                done < <(grep -RlZ -- "zhangsongcui3371/fastfetch" "$APT_SOURCES_DIR" 2>/dev/null || true)
                APT_SOURCES_CHANGED=true
                ok "added fastfetch PPA for Ubuntu ${VERSION_ID}"
            else
                warn "failed to add fastfetch PPA; fastfetch may not be available"
            fi
            ;;
        26.*)
            info "Ubuntu ${VERSION_ID} provides fastfetch; skipping fastfetch PPA"
            ;;
        *)
            warn "Ubuntu ${VERSION_ID} is not explicitly handled for the fastfetch PPA; using configured repositories"
            ;;
    esac
}

install_docker_ctop_repository() (
    set -Eeuo pipefail

    local changed=false
    local key_file="${SYSTEM_KEYRING_DIR}/azlux-archive-keyring.gpg"
    local source_file="${APT_SOURCES_DIR}/azlux.sources"
    local temporary_dir
    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    fetch_file "https://azlux.fr/repo.gpg" "$temporary_dir/azlux.asc" ||
        die "failed downloading the AZLux repository signing key"
    dearmor_openpgp_key "$temporary_dir/azlux.asc" "$temporary_dir/azlux.gpg" "AZLux"
    validate_openpgp_key \
        "$temporary_dir/azlux.gpg" \
        "AZLux" \
        "98B824A5FA7D3A10FDB225B7CA548A0A0312D8E6"

    cat >"$temporary_dir/azlux.sources" <<EOF
Types: deb
URIs: https://packages.azlux.fr/debian/
Suites: stable
Components: main
Signed-By: ${key_file}
EOF
    validate_repository_source \
        "$temporary_dir/azlux.sources" \
        "https://packages.azlux.fr/debian/" \
        "$key_file"

    if write_file_if_changed "$temporary_dir/azlux.gpg" "$key_file"; then
        changed=true
        ok "installed AZLux repository signing key"
    else
        info "AZLux repository signing key already current"
    fi
    if write_file_if_changed "$temporary_dir/azlux.sources" "$source_file"; then
        changed=true
        ok "configured AZLux repository"
    else
        info "AZLux repository already configured"
    fi

    [[ "$changed" == false ]] || return 10
)

ensure_tailscale_repository() (
    set -Eeuo pipefail

    local changed=false
    local key_file="${SYSTEM_KEYRING_DIR}/tailscale-archive-keyring.gpg"
    local repository_url="https://pkgs.tailscale.com/stable/ubuntu"
    local source_file="${APT_SOURCES_DIR}/tailscale.list"
    local temporary_dir

    case "$CODENAME" in
        noble | resolute) ;;
        *)
            die "Tailscale repository is not configured for Ubuntu codename ${CODENAME}"
            ;;
    esac

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    fetch_file \
        "${repository_url}/${CODENAME}.noarmor.gpg" \
        "$temporary_dir/tailscale-archive-keyring.gpg" ||
        die "failed downloading the Tailscale signing key"
    validate_openpgp_key "$temporary_dir/tailscale-archive-keyring.gpg" "Tailscale"

    cat >"$temporary_dir/tailscale.list" <<EOF
deb [signed-by=${key_file}] ${repository_url} ${CODENAME} main
EOF
    validate_repository_source \
        "$temporary_dir/tailscale.list" \
        "$repository_url" \
        "$key_file"

    if write_file_if_changed "$temporary_dir/tailscale-archive-keyring.gpg" "$key_file"; then
        changed=true
        ok "installed Tailscale repository signing key"
    else
        info "Tailscale repository signing key already current"
    fi
    if write_file_if_changed "$temporary_dir/tailscale.list" "$source_file"; then
        changed=true
        ok "configured Tailscale repository"
    else
        info "Tailscale repository already configured"
    fi

    [[ "$changed" == false ]] || return 10
)

ensure_sublime_text_repository() (
    set -Eeuo pipefail

    local changed=false
    local key_file="${SYSTEM_KEYRING_DIR}/sublimehq-pub.asc"
    local source_file="${APT_SOURCES_DIR}/sublime-text.sources"
    local temporary_dir
    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    fetch_file \
        "https://download.sublimetext.com/sublimehq-pub.gpg" \
        "$temporary_dir/sublimehq-pub.asc" || die "failed downloading the Sublime Text signing key"
    validate_openpgp_key "$temporary_dir/sublimehq-pub.asc" "Sublime Text"

    cat >"$temporary_dir/sublime-text.sources" <<EOF
Types: deb
URIs: https://download.sublimetext.com/
Suites: apt/stable/
Signed-By: ${key_file}
EOF
    validate_repository_source \
        "$temporary_dir/sublime-text.sources" \
        "https://download.sublimetext.com/" \
        "$key_file"

    if write_file_if_changed "$temporary_dir/sublimehq-pub.asc" "$key_file"; then
        changed=true
        ok "installed Sublime Text repository signing key"
    else
        info "Sublime Text repository signing key already current"
    fi
    if write_file_if_changed "$temporary_dir/sublime-text.sources" "$source_file"; then
        changed=true
        ok "configured Sublime Text repository"
    else
        info "Sublime Text repository already configured"
    fi

    [[ "$changed" == false ]] || return 10
)

ensure_brave_browser_repository() (
    set -Eeuo pipefail

    local changed=false
    local key_file="${SYSTEM_KEYRING_DIR}/brave-browser-archive-keyring.gpg"
    local source_file="${APT_SOURCES_DIR}/brave-browser-release.sources"
    local temporary_dir
    local legacy_file
    local -a legacy_files=()
    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    fetch_file \
        "https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg" \
        "$temporary_dir/brave-browser-archive-keyring.gpg" || die "failed downloading the Brave signing key"
    fetch_file \
        "https://brave-browser-apt-release.s3.brave.com/brave-browser.sources" \
        "$temporary_dir/brave-browser-release.sources" || die "failed downloading the Brave repository definition"
    validate_openpgp_key "$temporary_dir/brave-browser-archive-keyring.gpg" "Brave"
    validate_repository_source \
        "$temporary_dir/brave-browser-release.sources" \
        "https://brave-browser-apt-release.s3.brave.com" \
        "$key_file"

    if write_file_if_changed "$temporary_dir/brave-browser-archive-keyring.gpg" "$key_file"; then
        changed=true
        ok "installed Brave repository signing key"
    else
        info "Brave repository signing key already current"
    fi
    if write_file_if_changed "$temporary_dir/brave-browser-release.sources" "$source_file"; then
        changed=true
        ok "configured Brave repository"
    else
        info "Brave repository already configured"
    fi

    shopt -s nullglob
    legacy_files=("${APT_SOURCES_DIR}"/brave-browser-*.list)
    shopt -u nullglob
    for legacy_file in "${legacy_files[@]}"; do
        apt_transaction_record_file "$legacy_file"
        rm -f -- "$legacy_file"
        changed=true
        info "removed legacy Brave repository file: ${legacy_file}"
    done

    [[ "$changed" == false ]] || return 10
)

ensure_dbeaver_repository() (
    set -Eeuo pipefail

    local changed=false
    local key_file="${SYSTEM_KEYRING_DIR}/dbeaver.gpg.key"
    local source_file="${APT_SOURCES_DIR}/dbeaver.list"
    local temporary_dir
    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    fetch_file \
        "https://dbeaver.io/debs/dbeaver.gpg.key" \
        "$temporary_dir/dbeaver.asc" || die "failed downloading the DBeaver signing key"
    dearmor_openpgp_key "$temporary_dir/dbeaver.asc" "$temporary_dir/dbeaver.gpg" "DBeaver"
    validate_openpgp_key "$temporary_dir/dbeaver.gpg" "DBeaver"

    cat >"$temporary_dir/dbeaver.list" <<EOF
deb [signed-by=${key_file}] https://dbeaver.io/debs/dbeaver-ce /
EOF
    validate_repository_source \
        "$temporary_dir/dbeaver.list" \
        "https://dbeaver.io/debs/dbeaver-ce" \
        "$key_file"

    if write_file_if_changed "$temporary_dir/dbeaver.gpg" "$key_file"; then
        changed=true
        ok "installed DBeaver repository signing key"
    else
        info "DBeaver repository signing key already current"
    fi
    if write_file_if_changed "$temporary_dir/dbeaver.list" "$source_file"; then
        changed=true
        ok "configured DBeaver repository"
    else
        info "DBeaver repository already configured"
    fi

    [[ "$changed" == false ]] || return 10
)

ensure_mullvad_repository() (
    set -Eeuo pipefail

    local architecture
    local changed=false
    local key_file="${SYSTEM_KEYRING_DIR}/mullvad-keyring.asc"
    local source_file="${APT_SOURCES_DIR}/mullvad.list"
    local temporary_dir
    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    if [[ "$UBUNTU_VARIANT" != "desktop" ]]; then
        info "Mullvad VPN is desktop-only; skipping"
        return 0
    fi

    architecture="$(dpkg --print-architecture)"
    fetch_file \
        "https://repository.mullvad.net/deb/mullvad-keyring.asc" \
        "$temporary_dir/mullvad-keyring.asc" || die "failed downloading the Mullvad signing key"
    validate_openpgp_key "$temporary_dir/mullvad-keyring.asc" "Mullvad"

    cat >"$temporary_dir/mullvad.list" <<EOF
deb [signed-by=${key_file} arch=${architecture}] https://repository.mullvad.net/deb/stable stable main
EOF
    validate_repository_source \
        "$temporary_dir/mullvad.list" \
        "https://repository.mullvad.net/deb/stable" \
        "$key_file"

    if write_file_if_changed "$temporary_dir/mullvad-keyring.asc" "$key_file"; then
        changed=true
        ok "installed Mullvad repository signing key"
    else
        info "Mullvad repository signing key already current"
    fi
    if write_file_if_changed "$temporary_dir/mullvad.list" "$source_file"; then
        changed=true
        ok "configured Mullvad repository"
    else
        info "Mullvad repository already configured"
    fi

    [[ "$changed" == false ]] || return 10
)

ensure_typora_repository() (
    set -Eeuo pipefail

    local changed=false
    local key_file="${SYSTEM_KEYRING_DIR}/typora.gpg"
    local legacy_key_file="${APT_TRUSTED_KEY_DIR}/typora.asc"
    local source_file="${APT_SOURCES_DIR}/typora.list"
    local temporary_dir

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    fetch_file \
        "https://downloads.typora.io/typora.gpg" \
        "$temporary_dir/typora.gpg" ||
        die "failed downloading the Typora signing key"
    validate_openpgp_key "$temporary_dir/typora.gpg" "Typora"

    cat >"$temporary_dir/typora.list" <<EOF
deb [signed-by=${key_file}] https://downloads.typora.io/linux ./
EOF
    validate_repository_source \
        "$temporary_dir/typora.list" \
        "https://downloads.typora.io/linux" \
        "$key_file"

    if write_file_if_changed "$temporary_dir/typora.gpg" "$key_file"; then
        changed=true
        ok "installed Typora repository signing key"
    else
        info "Typora repository signing key already current"
    fi
    if write_file_if_changed "$temporary_dir/typora.list" "$source_file"; then
        changed=true
        ok "configured Typora repository"
    else
        info "Typora repository already configured"
    fi
    if [[ -e "$legacy_key_file" ]]; then
        apt_transaction_record_file "$legacy_key_file"
        rm -f -- "$legacy_key_file"
        changed=true
        info "removed obsolete Typora repository key: ${legacy_key_file}"
    fi

    [[ "$changed" == false ]] || return 10
)

# -----------------------------------------------------------------------------
# Desktop applications and configuration
# -----------------------------------------------------------------------------

configure_flathub() (
    set -euo pipefail

    local remote_url="https://dl.flathub.org/repo/flathub.flatpakrepo"

    if [[ "$UBUNTU_VARIANT" != "desktop" ]]; then
        info "Flathub is desktop-only; skipping"
        return
    fi

    command -v flatpak >/dev/null 2>&1 || die "flatpak is required to configure Flathub"

    info "configuring the system-wide Flathub remote"

    flatpak remote-add --system --if-not-exists flathub "$remote_url"
    flatpak remote-modify --system --enable flathub

    flatpak remotes --system --columns=name | grep -qx flathub ||
        die "Flathub remote configuration could not be verified"

    ok "Flathub system remote configured"
)

install_termix() (
    set -Eeuo pipefail

    local app_id="com.karmaa.termix"
    local temporary_dir

    if [[ "$ARCH" != "amd64" ]]; then
        warn "Termix Flatpak bundle is only configured for amd64; skipping on ${ARCH}"
        return
    fi
    command -v flatpak >/dev/null 2>&1 ||
        die "flatpak is required to install Termix"

    if run_as_target_user flatpak info --user "$app_id" >/dev/null 2>&1; then
        info "Termix Flatpak already installed for ${TARGET_USER}, skipping"
        return
    fi

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    info "checking latest Termix GitHub release"
    info "downloading Termix Flatpak bundle"
    fetch_latest_github_asset \
        "Termix-SSH/Termix" \
        "exact" \
        "termix_linux_flatpak.flatpak" \
        "$temporary_dir/termix.flatpak" \
        "$temporary_dir/release.json" \
        "Termix Flatpak bundle"

    chmod 0755 "$temporary_dir"
    chmod 0644 "$temporary_dir/termix.flatpak"
    info "installing Termix Flatpak for ${TARGET_USER}"
    run_quiet_command "Termix Flatpak installation failed" \
        run_as_target_user flatpak install --user --noninteractive -y \
        "$temporary_dir/termix.flatpak" ||
        die "failed installing Termix Flatpak"
    run_as_target_user flatpak info --user "$app_id" >/dev/null 2>&1 ||
        die "Termix Flatpak installation could not be verified"
    ok "Termix Flatpak installed for ${TARGET_USER}"
)

install_termius() {
    if [[ "$ARCH" != "amd64" ]]; then
        warn "Termius DEB is only configured for amd64; skipping on ${ARCH}"
        return
    fi

    install_downloaded_debian_package \
        "https://download.termius.com/linux/Termius.deb" \
        "termius-app" \
        "Termius"
}

install_rustdesk() {
    local asset_suffix

    case "$ARCH" in
        amd64) asset_suffix="-x86_64.deb" ;;
        arm64) asset_suffix="-aarch64.deb" ;;
        *)
            warn "RustDesk release installation is not configured for ${ARCH}; skipping"
            return
            ;;
    esac

    install_latest_github_debian_package \
        "rustdesk/rustdesk" \
        "$asset_suffix" \
        "rustdesk" \
        "RustDesk"
}

install_pandoc() {
    local asset_suffix

    case "$ARCH" in
        amd64 | arm64) asset_suffix="-1-${ARCH}.deb" ;;
        *)
            warn "Pandoc release installation is not configured for ${ARCH}; skipping"
            return
            ;;
    esac

    install_latest_github_debian_package \
        "jgm/pandoc" \
        "$asset_suffix" \
        "pandoc" \
        "Pandoc"
}

install_typora_themeable() (
    set -Eeuo pipefail

    local installed_version release_version
    local typora_config_directory="${TARGET_HOME}/.config/Typora"
    local marker_file="${TARGET_HOME}/.config/Typora/themes/.packertron-themeable-version"
    local theme_directory="${TARGET_HOME}/.config/Typora/themes"
    local temporary_dir

    install -d \
        -m 0755 \
        -o "$TARGET_USER" \
        -g "$TARGET_GROUP" \
        "$typora_config_directory" \
        "$theme_directory"
    verify_target_ownership "$typora_config_directory" "Typora configuration directory"
    verify_target_ownership "$theme_directory" "Typora theme directory"

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    info "checking latest Typora Themeable release"
    fetch_latest_github_release_metadata \
        "jhildenbiddle/typora-themeable" \
        "$temporary_dir/release.json" \
        "Typora Themeable"
    release_version="$(jq -r '.tag_name // empty' "$temporary_dir/release.json")"
    [[ -n "$release_version" ]] ||
        die "Typora Themeable release metadata does not contain a version"

    installed_version=""
    [[ ! -f "$marker_file" ]] || installed_version="$(<"$marker_file")"
    if [[ "$installed_version" == "$release_version" &&
        -f "$theme_directory/themeable.css" ]]; then
        info "Typora Themeable ${release_version} already installed, skipping"
        return
    fi

    info "downloading Typora Themeable ${release_version}"
    fetch_github_asset_from_metadata \
        "exact" \
        "typora-themeable.zip" \
        "$temporary_dir/typora-themeable.zip" \
        "$temporary_dir/release.json" \
        "Typora Themeable archive"
    info "installing Typora Themeable ${release_version}"
    validate_zip_archive "$temporary_dir/typora-themeable.zip" "Typora Themeable"

    chmod 0755 "$temporary_dir"
    chmod 0644 "$temporary_dir/typora-themeable.zip"
    run_quiet_command "Typora Themeable extraction failed" \
        run_as_target_user unzip -q -o \
        "$temporary_dir/typora-themeable.zip" \
        -d "$theme_directory" ||
        die "failed installing Typora Themeable"
    [[ -f "$theme_directory/themeable.css" ]] ||
        die "Typora Themeable installation could not be verified"

    printf '%s\n' "$release_version" >"$temporary_dir/theme-version"
    install \
        -o "$TARGET_USER" \
        -g "$TARGET_GROUP" \
        -m 0644 \
        "$temporary_dir/theme-version" \
        "$marker_file"
    verify_target_ownership "$marker_file" "Typora Themeable version marker"
    ok "Typora Themeable ${release_version} installed for ${TARGET_USER}"
)

configure_desktop_wallpaper() (
    set -euo pipefail

    local source_file="${SCRIPT_DIR}/ubuntu-wallpaper.png"
    local destination_file

    [[ -d "$TARGET_HOME" ]] || die "target home directory is unavailable: ${TARGET_HOME}"
    destination_file="$TARGET_HOME/.config/background"

    [[ -f "$source_file" ]] ||
        die "wallpaper not found: ${source_file}"

    install -d \
        -o "$TARGET_USER" \
        -g "$TARGET_GROUP" \
        -m 0755 \
        "$TARGET_HOME/.config"

    install \
        -C \
        -o "$TARGET_USER" \
        -g "$TARGET_GROUP" \
        -m 0644 \
        "$source_file" \
        "$destination_file"

    ok "GNOME wallpaper file ready: ${destination_file}"
)

configure_terminator() (
    set -Eeuo pipefail

    local expected_config
    local temporary_dir

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT
    expected_config="$temporary_dir/config"

    cat >"$expected_config" <<'EOF'
[global_config]
  window_state = maximise
[keybindings]
[profiles]
  [[default]]
    font = JetBrainsMono Nerd Font Mono 16
    foreground_color = "#f6f5f4"
    show_titlebar = False
    scrollback_infinite = True
    disable_mousewheel_zoom = True
    use_system_font = False
[layouts]
  [[default]]
    [[[window0]]]
      type = Window
      parent = ""
    [[[child1]]]
      type = Terminal
      parent = window0
[plugins]
EOF

    install_target_config_file \
        "$expected_config" \
        "$TARGET_HOME/.config/terminator/config" \
        "Terminator"
)

configure_terminator_as_default() {
    local account="$1"
    local status
    local terminator_bin
    local desktop_file="${TERMINATOR_DESKTOP_FILE:-/usr/share/applications/terminator.desktop}"
    local desktop_id="terminator.desktop"

    [[ "$account" == "$TARGET_USER" ]] ||
        die "default terminal must be configured for the resolved target user"

    terminator_bin="$(command -v terminator 2>/dev/null || true)"
    if [[ -z "$terminator_bin" ]]; then
        warn "Terminator is not installed; cannot configure default terminal"
        return
    fi

    case "$VERSION_ID" in
        24.*)
            # Ubuntu 24.04: legacy system-wide alternatives mechanism.
            if ! grep -Fx -- "$terminator_bin" \
                < <(update-alternatives --list x-terminal-emulator 2>/dev/null); then
                warn "Terminator is not registered as an x-terminal-emulator alternative"
                return
            fi

            if [[ "$(readlink -f /etc/alternatives/x-terminal-emulator 2>/dev/null || true)" == "$terminator_bin" ]]; then
                info "Terminator already configured as system default terminal, skipping"
                return
            fi

            update-alternatives --set x-terminal-emulator "$terminator_bin"
            ok "Terminator configured as system default terminal on Ubuntu ${VERSION_ID}"
            ;;

        26.*)
            # Ubuntu 26.04: per-user xdg-terminal-exec configuration.
            if [[ ! -f "$desktop_file" ]]; then
                warn "Terminator desktop file not found: ${desktop_file}"
                return
            fi

            install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$TARGET_HOME/.config"

            if run_as_target_user bash -s -- "$desktop_id" <<'EOF'; then
set -euo pipefail

desktop_id="$1"
config_file="$HOME/.config/ubuntu-xdg-terminals.list"
tmp_file="$(mktemp "$HOME/.config/.ubuntu-xdg-terminals.list.XXXXXX")"

cleanup() {
  rm -f "$tmp_file"
}
trap cleanup EXIT

# Put Terminator first while preserving other configured terminals.
{
  printf '%s\n' "$desktop_id"

  if [[ -f "$config_file" ]]; then
    awk -v desktop_id="$desktop_id" '$0 != desktop_id' "$config_file"
  fi
} > "$tmp_file"

chmod 0644 "$tmp_file"
if [[ -f "$config_file" ]] && cmp -s -- "$tmp_file" "$config_file"; then
  exit 0
fi

mv -f "$tmp_file" "$config_file"
trap - EXIT
exit 10
EOF
                info "Terminator already configured as default terminal for ${account}, skipping"
            else
                status=$?
                [[ "$status" -eq 10 ]] ||
                    die "failed configuring Terminator as default terminal for ${account}"
                ok "Terminator configured as default terminal for ${account} on Ubuntu ${VERSION_ID}"
            fi
            ;;

        *)
            warn "default terminal configuration not implemented for Ubuntu ${VERSION_ID}"
            ;;
    esac
}

install_snap_package() {
    local snap_name="$1"
    local display_name="$2"

    if ! command -v snap >/dev/null 2>&1; then
        warn "snap command not found; cannot install ${display_name}"
        return 0
    fi

    if snap list "$snap_name" >/dev/null 2>&1; then
        info "${display_name} snap already installed, skipping"
        return 0
    fi

    if ! snap install "$snap_name"; then
        die "failed installing ${display_name} snap (${snap_name})"
    fi
    ok "${display_name} snap installed"
}

connect_snap_interface() {
    local connection="$1"
    local description="$2"

    if ! command -v snap >/dev/null 2>&1; then
        return 0
    fi

    if snap connect "$connection" >/dev/null 2>&1; then
        info "${description} interface connected"
    else
        warn "could not connect ${description} interface (${connection})"
    fi
}

install_flameshot() (
    set -euo pipefail

    local api_url="https://api.github.com/repos/flameshot-org/flameshot/releases/latest"
    local cmd
    local release_json tag latest_version installed_version
    local architecture platform asset_url asset_name asset_digest
    local tmp_dir deb_file checksum_file package_architecture package_name package_version
    local -a checksum_files deb_files
    local -a platform_candidates

    for cmd in curl jq unzip sha256sum dpkg dpkg-query dpkg-deb apt-get; do
        command -v "$cmd" >/dev/null 2>&1 ||
            die "${cmd} is required to install Flameshot"
    done

    architecture="$(dpkg --print-architecture)"
    case "$architecture" in
        amd64 | arm64) ;;
        *)
            warn "unsupported Flameshot architecture: ${architecture}"
            return
            ;;
    esac

    case "$VERSION_ID" in
        24.*)
            platform_candidates=("ubuntu-24.04")
            ;;
        26.*)
            # Use a native 26.04 artifact when upstream provides one;
            # otherwise fall back to the Ubuntu 24.04 package.
            platform_candidates=("ubuntu-26.04" "ubuntu-24.04")
            ;;
        *)
            warn "Flameshot release installation not configured for Ubuntu ${VERSION_ID}"
            return
            ;;
    esac

    tmp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$tmp_dir"' EXIT

    info "checking latest Flameshot GitHub release"

    fetch_file "$api_url" "$tmp_dir/release.json" ||
        die "failed downloading Flameshot release metadata"
    release_json="$(<"$tmp_dir/release.json")"
    tag="$(jq -r '.tag_name // empty' <<<"$release_json")" ||
        die "Flameshot release metadata is invalid"
    [[ -n "$tag" ]] || die "could not determine latest Flameshot release"

    latest_version="${tag#v}"
    installed_version="$(
        dpkg-query -W -f='${Version}' flameshot 2>/dev/null || true
    )"

    if [[ -n "$installed_version" ]] &&
        dpkg --compare-versions "$installed_version" ge "$latest_version"; then
        info "Flameshot ${installed_version} already installed, skipping"
        return
    fi

    asset_url=""
    for platform in "${platform_candidates[@]}"; do
        asset_url="$(
            jq -r \
                --arg suffix "artifact-${platform}-${architecture}.zip" \
                '[.assets[]
          | select(.name | endswith($suffix))
        ][0].browser_download_url // empty' \
                <<<"$release_json"
        )" || die "Flameshot release metadata is invalid"

        [[ -n "$asset_url" ]] && break
    done

    [[ -n "$asset_url" ]] ||
        die "no compatible Flameshot artifact for Ubuntu ${VERSION_ID}/${architecture}"

    asset_name="${asset_url##*/}"
    asset_digest="$(
        jq -r --arg name "$asset_name" '
      [.assets[] | select(.name == $name)][0].digest // empty
    ' <<<"$release_json"
    )" || die "Flameshot release metadata is invalid"

    info "downloading Flameshot ${tag} (${platform}/${architecture})"
    fetch_file "$asset_url" "$tmp_dir/$asset_name" ||
        die "failed downloading Flameshot ${tag}"
    verify_github_asset_digest "$tmp_dir/$asset_name" "$asset_digest" "Flameshot ${tag} archive"
    validate_zip_archive "$tmp_dir/$asset_name" "Flameshot ${tag}"

    mkdir "$tmp_dir/extracted"
    unzip -q "$tmp_dir/$asset_name" -d "$tmp_dir/extracted"

    mapfile -t deb_files < <(
        find "$tmp_dir/extracted" -maxdepth 2 -type f -name 'flameshot*.deb' -print
    )
    mapfile -t checksum_files < <(
        find "$tmp_dir/extracted" -maxdepth 2 -type f -name 'flameshot*.deb.sha256sum' -print
    )

    ((${#deb_files[@]} == 1)) ||
        die "Flameshot archive must contain exactly one Debian package"
    ((${#checksum_files[@]} == 1)) ||
        die "Flameshot archive must contain exactly one Debian package checksum"
    deb_file="${deb_files[0]}"
    checksum_file="${checksum_files[0]}"

    info "verifying Flameshot package checksum"
    (
        cd "$(dirname "$deb_file")"
        sha256sum --check "$(basename "$checksum_file")"
    )

    dpkg-deb --info "$deb_file" >/dev/null ||
        die "Flameshot Debian package is invalid"
    package_name="$(dpkg-deb -f "$deb_file" Package)"
    package_architecture="$(dpkg-deb -f "$deb_file" Architecture)"
    package_version="$(dpkg-deb -f "$deb_file" Version)"

    [[ "$package_name" == "flameshot" ]] ||
        die "unexpected Flameshot package name: ${package_name}"
    [[ "$package_architecture" == "$architecture" || "$package_architecture" == "all" ]] ||
        die "unexpected Flameshot package architecture: ${package_architecture}"
    dpkg --compare-versions "$package_version" ge "$latest_version" ||
        die "unexpected Flameshot package version: ${package_version}"

    info "installing Flameshot ${tag}"
    run_apt_get install -y "$deb_file"

    installed_version="$(
        dpkg-query -W -f='${Version}' flameshot 2>/dev/null || true
    )"

    [[ -n "$installed_version" ]] ||
        die "Flameshot installation could not be verified"

    ok "Flameshot ${installed_version} installed from the official GitHub release"
)

configure_flameshot() (
    set -Eeuo pipefail

    local expected_config
    local pictures_dir="${TARGET_HOME}/Pictures"
    local flameshot_dir="${TARGET_HOME}/Pictures/flameshot"
    local temporary_dir

    install -d \
        -m 0755 \
        -o "$TARGET_USER" \
        -g "$TARGET_GROUP" \
        "$pictures_dir" \
        "$flameshot_dir"

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT
    expected_config="$temporary_dir/flameshot.ini"

    cat >"$expected_config" <<EOF
[General]
contrastOpacity=188
copyOnDoubleClick=true
copyPathAfterSave=false
saveAfterCopy=true
saveAsFileExtension=png
saveLastRegion=false
savePath=${flameshot_dir}
savePathFixed=true
showHelp=false
showMagnifier=true
showStartupLaunchMessage=false
squareMagnifier=true
startupLaunch=true
EOF

    install_target_config_file \
        "$expected_config" \
        "$TARGET_HOME/.config/flameshot/flameshot.ini" \
        "Flameshot"
)

install_obsidian() (
    set -euo pipefail

    local api_url="https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest"
    local cmd
    local release_json tag latest_version
    local architecture asset_url asset_name asset_digest package_architecture package_version
    local installed_version tmp_dir deb_file package_name
    local snap_installed=false

    for cmd in curl jq sha256sum dpkg dpkg-query dpkg-deb apt-get; do
        command -v "$cmd" >/dev/null 2>&1 ||
            die "${cmd} is required to install Obsidian"
    done

    architecture="$(dpkg --print-architecture)"
    case "$architecture" in
        amd64 | arm64) ;;
        *)
            warn "unsupported Obsidian architecture: ${architecture}"
            return
            ;;
    esac

    if command -v snap >/dev/null 2>&1 &&
        snap list obsidian >/dev/null 2>&1; then
        snap_installed=true
    fi

    tmp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$tmp_dir"' EXIT

    info "checking latest Obsidian GitHub release"

    fetch_file "$api_url" "$tmp_dir/release.json" ||
        die "failed downloading Obsidian release metadata"
    release_json="$(<"$tmp_dir/release.json")"
    tag="$(jq -r '.tag_name // empty' <<<"$release_json")" ||
        die "Obsidian release metadata is invalid"
    [[ -n "$tag" ]] ||
        die "could not determine the latest Obsidian release"

    latest_version="${tag#v}"

    installed_version="$(
        dpkg-query -W -f='${Version}' obsidian 2>/dev/null || true
    )"

    if [[ -n "$installed_version" ]] &&
        dpkg --compare-versions "$installed_version" ge "$latest_version"; then
        if [[ "$snap_installed" == true ]]; then
            info "removing duplicate Obsidian snap"
            snap remove obsidian || die "failed removing duplicate Obsidian snap"
        fi
        info "Obsidian ${installed_version} already installed, skipping"
        return
    fi

    asset_url="$(
        jq -r --arg arch "$architecture" '
      first(
        .assets[]
        | select(.name | endswith("_" + $arch + ".deb"))
        | .browser_download_url
      ) // empty
    ' <<<"$release_json"
    )" || die "Obsidian release metadata is invalid"

    [[ -n "$asset_url" ]] ||
        die "no Obsidian Debian package found for ${architecture}"

    asset_name="${asset_url##*/}"

    asset_digest="$(
        jq -r --arg name "$asset_name" '
      [.assets[] | select(.name == $name)][0].digest // empty
    ' <<<"$release_json"
    )" || die "Obsidian release metadata is invalid"

    deb_file="$tmp_dir/$asset_name"

    info "downloading Obsidian ${tag} for ${architecture}"
    fetch_file "$asset_url" "$deb_file" ||
        die "failed downloading Obsidian ${tag}"
    [[ -s "$deb_file" ]] || die "downloaded Obsidian package is empty"

    verify_github_asset_digest "$deb_file" "$asset_digest" "Obsidian ${tag} package"

    dpkg-deb --info "$deb_file" >/dev/null ||
        die "downloaded Obsidian Debian package is invalid"

    package_name="$(dpkg-deb -f "$deb_file" Package)"
    package_architecture="$(dpkg-deb -f "$deb_file" Architecture)"
    package_version="$(dpkg-deb -f "$deb_file" Version)"
    [[ "$package_name" == "obsidian" ]] ||
        die "unexpected Debian package name: ${package_name}"
    [[ "$package_architecture" == "$architecture" || "$package_architecture" == "all" ]] ||
        die "unexpected Obsidian package architecture: ${package_architecture}"
    dpkg --compare-versions "$package_version" ge "$latest_version" ||
        die "unexpected Obsidian package version: ${package_version}"

    info "installing Obsidian ${tag}"
    run_apt_get install -y "$deb_file"

    installed_version="$(
        dpkg-query -W -f='${Version}' obsidian 2>/dev/null || true
    )"

    [[ -n "$installed_version" ]] ||
        die "Obsidian installation could not be verified"

    if [[ "$snap_installed" == true ]]; then
        info "removing duplicate Obsidian snap"
        snap remove obsidian || die "failed removing duplicate Obsidian snap"
    fi

    ok "Obsidian ${installed_version} installed from the official GitHub release"
)

# -----------------------------------------------------------------------------
# Common user tools and shell configuration
# -----------------------------------------------------------------------------

prepare_user_workspace() (
    set -euo pipefail

    local account="${1:-$USER_NAME}"
    local home
    local group
    local repos_root
    local obsidian_dir
    local ssh_dir

    home="$(user_home "$account")"
    [[ -n "$home" && -d "$home" ]] ||
        die "could not determine home directory for ${account}"

    group="$(id -gn "$account")"

    data_dir="$home/data"
    docker_dir="$home/docker"
    gdrive_dir="$home/gdrive"
    repos_root="$home/repos"
    obsidian_dir="$home/obsidian"
    ssh_dir="$home/.ssh"

    info "preparing workspace directories for ${account}"

    install -d \
        -o "$account" \
        -g "$group" \
        -m 0755 \
        "$data_dir" \
        "$docker_dir" \
        "$gdrive_dir" \
        "$repos_root" \
        "$repos_root/github" \
        "$repos_root/gitlab" \
        "$repos_root/forgejo" \
        "$obsidian_dir"

    install -d \
        -o "$account" \
        -g "$group" \
        -m 0700 \
        "$ssh_dir"

    ok "Data directory ready: ${data_dir}"
    ok "Docker directory ready: ${docker_dir}"
    ok "Google Drive directory ready: ${gdrive_dir}"
    ok "GitHub repository directory ready: ${repos_root}/github"
    ok "GitLab repository directory ready: ${repos_root}/gitlab"
    ok "Forgejo repository directory ready: ${repos_root}/forgejo"
    ok "Obsidian directory ready: ${obsidian_dir}"
    ok "SSH directory ready: ${ssh_dir}"
)

install_tldr_pipx() {
    local installed_packages

    if ! installed_packages="$(run_as_target_user pipx list --short 2>/dev/null)"; then
        die "could not inspect pipx packages for ${TARGET_USER}"
    fi

    if grep -Eq '^tldr[[:space:]]' <<<"$installed_packages"; then
        info "tldr already installed via pipx, skipping"
        return
    fi

    run_quiet_command "pipx tldr installation" run_as_target_user pipx install tldr ||
        die "failed installing tldr via pipx"
    run_quiet_command "pipx PATH configuration" run_as_target_user pipx ensurepath ||
        die "failed configuring the pipx application path"

    if ! installed_packages="$(run_as_target_user pipx list --short 2>/dev/null)"; then
        die "could not verify pipx packages for ${TARGET_USER}"
    fi
    grep -Eq '^tldr[[:space:]]' <<<"$installed_packages" ||
        die "tldr installation could not be verified"
    ok "tldr installed via pipx"
}

install_fzf_for_user() {
    local account="$1"
    local home
    home="$(user_home "$account")"
    [[ -n "$home" ]] || die "could not determine home directory for ${account}"

    if [[ -d "$home/.fzf/.git" && -x "$home/.fzf/bin/fzf" && -f "$home/.fzf.bash" ]]; then
        info "fzf already installed for ${account}, skipping"
        return
    elif [[ -d "$home/.fzf/.git" ]]; then
        info "repairing incomplete fzf installation for ${account}"
    elif [[ -e "$home/.fzf" ]]; then
        warn "${home}/.fzf exists but is not a Git checkout; skipping fzf for ${account}"
        return
    else
        info "cloning fzf for ${account}"
        timeout --foreground 180 \
            sudo -u "$account" -H git \
            -c http.lowSpeedLimit=1024 \
            -c http.lowSpeedTime=30 \
            clone --quiet --depth 1 \
            https://github.com/junegunn/fzf.git "$home/.fzf" ||
            die "fzf clone failed or timed out for ${account}"
    fi

    run_quiet_command \
        "fzf installer for ${account}" \
        sudo -u "$account" -H "$home/.fzf/install" \
        --all --no-update-rc --no-zsh --no-fish --no-nushell ||
        die "fzf installation failed for ${account}"

    [[ -x "$home/.fzf/bin/fzf" && -f "$home/.fzf.bash" ]] ||
        die "fzf installation could not be verified for ${account}"
    ok "fzf installed for ${account}"
}

install_starship() (
    set -Eeuo pipefail

    local line
    local temporary_dir
    local version_output

    if command -v starship >/dev/null 2>&1; then
        version_output="$(starship --version)" || die "existing Starship command is not usable"
        [[ "$version_output" == starship* ]] || die "existing Starship version could not be verified"
        info "${version_output%%$'\n'*} already installed, skipping"
        return
    fi

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    info "installing Starship"
    fetch_file "$STARSHIP_INSTALL_URL" "$temporary_dir/install.sh" ||
        die "failed downloading the Starship installer"

    [[ -s "$temporary_dir/install.sh" ]] || die "downloaded Starship installer is empty"
    sh -n "$temporary_dir/install.sh" || die "downloaded Starship installer is not valid shell"

    if ! sh "$temporary_dir/install.sh" --yes >"$temporary_dir/install.log" 2>&1; then
        while IFS= read -r line; do
            error "Starship installer: ${line}"
        done <"$temporary_dir/install.log"
        die "Starship installation failed"
    fi

    command -v starship >/dev/null 2>&1 || die "Starship installation did not provide a starship command"
    ok "Starship installed"
)

install_jetbrainsmono_nerd_font_for_user() (
    set -Eeuo pipefail

    local account="$1"
    local account_group
    local account_uid
    local api_url="https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest"
    local asset_digest
    local asset_url
    local command_name
    local home
    local matched_family
    local release_json
    local temporary_dir
    local -a account_command

    for command_name in curl fc-cache fc-match jq sha256sum unzip; do
        command -v "$command_name" >/dev/null 2>&1 ||
            die "${command_name} is required to install JetBrainsMono Nerd Font"
    done

    home="$(user_home "$account")"
    [[ -n "$home" ]] || die "could not determine home directory for ${account}"
    account_uid="$(id -u "$account")"
    account_group="$(id -gn "$account")"

    if [[ "$account" == "$TARGET_USER" ]]; then
        account_command=(run_as_target_user)
    else
        account_command=(
            sudo -u "$account" -g "$account_group" -H env
            HOME="$home"
            USER="$account"
            LOGNAME="$account"
            TARGET_USER="$account"
            TARGET_HOME="$home"
            TARGET_UID="$account_uid"
            TARGET_GROUP="$account_group"
        )
    fi

    matched_family="$(
        "${account_command[@]}" \
            fc-match --format='%{family}\n' 'JetBrainsMono Nerd Font' 2>/dev/null
    )" || die "could not inspect fonts for ${account}"

    if [[ "$matched_family" == *"JetBrainsMono Nerd Font"* ]]; then
        info "JetBrainsMono Nerd Font already installed for ${account}, skipping"
        return
    fi

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT
    chmod 0755 "$temporary_dir"

    info "checking latest JetBrainsMono Nerd Font release"
    fetch_file "$api_url" "$temporary_dir/release.json" ||
        die "failed downloading JetBrainsMono Nerd Font release metadata"
    release_json="$(<"$temporary_dir/release.json")"
    asset_url="$(
        jq -r '
      [.assets[] | select(.name == "JetBrainsMono.zip")][0].browser_download_url // empty
    ' <<<"$release_json"
    )" || die "JetBrainsMono Nerd Font release metadata is invalid"
    asset_digest="$(
        jq -r '
      [.assets[] | select(.name == "JetBrainsMono.zip")][0].digest // empty
    ' <<<"$release_json"
    )" || die "JetBrainsMono Nerd Font release metadata is invalid"
    [[ -n "$asset_url" ]] ||
        die "JetBrainsMono Nerd Font archive is missing from the latest release"

    info "downloading JetBrainsMono Nerd Font for ${account}"
    fetch_file "$asset_url" "$temporary_dir/JetBrainsMono.zip" ||
        die "failed downloading JetBrainsMono Nerd Font"
    verify_github_asset_digest \
        "$temporary_dir/JetBrainsMono.zip" \
        "$asset_digest" \
        "JetBrainsMono Nerd Font archive"
    validate_zip_archive "$temporary_dir/JetBrainsMono.zip" "JetBrainsMono Nerd Font"
    chmod 0644 "$temporary_dir/JetBrainsMono.zip"

    if ! run_quiet_command \
        "JetBrainsMono Nerd Font installer for ${account}" \
        "${account_command[@]}" \
        bash -s -- "$temporary_dir/JetBrainsMono.zip" <<'USER_INSTALL'; then
set -Eeuo pipefail

archive="$1"
font_dir="$HOME/.local/share/fonts"
mkdir -p "$font_dir"
unzip -q -o "$archive" -d "$font_dir"
fc-cache -f "$font_dir"
USER_INSTALL
        die "JetBrainsMono Nerd Font installation failed for ${account}"
    fi

    matched_family="$(
        "${account_command[@]}" \
            fc-match --format='%{family}\n' 'JetBrainsMono Nerd Font' 2>/dev/null
    )" || die "could not verify fonts for ${account}"
    [[ "$matched_family" == *"JetBrainsMono Nerd Font"* ]] ||
        die "JetBrainsMono Nerd Font installation could not be verified for ${account}"
    ok "JetBrainsMono Nerd Font installed for ${account}"
)

ensure_bat_symlink_for_user() {
    local account="$1"
    local home="$2"
    local bat_link="$home/.local/bin/bat"

    if [[ -L "$bat_link" && "$(readlink -- "$bat_link")" == "/usr/bin/batcat" ]]; then
        return
    fi

    if [[ ! -d "$home/.local/bin" ]]; then
        sudo -u "$account" -H mkdir -p "$home/.local/bin"
    fi

    if [[ -L "$bat_link" ]]; then
        sudo -u "$account" -H ln -sfn /usr/bin/batcat "$bat_link"
    elif [[ -e "$bat_link" ]]; then
        warn "${bat_link} is not a symlink; preserving it"
    else
        sudo -u "$account" -H ln -s /usr/bin/batcat "$bat_link"
    fi
}

configure_bash_for_user() {
    local account="$1"
    local home
    local update_scope="system"
    home="$(user_home "$account")"
    [[ -n "$home" ]] || die "could not determine home directory for ${account}"

    if [[ "$UBUNTU_VARIANT" == "desktop" && "$account" == "$TARGET_USER" ]]; then
        update_scope="desktop-user"
    fi

    ensure_bat_symlink_for_user "$account" "$home"

    sudo -u "$account" -H python3 - "$home" "$update_scope" <<'PY'
from datetime import datetime
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

home = Path(sys.argv[1])
update_scope = sys.argv[2]
bashrc = home / ".bashrc"
aliases_path = home / ".bash_aliases"

aliases = r'''# $HOME/.bash_aliases — centralized interactive aliases

# System update
@UPDATEOS_ALIAS@

# Core utils
alias brave='brave-browser'
alias cat='batcat -pp'
alias df='df -h'
alias diff='diff --color=auto'
alias dir='dir --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'
alias fd='fdfind -H'
alias grep='grep --color=auto'
alias vdir='vdir --color=auto'
alias which-command='type'

# Listing
alias ls='ls -lh --color=auto'
alias la='ls -A'
alias l='eza -lah --group-directories-first'
alias ll='l -T'

# History
alias h='history'
alias hl='history | less'
alias hs='history | grep'
alias hsi='history | grep -i'

# Network / ports
alias ip='ip --color=auto'
alias ipa='ip -br -c a'
alias ports='ss -tunlp'
alias publicip='curl -4 ifconfig.me && echo'

# Python
alias p3='python3'
alias python='python3'

# Search
alias ugq='ugrep --pretty --hidden -Qria'

# Mask stdin after first 5 chars
alias mask='awk '\''{ printf substr($0, 1, 5); for (i=6; i<=length($0); i++) printf "*"; print "" }'\'''

# Preserve alias expansion after sudo
alias sudo='sudo '

# Ubuntu default long-running command notification
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'
'''

if update_scope == "desktop-user":
    updateos_alias = """alias updateos='sudo sh -c \"apt update && apt -y upgrade && apt -y autoremove && snap refresh && flatpak update -y\" && brew upgrade'"""
elif update_scope == "system":
    updateos_alias = """alias updateos='sudo sh -c \"apt update && apt -y upgrade && apt -y autoremove\"'"""
else:
    raise SystemExit(f"unsupported update scope: {update_scope}")

aliases = aliases.replace("@UPDATEOS_ALIAS@", updateos_alias)

fzf_block = r'''# >>> fzf (managed) >>>
export FZF_DEFAULT_OPTS='-m --height 50% --border'
export FZF_CTRL_R_OPTS="$FZF_DEFAULT_OPTS"
export FZF_CTRL_T_OPTS="$FZF_DEFAULT_OPTS"
export FZF_ALT_C_OPTS="$FZF_DEFAULT_OPTS"

[ -f "$HOME/.fzf.bash" ] && source "$HOME/.fzf.bash"
# <<< fzf (managed) <<<'''

fastfetch_block = r'''# >>> fastfetch (managed) >>>
# Fastfetch - login shells only
if shopt -q login_shell && command -v fastfetch >/dev/null 2>&1; then
    clear
    fastfetch
fi
# <<< fastfetch (managed) <<<'''

starship_block = r'''# >>> starship (managed) >>>
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
else
  PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
fi
# <<< starship (managed) <<<'''

dotfiles_hook = r'''# >>> future dotfiles hook (disabled) >>>
# DOTFILES_REPO_URL="https://github.com/<owner>/<dotfiles-repository>.git"
# DOTFILES_DIR="$HOME/.local/share/dotfiles"
# if [ -d "$DOTFILES_DIR/.git" ]; then
#   git -C "$DOTFILES_DIR" pull --ff-only
# else
#   git clone "$DOTFILES_REPO_URL" "$DOTFILES_DIR"
# fi
# "$DOTFILES_DIR/install.sh"
# <<< future dotfiles hook (disabled) <<<'''

def backup(path: Path) -> None:
    stamp = datetime.now().strftime("%Y-%m-%d-%H%M%S")
    destination = path.with_name(f"{path.name}.bak.{stamp}")
    counter = 1
    while destination.exists():
        destination = path.with_name(f"{path.name}.bak.{stamp}.{counter}")
        counter += 1
    shutil.copy2(path, destination)

def install_if_changed(path: Path, content: str) -> bool:
    content = content.rstrip() + "\n"
    old = path.read_text(encoding="utf-8") if path.exists() else None
    if old == content:
        return False

    path.parent.mkdir(parents=True, exist_ok=True)
    fd, candidate_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    candidate = Path(candidate_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(content)
        subprocess.run(["bash", "-n", str(candidate)], check=True)
        if path.exists():
            backup(path)
            candidate.chmod(path.stat().st_mode & 0o777)
        else:
            candidate.chmod(0o644)
        os.replace(candidate, path)
    finally:
        candidate.unlink(missing_ok=True)
    return True

def set_line(content: str, pattern: str, replacement: str) -> str:
    if re.search(pattern, content, flags=re.M):
        replaced = False

        def replace_once(match: re.Match[str]) -> str:
            nonlocal replaced
            if not replaced:
                replaced = True
                return replacement
            return ""

        return re.sub(pattern, replace_once, content, flags=re.M)
    return content.rstrip() + "\n" + replacement + "\n"

source = bashrc.read_text(encoding="utf-8") if bashrc.exists() else ""

# Comment active aliases while preserving indentation and commented aliases.
source = re.sub(
    r'^(?![ \t]*#)([ \t]*)(alias[ \t].*)$',
    r'\1# \2',
    source,
    flags=re.M,
)

source = set_line(source, r'^[ \t]*HISTCONTROL=.*$', 'HISTCONTROL=ignoreboth:erasedups')
source = set_line(source, r'^[ \t]*HISTSIZE=.*$', 'HISTSIZE=50000')
source = set_line(source, r'^[ \t]*HISTFILESIZE=.*$', 'HISTFILESIZE=100000')
source = re.sub(r'^[ \t]*HISTTIMEFORMAT=.*\n?', '', source, flags=re.M)
source = re.sub(
    r'(^HISTFILESIZE=.*$)',
    lambda match: match.group(1) + "\nHISTTIMEFORMAT='%F %T '",
    source,
    count=1,
    flags=re.M,
)
source = set_line(source, r'^[ \t]*PROMPT_COMMAND=.*$', "PROMPT_COMMAND='history -a; history -n'")
source = set_line(source, r'^[ \t]*#?[ \t]*shopt -s checkwinsize.*$', 'shopt -s checkwinsize')
source = set_line(source, r'^[ \t]*#?[ \t]*shopt -s globstar.*$', 'shopt -s globstar 2>/dev/null')
source = re.sub(r'^[ \t]*#?[ \t]*set -o vi[ \t]*\n?', '', source, flags=re.M)

for name in ("fzf", "fastfetch", "starship", "future dotfiles hook"):
    source = re.sub(
        rf'\n?# >>> {re.escape(name)} \((?:managed|disabled)\) >>>.*?# <<< {re.escape(name)} \((?:managed|disabled)\) <<<\n?',
        '\n',
        source,
        flags=re.S,
    )

source = re.sub(
    r'^[ \t]*\[ -[fr] (?:~|"\$HOME)/\.fzf\.bash"? \] && source (?:~|"\$HOME)/\.fzf\.bash"?[ \t]*\n?',
    '',
    source,
    flags=re.M,
)

if not re.search(r'^[^#\n]*\.bash_aliases', source, flags=re.M):
    source = source.rstrip() + r'''

# Load centralized aliases.
if [ -f "$HOME/.bash_aliases" ]; then
  . "$HOME/.bash_aliases"
fi
'''

source = source.rstrip() + "\n\n" + fzf_block + "\n\n" + fastfetch_block + "\n\n" + starship_block + "\n\n" + dotfiles_hook + "\n"

install_if_changed(aliases_path, aliases)
install_if_changed(bashrc, source)
PY

    sudo -u "$account" -H bash -n "$home/.bashrc"
    sudo -u "$account" -H bash -n "$home/.bash_aliases"
    ok "Bash configuration installed for ${account}"
}

configure_starship_for_user() {
    local account="$1"
    local home
    home="$(user_home "$account")"
    [[ -n "$home" ]] || die "could not determine home directory for ${account}"

    sudo -u "$account" -H python3 - "$home" <<'PY'
from datetime import datetime
from pathlib import Path
import os
import shutil
import sys
import tempfile

home = Path(sys.argv[1])
path = home / ".config" / "starship.toml"
content = """format = \"\"\"
${custom.root_marker}\\
$username\\
${custom.directory_icon}\\
$directory\\
$git_branch\\
$git_status\\
$fill\\
$hostname\\
$jobs\\
$cmd_duration\\
$status\\
$time\\
$line_break\\
$character\"\"\"

add_newline = false

[custom.root_marker]
command = "printf ''"
when = 'test "$(id -u)" -eq 0'
format = "[$output]($style) "
style = "bold red"

[username]
show_always = true
format = "[$user]($style) "
style_user = "bold yellow"
style_root = "bold red"

[custom.directory_icon]
command = '''
if [ "$PWD" = "$HOME" ]; then
    printf ''
else
    printf ''
fi
'''
when = true
format = "[$output]($style) "
style = "bold cyan"

[directory]
format = "[$path]($style) "
style = "bold cyan"
home_symbol = "~"
truncation_length = 3
truncation_symbol = "…/"
truncate_to_repo = false
read_only = " "
read_only_style = "bold red"

[git_branch]
symbol = " "
format = "[$symbol$branch]($style) "
style = "bold green"

[git_status]
format = "([$all_status$ahead_behind]($style) )"
style = "bold yellow"

[hostname]
ssh_only = true
format = "[$ssh_symbol$hostname]($style) "
style = "dimmed cyan"
ssh_symbol = "󰣀 "

[jobs]
symbol = " "
format = "[$symbol$number]($style) "
style = "bold red"
number_threshold = 1

[cmd_duration]
min_time = 2000
format = "[$duration]($style) "
style = "dimmed yellow"

[status]
disabled = false
format = "[$symbol$signal_name$maybe_int]($style) "
symbol = "✘ "
sigint_symbol = "✘ "
signal_symbol = "✘ "
not_executable_symbol = "✘ "
not_found_symbol = "✘ "
recognize_signal_code = true
map_symbol = false
style = "bold red"

[time]
disabled = false
format = "[ $time]($style)"
time_format = "%H:%M:%S"
style = "bold cyan"

[character]
format = "$symbol "
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"

[fill]
symbol = " "
"""

content = content.rstrip() + "\n"
old = path.read_text(encoding="utf-8") if path.exists() else None
if old != content:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        stamp = datetime.now().strftime("%Y-%m-%d-%H%M%S")
        backup = path.with_name(f"{path.name}.bak.{stamp}")
        counter = 1
        while backup.exists():
            backup = path.with_name(f"{path.name}.bak.{stamp}.{counter}")
            counter += 1
        shutil.copy2(path, backup)
    fd, candidate_name = tempfile.mkstemp(prefix=".starship.toml.", dir=path.parent)
    candidate = Path(candidate_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(content)
        candidate.chmod(0o644)
        os.replace(candidate, path)
    finally:
        candidate.unlink(missing_ok=True)
PY
    ok "Starship configuration installed for ${account}"
}

configure_git_for_user() {
    local account="$1"
    local changed=false
    local current
    local git_name="syselement"
    local git_email="81392234+syselement@users.noreply.github.com"

    if ! id "$account" >/dev/null 2>&1; then
        warn "user not found: ${account}; skipping Git configuration"
        return
    fi

    [[ "$account" == "$TARGET_USER" ]] ||
        die "Git configuration account does not match target user: ${account}"

    if ! current="$(run_as_target_user git config --global --get user.name 2>/dev/null)"; then
        current=""
    fi
    if [[ "$current" != "$git_name" ]]; then
        run_as_target_user git config --global user.name "$git_name"
        changed=true
    fi

    if ! current="$(run_as_target_user git config --global --get user.email 2>/dev/null)"; then
        current=""
    fi
    if [[ "$current" != "$git_email" ]]; then
        run_as_target_user git config --global user.email "$git_email"
        changed=true
    fi

    if ! current="$(run_as_target_user git config --global --get pull.rebase 2>/dev/null)"; then
        current=""
    fi
    if [[ "$current" != "true" ]]; then
        run_as_target_user git config --global pull.rebase true
        changed=true
    fi

    if ! current="$(run_as_target_user git config --global --get rebase.autoStash 2>/dev/null)"; then
        current=""
    fi
    if [[ "$current" != "true" ]]; then
        run_as_target_user git config --global rebase.autoStash true
        changed=true
    fi

    if [[ "$(
        run_as_target_user git config --global --get user.name
    )" != "$git_name" ]] ||
        [[ "$(
            run_as_target_user git config --global --get user.email
        )" != "$git_email" ]] ||
        [[ "$(
            run_as_target_user git config --global --get pull.rebase
        )" != "true" ]] ||
        [[ "$(
            run_as_target_user git config --global --get rebase.autoStash
        )" != "true" ]]; then
        die "failed to configure Git for ${account}"
    fi

    if [[ "$changed" == true ]]; then
        ok "Git configured for ${account}: identity and pull-rebase policy"
    else
        info "Git already configured for ${account}, skipping"
    fi
}

homebrew_cpu_is_supported() {
    case "$(uname -m)" in
        x86_64 | amd64)
            [[ -r /proc/cpuinfo ]] && grep -Eq '(^|[[:space:]])ssse3([[:space:]]|$)' /proc/cpuinfo
            ;;
        aarch64 | arm64)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

homebrew_is_usable() {
    local brew_bin="$1"

    [[ -x "$brew_bin" ]] || return 1
    run_as_target_user "$brew_bin" --prefix >/dev/null 2>&1 &&
        run_as_target_user "$brew_bin" --version >/dev/null 2>&1
}

configure_homebrew_bash() {
    local brew_bin="$1"
    local shellenv_line="eval \"\$(${brew_bin} shellenv)\""

    run_as_target_user bash -s -- "$brew_bin" <<'TARGET_BASHRC'
set -euo pipefail

brew_bin="$1"
rc="$HOME/.bashrc"
line="eval \"\$(${brew_bin} shellenv)\""

touch "$rc"

if ! grep -Fqx "$line" "$rc"; then
  {
    printf "\n# Homebrew\n"
    printf "%s\n" "$line"
  } >> "$rc"
fi
TARGET_BASHRC

    run_as_target_user grep -Fqx "$shellenv_line" "$TARGET_HOME/.bashrc" ||
        die "failed to configure Homebrew in ${TARGET_HOME}/.bashrc"
}

install_homebrew_for_user() (
    set -Eeuo pipefail

    local architecture
    local configured_prefix
    local installer_file
    local prefix="$HOMEBREW_PREFIX"
    local brew_bin="${prefix}/bin/brew"
    local temporary_dir
    local version_output

    architecture="$(uname -m)"
    if ! homebrew_cpu_is_supported; then
        if [[ "$architecture" == "x86_64" || "$architecture" == "amd64" ]]; then
            warn "Homebrew requires SSSE3 on x86_64; the current CPU flags do not expose it, skipping Homebrew"
        else
            warn "Homebrew does not support architecture ${architecture} in this workflow, skipping Homebrew"
        fi
        return 0
    fi

    if homebrew_is_usable "$brew_bin"; then
        info "Homebrew already installed; skipping installer prerequisites"
    else
        if [[ -e "$brew_bin" ]]; then
            warn "existing Homebrew installation is incomplete; rerunning the installer"
        fi

        install_package_array "Homebrew prerequisite" \
            build-essential \
            procps \
            curl \
            file \
            git

        info "staging Homebrew installer for ${TARGET_USER}"

        temporary_dir="$(mktemp -d)"
        trap 'rm -rf -- "$temporary_dir"' EXIT
        chmod 0755 "$temporary_dir"
        installer_file="${temporary_dir}/install.sh"

        fetch_file "$HOMEBREW_INSTALL_URL" "$installer_file" ||
            die "failed downloading the Homebrew installer"
        [[ -s "$installer_file" ]] || die "downloaded Homebrew installer is empty"
        chmod 0644 "$installer_file"
        bash -n "$installer_file" || die "downloaded Homebrew installer is not valid Bash"

        # Pre-create the supported Linux prefix so the non-interactive installer does not require password-based sudo access.
        if [[ ! -d "$(dirname -- "$prefix")" ]]; then
            install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$(dirname -- "$prefix")"
        fi
        if [[ ! -d "$prefix" ]]; then
            install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$prefix"
        fi
        verify_target_ownership "$prefix" "Homebrew prefix"

        if ! run_quiet_command \
            "Homebrew installer" \
            run_as_target_user env NONINTERACTIVE=1 /bin/bash "$installer_file"; then
            die "Homebrew installation failed"
        fi

        [[ -x "$brew_bin" ]] ||
            die "Homebrew installation did not provide ${brew_bin}"
    fi

    verify_target_ownership "$prefix" "Homebrew prefix"
    verify_target_ownership "$brew_bin" "Homebrew binary"

    configured_prefix="$(run_as_target_user "$brew_bin" --prefix)" ||
        die "Homebrew prefix verification failed"
    [[ "$configured_prefix" == "$prefix" ]] ||
        die "Homebrew reported unexpected prefix: ${configured_prefix}"

    version_output="$(run_as_target_user "$brew_bin" --version)" ||
        die "Homebrew version verification failed"
    [[ "$version_output" == Homebrew* ]] || die "Homebrew version verification failed"

    configure_homebrew_bash "$brew_bin"
    ok "${version_output%%$'\n'*} installed and verified for ${TARGET_USER}"
    info "Homebrew Bash setup is ready; start a new shell or run: source ${TARGET_HOME}/.bashrc"
)

# -----------------------------------------------------------------------------
# Manual post-install instructions
# -----------------------------------------------------------------------------

show_manual_setup_hints() {
    local home
    local instruction_number=0
    home="$(user_home "$USER_NAME")"

    section "Manual Post-Install Setup"

    if [[ "$UBUNTU_VARIANT" == "desktop" ]]; then
        manual_step "$((instruction_number += 1)). Fingerprint login"
        manual_line "Open: Settings → System → Users → Fingerprint Login"
        manual_line "Enroll at least two fingers and verify sudo authentication."

        manual_step "$((instruction_number += 1)). Keyboard shortcuts"
        manual_line "Open: Settings → Keyboard → View and Customize Shortcuts"
        manual_line "Then: Custom Shortcuts → Add Shortcut"
        manual_item "Flameshot"
        manual_line "Command:"
        manual_command "script --quiet --command \"/usr/bin/flameshot gui --clipboard --path ${home}/Pictures/flameshot\" /dev/null"
        manual_line "Shortcut: Print or Shift+Alt+S"
        manual_item "Emote"
        manual_line "Command:"
        manual_command "/snap/bin/emote"
        manual_line "Shortcut: Super+Comma (Windows key + ,)"

        manual_step "$((instruction_number += 1)). Bluetooth devices"
        manual_line "Open: Settings → Bluetooth"
        manual_line "Pair the mouse, soundbar, and other devices."

        manual_step "$((instruction_number += 1)). Visual Studio Code"
        manual_line "Open: VS Code → Accounts → Sign in with GitHub"
        manual_line "Enable Settings Sync and verify restored extensions and settings."

        manual_step "$((instruction_number += 1)). Bitwarden and Ente Auth"
        manual_line "Sign in, complete MFA, and verify vault synchronization."

        manual_step "$((instruction_number += 1)). Brave"
        manual_line "Open: brave://settings/braveSync/setup"
        manual_line "Join the existing sync chain and verify bookmarks and extensions."

        manual_step "$((instruction_number += 1)). Obsidian"
        manual_line "Vault path: ${home}/obsidian"
        manual_line "Configure Obsidian Sync, Git, or the selected backup method."

        manual_step "$((instruction_number += 1)). Telegram"
        manual_line "Sign in and verify the session."
    fi

    manual_step "$((instruction_number += 1)). SSH private key"
    manual_line "Copy the private key from a trusted offline source or password manager:"
    manual_command "cat > ${home}/.ssh/id_ed25519"
    manual_line "Paste the key, then press Ctrl-D."
    manual_command "chmod 600 ${home}/.ssh/id_ed25519"
    manual_line "Generate the matching public key:"
    manual_command "ssh-keygen -y -f ${home}/.ssh/id_ed25519 > ${home}/.ssh/id_ed25519.pub"
    manual_command "chmod 0644 ${home}/.ssh/id_ed25519.pub"
    manual_line "Load and test the key:"
    manual_command "ssh-add ${home}/.ssh/id_ed25519 || { eval \"\$(ssh-agent -s)\"; ssh-add ${home}/.ssh/id_ed25519; }"
    manual_command "ssh -T git@github.com"

    manual_step "$((instruction_number += 1)). Tailscale client"
    manual_command "sudo tailscale up"
    manual_line "Open the authentication URL, then verify the connection:"
    manual_command "tailscale status"

    manual_step "$((instruction_number += 1)). WireGuard connection"
    manual_line "Add the WireGuard configuration to /etc/wireguard/wg0.conf, then import it:"
    manual_command "sudo nmcli connection import type wireguard file /etc/wireguard/wg0.conf"

    manual_step "$((instruction_number += 1)). Cockpit web console"
    manual_line "Visit: https://localhost:9090/"

    manual_step "$((instruction_number += 1)). Clone Git repositories over SSH"
    manual_item "GitHub:  cd ${home}/repos/github"
    manual_item "GitLab:  cd ${home}/repos/gitlab"
    manual_item "Forgejo: cd ${home}/repos/forgejo"
    manual_command "git clone git@github.com:syselement/<repository>.git"
    manual_line "Verify the configured Git identity:"
    manual_command "git config list"

    manual_step "$((instruction_number += 1)). Virtualization"
    manual_line "Log out and back in, or reboot, before managing virtual machines."
    manual_line "This applies the new libvirt group membership."
    if [[ "$UBUNTU_VARIANT" == "desktop" ]]; then
        manual_line "Open Virtual Machine Manager:"
        manual_command "virt-manager --connect qemu:///system"
    else
        manual_line "Manage this headless host with virsh or a remote virt-manager client."
    fi
    manual_line "Verify the local system connection and network state:"
    manual_command "virsh --connect qemu:///system list --all"
    manual_command "virsh --connect qemu:///system net-list --all"
}

# -----------------------------------------------------------------------------
# Main entry point
# -----------------------------------------------------------------------------

main() {
    local end_ts elapsed start_ts

    initialize_runtime

    section "Run Context"
    info "run_id=${RUN_ID}"
    info "started_at=$(date -Is)"
    start_ts="$(date +%s)"

    info "distro version=${VERSION_ID} codename=${CODENAME} variant=${UBUNTU_VARIANT} variant_source=${UBUNTU_VARIANT_SOURCE} arch=${ARCH}"
    info "execution mode=${EXECUTION_MODE} context=${EXECUTION_CONTEXT} interactive=${EXECUTION_INTERACTIVE}"
    ok "target user=${TARGET_USER} home=${TARGET_HOME}"

    apt_transaction_recover

    section "Connectivity"
    info "checking Internet connectivity and DNS resolution"
    if ping -c 1 -W 1 1.1.1.1 &>/dev/null || ping -c 1 -W 1 8.8.8.8 &>/dev/null || ping -c 1 -W 1 9.9.9.9 &>/dev/null; then
        ok "Internet connectivity available (ICMP)"
    else
        warn "Internet connectivity unavailable over ICMP"
    fi

    if getent hosts ubuntu.com >/dev/null 2>&1; then
        ok "DNS resolution available (ubuntu.com)"
    else
        warn "DNS resolution unavailable (ubuntu.com)"
    fi

    section "System Update"
    info "running APT update and dist-upgrade"
    run_apt_get update -qq
    run_apt_get dist-upgrade -y -qq
    ok "APT update and dist-upgrade completed"

    if [[ "$UBUNTU_VARIANT" == "desktop" ]]; then
        if command -v snap >/dev/null 2>&1; then
            info "refreshing Snap packages"
            if timeout --foreground 15m snap refresh; then
                ok "Snap refresh completed"
            else
                warn "Snap refresh failed or timed out; continuing"
            fi
        else
            warn "Snap command unavailable; refresh skipped"
        fi
    else
        info "Server detected; Desktop Snap refresh skipped"
    fi

    install_package_array "APT bootstrap" "${APT_BOOTSTRAP_PACKAGES[@]}"
    if [[ "$VERSION_ID" == 24.* ]]; then
        install_package_array "Ubuntu 24 repository bootstrap" software-properties-common
    fi

    section "Repositories"
    apt_transaction_begin
    info "ensuring common repositories"
    ensure_fastfetch_ppa
    apply_repository_setup install_docker_ctop_repository
    apply_repository_setup ensure_tailscale_repository

    if [[ "$UBUNTU_VARIANT" == "desktop" ]]; then
        info "ensuring Desktop application repositories"
        apply_repository_setup ensure_brave_browser_repository
        apply_repository_setup ensure_dbeaver_repository
        apply_repository_setup ensure_mullvad_repository
        apply_repository_setup ensure_sublime_text_repository
        apply_repository_setup ensure_typora_repository
    else
        info "Server detected; Desktop application repositories skipped"
    fi

    if [[ "$APT_SOURCES_CHANGED" == true ]]; then
        info "apt update after repository changes"
        if ! run_apt_get update -qq; then
            warn "APT update failed after repository changes; restoring previous repository state"
            apt_transaction_rollback
            die "APT repository validation failed; previous repository state restored"
        fi
    else
        info "APT repositories unchanged; existing package cache is current"
    fi
    apt_transaction_commit
    ok "Repository configuration completed"

    section "Packages"
    install_package_array "common" "${COMMON_PACKAGES[@]}"
    install_available_package_array "release-optional" "${RELEASE_OPTIONAL_PACKAGES[@]}"
    configure_cockpit_socket
    install_pandoc
    if [[ "$UBUNTU_VARIANT" == "desktop" ]]; then
        install_package_array "Desktop" "${DESKTOP_PACKAGES[@]}"
        configure_flathub
        install_flatpak_package_array "Desktop Flatpak" "${FLATPAK_PACKAGES[@]}"
        install_rustdesk
        install_termius
        install_termix
        install_typora_themeable
    else
        info "Server detected; Desktop packages skipped"
    fi
    ok "Package installation completed"

    section "Virtualization"
    install_virtualization_stack
    configure_libvirt
    validate_virtualization_stack
    ok "Virtualization configuration completed"

    section "User Environment"
    info "installing common user tools and shell configuration"
    prepare_user_workspace "$USER_NAME"
    install_starship
    for account in "$USER_NAME" root; do
        install_fzf_for_user "$account"
        install_jetbrainsmono_nerd_font_for_user "$account"
        configure_bash_for_user "$account"
        configure_starship_for_user "$account"
    done
    install_tldr_pipx
    configure_git_for_user "$USER_NAME"
    install_homebrew_for_user
    ok "common user tools and shell configuration completed"

    section "Desktop Configuration"
    if [[ "$UBUNTU_VARIANT" == "desktop" ]]; then
        info "installing/configuring Desktop-specific tools"
        configure_desktop_wallpaper
        install_flameshot
        configure_flameshot
        install_obsidian
        configure_terminator
        configure_terminator_as_default "$USER_NAME"
        install_snap_package discord "Discord"
        connect_snap_interface discord:system-observe "Discord system-observe"
        install_snap_package emote "Emote"
        install_snap_package postman "Postman"
        install_snap_package telegram-desktop "Telegram Desktop"
        ok "Desktop-specific tools installed/configured"
    else
        info "Server detected; Desktop configuration skipped"
    fi

    info "updating locate database (best effort)"
    updatedb || true

    section "GNOME"
    if [[ "$UBUNTU_VARIANT" == "desktop" ]]; then
        # Apply now, inside this provisioning run. When GNOME is already running,
        # target its real per-user bus; during headless SSH/Vagrant provisioning,
        # use the temporary-bus fallback from run_as_gnome_user().
        install_dim_background_windows_extension "$USER_NAME"
        install_hide_universal_access_extension "$USER_NAME"
        install_system_monitor_panel_extension "$USER_NAME"
        apply_gnome_preferences
        enable_battery_health_preservation
    else
        info "Server detected; GNOME configuration skipped"
    fi

    section "Cleanup"
    info "removing unused APT packages and cleaning the package cache"
    run_apt_get -y -qq autoremove --purge
    run_apt_get -y clean
    ok "cleanup completed"

    show_manual_setup_hints

    end_ts="$(date +%s)"
    elapsed="$((end_ts - start_ts))"
    section "Summary"
    info "completed_at=$(date -Is)"
    info "elapsed=$(printf '%02d:%02d:%02d' "$((elapsed / 3600))" "$((elapsed % 3600 / 60))" "$((elapsed % 60))")"
    info "log_file=${LOG_FILE}"
    info "run_id=${RUN_ID}"
    ok "System customization complete"

    if [[ "$REBOOT_AT_END" == "true" ]]; then
        info "rebooting in 10 seconds"
        sleep 10
        sync
        shutdown -r now
    else
        info "reboot deferred to orchestrator"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
