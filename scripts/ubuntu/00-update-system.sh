#!/usr/bin/env bash
#
# Update an Ubuntu VM template and install the appropriate guest agent.
#

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

SYSTEMD_RUNTIME_DIR="${PACKERTRON_SYSTEMD_RUNTIME_DIR:-/run/systemd/system}"

readonly -a BASE_PACKAGES=(
    net-tools
    unzip
)

log() { printf '[update] %s\n' "$*"; }
die() {
    printf '[update] ERROR: %s\n' "$*" >&2
    exit 1
}

run_apt_get() {
    apt-get -o DPkg::Lock::Timeout=300 "$@"
}

package_is_available() {
    apt-cache show "$1" >/dev/null 2>&1
}

ubuntu_desktop_is_installed() {
    local package
    local status

    for package in ubuntu-desktop ubuntu-desktop-minimal; do
        if status="$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null)" &&
            [[ "$status" == "install ok installed" ]]; then
            return 0
        fi
    done
    return 1
}

detect_virtualization() {
    local detected

    if [[ -n "${PACKERTRON_VIRTUALIZATION_TYPE:-}" ]]; then
        printf '%s\n' "$PACKERTRON_VIRTUALIZATION_TYPE"
    elif detected="$(systemd-detect-virt --vm 2>/dev/null)"; then
        printf '%s\n' "$detected"
    else
        printf 'none\n'
    fi
}

configure_guest_service() {
    local unit="$1"
    local enablement

    if [[ ! -d "$SYSTEMD_RUNTIME_DIR" ]]; then
        log "systemd is not running; ${unit} activation deferred until boot"
        return
    fi

    systemctl cat "$unit" >/dev/null 2>&1 || die "installed guest service is missing: ${unit}"

    if ! enablement="$(systemctl is-enabled "$unit" 2>/dev/null)"; then
        case "$enablement" in
            disabled | static | indirect | generated | linked | linked-runtime) ;;
            *) die "cannot determine enablement state for ${unit}: ${enablement:-unknown}" ;;
        esac
    fi
    case "$enablement" in
        disabled) systemctl enable "$unit" ;;
        enabled | enabled-runtime | static | indirect | generated | linked | linked-runtime | alias) ;;
        *) die "unsupported enablement state for ${unit}: ${enablement}" ;;
    esac
    if ! systemctl is-active --quiet "$unit"; then
        systemctl start "$unit"
    fi
}

install_guest_tools() {
    local virtualization

    virtualization="$(detect_virtualization)"
    log "detected virtualization: ${virtualization}"

    case "$virtualization" in
        vmware)
            run_apt_get install -y --no-install-recommends open-vm-tools ||
                die "failed installing open-vm-tools"
            if ubuntu_desktop_is_installed; then
                if package_is_available open-vm-tools-desktop; then
                    run_apt_get install -y --no-install-recommends open-vm-tools-desktop ||
                        die "failed installing open-vm-tools-desktop"
                else
                    log "open-vm-tools-desktop is unavailable; keeping base VMware guest tools"
                fi
            fi
            configure_guest_service open-vm-tools.service
            ;;
        kvm | qemu | proxmox)
            run_apt_get install -y --no-install-recommends qemu-guest-agent ||
                die "failed installing qemu-guest-agent"
            configure_guest_service qemu-guest-agent.service
            ;;
        *)
            log "no guest-agent package selected for ${virtualization}"
            ;;
    esac
}

main() {
    [[ "$EUID" -eq 0 ]] || die "run as root"

    log "apt update / dist-upgrade"
    run_apt_get update
    run_apt_get dist-upgrade -y

    log "install baseline tools"
    run_apt_get install -y --no-install-recommends "${BASE_PACKAGES[@]}"

    install_guest_tools
    log "done updating system and installing necessary packages"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
