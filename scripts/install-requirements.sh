#!/usr/bin/env bash
#
# Report, and optionally install, the host tooling this repository needs.
# Checks by default and changes nothing; installing is an explicit argument.
#
# Docs:
#   Packer     https://developer.hashicorp.com/packer/install
#   Vagrant    https://developer.hashicorp.com/vagrant/install
#   gitleaks   https://github.com/gitleaks/gitleaks
#   README.md  what the Proxmox and VMware paths each need
#
# Run:
#   scripts/install-requirements.sh            # report what is missing
#   scripts/install-requirements.sh install    # install what is missing
#   scripts/install-requirements.sh install --with-vmware
#
# APT only: this installs through apt-get and the HashiCorp APT repository, so
# it targets Ubuntu and Debian. On anything else it reports what is missing and
# leaves installing to you.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly SCRIPT_DIR REPO_ROOT

readonly KEYRING_DIR=/etc/apt/keyrings
readonly HASHICORP_KEYRING="$KEYRING_DIR/hashicorp-archive-keyring.gpg"
readonly HASHICORP_LIST=/etc/apt/sources.list.d/hashicorp.list

# The HashiCorp APT repository publishes per-codename suites and lags new
# Ubuntu releases. Override when your codename has no suite yet:
#   PACKERTRON_HASHICORP_SUITE=noble scripts/install-requirements.sh install
HASHICORP_SUITE="${PACKERTRON_HASHICORP_SUITE:-}"

WITH_VMWARE=false
INSTALL=false
missing_core=0
missing_optional=0

log() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

# First line only: several of these print a banner.
tool_version() {
    local command_name="$1"
    case "$command_name" in
        packer) packer version 2>/dev/null | head -1 ;;
        vagrant) vagrant --version 2>/dev/null | head -1 ;;
        cloud-init) cloud-init --version 2>&1 | head -1 ;;
        bats) bats --version 2>/dev/null | head -1 ;;
        gitleaks) gitleaks version 2>/dev/null | head -1 ;;
        *) "$command_name" --version 2>/dev/null | head -1 ;;
    esac
}

report() {
    local state="$1" command_name="$2" purpose="$3"
    local version=""

    if [[ "$state" == ok ]]; then
        version="$(tool_version "$command_name" || true)"
        printf '   ok      %-14s %s\n' "$command_name" "${version:-installed}"
    else
        printf '   MISSING %-14s %s\n' "$command_name" "$purpose"
    fi
}

# Core tooling is what scripts/check-templates.sh and the Bats suite need. A
# missing one means the checks cannot run at all, so it fails this script.
check_core() {
    local entry command_name purpose
    local -a core=(
        "packer:builds and validates every template"
        "cloud-init:validates the autoinstall seeds (Linux only)"
        "shellcheck:lints every Bash script"
        "shfmt:checks Bash formatting"
        "bats:runs the scripts/ubuntu test suite"
        "git:required by gitleaks and the release workflow"
    )

    log ''
    log '== core'
    for entry in "${core[@]}"; do
        command_name="${entry%%:*}"
        purpose="${entry#*:}"
        if have "$command_name"; then
            report ok "$command_name" "$purpose"
        else
            report missing "$command_name" "$purpose"
            missing_core=$((missing_core + 1))
        fi
    done
}

check_optional() {
    local entry command_name purpose
    local -a optional=(
        "gitleaks:scans the tree and history for committed secrets"
    )
    if [[ "$WITH_VMWARE" == true ]]; then
        optional+=("vagrant:runs the VMware desktop boxes")
    fi

    log ''
    log '== optional'
    for entry in "${optional[@]}"; do
        command_name="${entry%%:*}"
        purpose="${entry#*:}"
        if have "$command_name"; then
            report ok "$command_name" "$purpose"
        else
            report missing "$command_name" "$purpose"
            missing_optional=$((missing_optional + 1))
        fi
    done
}

# Not installable from here: the download needs a Broadcom account, and the
# Vagrant plugin has to be installed as the user who will run Vagrant.
check_vmware_manual() {
    [[ "$WITH_VMWARE" == true ]] || return 0

    log ''
    log '== manual (VMware path)'
    if have vmware || have vmrun; then
        printf '   ok      %-14s %s\n' vmware "VMware Workstation found"
    else
        printf '   MANUAL  %-14s %s\n' vmware \
            "install VMware Workstation Pro: https://support.broadcom.com/group/ecx/free-downloads"
    fi
    if have vagrant && vagrant plugin list 2>/dev/null | grep -q vagrant-vmware-desktop; then
        printf '   ok      %-14s %s\n' vagrant-plugin "vagrant-vmware-desktop installed"
    else
        printf '   MANUAL  %-14s %s\n' vagrant-plugin \
            "vagrant plugin install vagrant-vmware-desktop (as your own user, not root)"
    fi
}

require_apt() {
    have apt-get || die "no apt-get: install the missing tools with your own package manager"
    have sudo || die "no sudo: run this as a user that can elevate"
}

apt_update_done=false
apt_update() {
    [[ "$apt_update_done" == false ]] || return 0
    sudo apt-get update
    apt_update_done=true
}

apt_install() {
    apt_update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends "$@"
}

# Keyring under /etc/apt/keyrings with signed-by, never apt-key. Downloaded to
# a temporary file and dearmored before it is trusted.
ensure_hashicorp_repository() {
    local tmp_key suite

    if [[ -s "$HASHICORP_KEYRING" && -s "$HASHICORP_LIST" ]]; then
        return 0
    fi

    have curl || apt_install curl ca-certificates gnupg
    have gpg || apt_install gnupg

    suite="$HASHICORP_SUITE"
    if [[ -z "$suite" ]]; then
        suite="$(. /etc/os-release && printf '%s' "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")"
    fi
    [[ -n "$suite" ]] || die "cannot determine the distribution codename; set PACKERTRON_HASHICORP_SUITE"

    log "   adding the HashiCorp APT repository (suite: ${suite})"
    tmp_key="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '$tmp_key'" RETURN

    curl --fail --show-error --location --silent \
        --output "$tmp_key" https://apt.releases.hashicorp.com/gpg ||
        die "failed downloading the HashiCorp signing key"
    sudo install -d -m 0755 "$KEYRING_DIR"
    sudo gpg --batch --yes --dearmor --output "$HASHICORP_KEYRING" "$tmp_key" ||
        die "failed dearmoring the HashiCorp signing key"
    sudo chmod 0644 "$HASHICORP_KEYRING"

    printf 'deb [arch=%s signed-by=%s] https://apt.releases.hashicorp.com %s main\n' \
        "$(dpkg --print-architecture)" "$HASHICORP_KEYRING" "$suite" |
        sudo tee "$HASHICORP_LIST" >/dev/null

    apt_update_done=false
    apt_update || die "apt update failed; the repository has no suite for '${suite}' - retry with PACKERTRON_HASHICORP_SUITE=noble"
}

install_core() {
    local -a apt_packages=()

    have shellcheck || apt_packages+=(shellcheck)
    have shfmt || apt_packages+=(shfmt)
    have bats || apt_packages+=(bats)
    have cloud-init || apt_packages+=(cloud-init)
    have git || apt_packages+=(git)

    if ((${#apt_packages[@]} > 0)); then
        log "   installing: ${apt_packages[*]}"
        apt_install "${apt_packages[@]}"
    fi

    if ! have packer; then
        ensure_hashicorp_repository
        log '   installing: packer'
        apt_install packer
    fi
}

install_optional() {
    if ! have gitleaks; then
        # Not in the Ubuntu archive. Installing it means fetching a release
        # binary, which needs a checksum this script cannot pin sensibly, so it
        # stays a pointer rather than an unverified download.
        warn "gitleaks is not packaged for Ubuntu; install it from https://github.com/gitleaks/gitleaks/releases"
    fi

    if [[ "$WITH_VMWARE" == true ]] && ! have vagrant; then
        ensure_hashicorp_repository
        log '   installing: vagrant'
        apt_install vagrant
    fi
}

summary() {
    log ''
    if ((missing_core > 0)); then
        if [[ "$INSTALL" == true ]]; then
            die "${missing_core} core tool(s) still missing after installing"
        fi
        printf '%d core tool(s) missing. Install them with:\n' "$missing_core" >&2
        printf '  scripts/install-requirements.sh install\n' >&2
        return 1
    fi

    log 'all core tooling present'
    ((missing_optional == 0)) || log "${missing_optional} optional tool(s) missing; see above"
    log ''
    log 'Next:'
    log '  scripts/check-templates.sh          # the checks CI runs'
    log '  (cd scripts/ubuntu && bats tests)   # the provisioning test suite'
}

usage() {
    printf 'usage: %s [check|install] [--with-vmware]\n' "${BASH_SOURCE[0]##*/}" >&2
    exit 2
}

main() {
    local argument

    for argument in "$@"; do
        case "$argument" in
            check) INSTALL=false ;;
            install) INSTALL=true ;;
            --with-vmware) WITH_VMWARE=true ;;
            -h | --help) usage ;;
            *)
                printf 'unknown argument: %s\n' "$argument" >&2
                usage
                ;;
        esac
    done

    log "packertron-vms host requirements (repository: ${REPO_ROOT})"

    if [[ "$INSTALL" == true ]]; then
        require_apt
        log ''
        log '== installing'
        install_core
        install_optional
        missing_core=0
        missing_optional=0
    fi

    check_core
    check_optional
    check_vmware_manual
    summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
