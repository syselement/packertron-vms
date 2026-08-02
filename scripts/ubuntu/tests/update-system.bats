#!/usr/bin/env bats
# ShellCheck cannot infer function calls made through sourced code and Bats.
# shellcheck disable=SC1091,SC2329

setup() {
    UPDATE_SCRIPT="$BATS_TEST_DIRNAME/../00-update-system.sh"

    # shellcheck source=../00-update-system.sh
    source "$UPDATE_SCRIPT"

    log() {
        printf 'LOG: %s\n' "$*"
    }
}

@test "all update-system APT operations use the dpkg lock timeout" {
    local apt_record="$BATS_TEST_TMPDIR/apt-record"

    apt-get() {
        printf '%s\n' "$@" >"$apt_record"
    }

    run_apt_get install -y test-package

    grep -Fxq 'DPkg::Lock::Timeout=300' "$apt_record"
    grep -Fxq 'test-package' "$apt_record"
}

@test "VMware installs base and available Desktop integration separately" {
    local apt_record="$BATS_TEST_TMPDIR/apt-record"
    local service_record="$BATS_TEST_TMPDIR/service-record"

    PACKERTRON_VIRTUALIZATION_TYPE="vmware"
    run_apt_get() {
        printf '%s\n' "$*" >>"$apt_record"
    }
    ubuntu_desktop_is_installed() { return 0; }
    package_is_available() { [[ "$1" == "open-vm-tools-desktop" ]]; }
    configure_guest_service() {
        printf '%s\n' "$1" >"$service_record"
    }

    install_guest_tools

    [[ "$(wc -l <"$apt_record")" -eq 2 ]]
    grep -Fq 'open-vm-tools' "$apt_record"
    grep -Fq 'open-vm-tools-desktop' "$apt_record"
    [[ "$(<"$service_record")" == "open-vm-tools.service" ]]
}

@test "VMware base-package failure is not treated as a missing Desktop package" {
    local apt_record="$BATS_TEST_TMPDIR/apt-record"

    PACKERTRON_VIRTUALIZATION_TYPE="vmware"
    run_apt_get() {
        printf '%s\n' "$*" >>"$apt_record"
        return 42
    }
    ubuntu_desktop_is_installed() { return 0; }
    package_is_available() { return 0; }
    configure_guest_service() {
        printf 'unexpected service configuration\n' >&2
        return 99
    }

    run install_guest_tools

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"failed installing open-vm-tools"* ]]
    [[ "$(wc -l <"$apt_record")" -eq 1 ]]
    [[ "$output" != *"unexpected service configuration"* ]]
}

@test "KVM QEMU and Proxmox install qemu-guest-agent" {
    local virtualization
    local apt_record="$BATS_TEST_TMPDIR/apt-record"
    local service_record="$BATS_TEST_TMPDIR/service-record"

    run_apt_get() {
        printf '%s\n' "$*" >"$apt_record"
    }
    configure_guest_service() {
        printf '%s\n' "$1" >"$service_record"
    }

    for virtualization in kvm qemu proxmox; do
        # shellcheck disable=SC2034
        PACKERTRON_VIRTUALIZATION_TYPE="$virtualization"
        install_guest_tools
        grep -Fq 'qemu-guest-agent' "$apt_record"
        [[ "$(<"$service_record")" == "qemu-guest-agent.service" ]]
    done
}

@test "static guest-agent units do not require enablement" {
    local systemctl_record="$BATS_TEST_TMPDIR/systemctl-record"

    SYSTEMD_RUNTIME_DIR="$BATS_TEST_TMPDIR/run/systemd/system"
    mkdir -p "$SYSTEMD_RUNTIME_DIR"
    systemctl() {
        case "$1" in
            cat) return 0 ;;
            is-enabled)
                printf 'static\n'
                return 1
                ;;
            is-active) return 0 ;;
            *)
                printf '%s\n' "$*" >>"$systemctl_record"
                return 99
                ;;
        esac
    }

    configure_guest_service qemu-guest-agent.service

    [[ ! -e "$systemctl_record" ]]
}
