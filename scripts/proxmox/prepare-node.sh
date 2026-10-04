#!/usr/bin/env bash
#
# Prepare a Proxmox VE node for this repository: the automation@pve user, its
# IACDeploy role, ACL and API token for Packer and OpenTofu, and the snippets
# content type first-boot provisioning needs. With --with-vdi, also the
# vdi@pve user and its CV4PVEVDI role for the cv4pve-vdi client.
#
# Every step reads the current state first, so a rerun changes nothing. The
# roles are set to exactly the privileges below; any other privilege on them
# is removed, and the difference is printed first. The token secret is shown
# once, when the token is created - Proxmox never shows it again.
#
# Docs:
#   pveum      https://pve.proxmox.com/pve-docs/pveum.1.html
#   README.md  ../../templates/proxmox/README.md, what each privilege is for
#
# Run, from the workstation (the node needs no copy of this repository):
#   ssh root@pve02 'bash -s -- --dry-run' <scripts/proxmox/prepare-node.sh
#   ssh root@pve02 'bash -s' <scripts/proxmox/prepare-node.sh
#   ssh root@pve02 'bash -s -- --with-vdi --storage local' <scripts/proxmox/prepare-node.sh

set -Eeuo pipefail

readonly AUTOMATION_USER="automation@pve"
readonly AUTOMATION_ROLE="IACDeploy"
readonly AUTOMATION_TOKEN="deploy"
readonly -a AUTOMATION_PRIVILEGES=(
    Datastore.Allocate
    Datastore.AllocateSpace
    Datastore.AllocateTemplate
    Datastore.Audit
    SDN.Use
    VM.Allocate
    VM.Audit
    VM.Clone
    VM.Config.CDROM
    VM.Config.CPU
    VM.Config.Cloudinit
    VM.Config.Disk
    VM.Config.HWType
    VM.Config.Memory
    VM.Config.Network
    VM.Config.Options
    VM.Console
    VM.GuestAgent.Audit
    VM.PowerMgmt
)

readonly VDI_USER="vdi@pve"
readonly VDI_ROLE="CV4PVEVDI"
readonly -a VDI_PRIVILEGES=(
    VM.Audit
    VM.Console
    VM.GuestAgent.Audit
    VM.PowerMgmt
)

DRY_RUN=false
WITH_VDI=false
SNIPPET_STORAGE="local"

log() { printf '[node] %s\n' "$*"; }
die() {
    printf '[node] error: %s\n' "$*" >&2
    exit 1
}

usage() {
    printf 'usage: prepare-node.sh [--dry-run] [--with-vdi] [--storage <id>]\n' >&2
    exit 2
}

require_root() {
    [[ "$EUID" -eq 0 ]] || die "run as root on the node, or with --dry-run"
}

# Every change goes through here, so --dry-run is complete by construction.
change() {
    if [[ "$DRY_RUN" == true ]]; then
        printf '[node] would run:'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    printf '[node] run:'
    printf ' %q' "$@"
    printf '\n'
    "$@"
}

pve_get() {
    pvesh get "$1" --output-format json 2>/dev/null
}

sorted_csv() {
    printf '%s\n' "$@" | sort -u | paste -sd, -
}

role_privileges_csv() {
    pve_get "/access/roles/$1" |
        grep -o '"[A-Za-z0-9.]*":1' |
        sed 's/^"\(.*\)":1$/\1/' |
        sort -u |
        paste -sd, -
}

ensure_role() {
    local role="$1"
    shift
    local wanted current

    wanted="$(sorted_csv "$@")"
    if ! pve_get "/access/roles/$role" >/dev/null; then
        change pveum role add "$role" --privs "$wanted"
        return
    fi

    current="$(role_privileges_csv "$role" || true)"
    if [[ "$current" == "$wanted" ]]; then
        log "role ${role} already has exactly its privileges"
        return
    fi
    log "role ${role} differs:"
    comm -3 <(tr ',' '\n' <<<"$wanted") <(tr ',' '\n' <<<"$current") |
        sed -e 's/^\t\(.*\)/    remove \1/' -e 's/^\([^ ].*\)/    add    \1/'
    change pveum role modify "$role" --privs "$wanted"
}

ensure_user() {
    local user="$1" comment="$2"

    if pve_get "/access/users/$user" >/dev/null; then
        log "user ${user} exists"
        return
    fi
    change pveum user add "$user" --comment "$comment"
}

acl_present() {
    local path="$1" user="$2" role="$3"

    pve_get /access/acl |
        grep -o '{[^{}]*}' |
        grep -F "\"path\":\"${path}\"" |
        grep -F "\"ugid\":\"${user}\"" |
        grep -qF "\"roleid\":\"${role}\""
}

ensure_acl() {
    local path="$1" user="$2" role="$3"

    if acl_present "$path" "$user" "$role"; then
        log "${user} already holds ${role} on ${path}"
        return
    fi
    change pveum acl modify "$path" --users "$user" --roles "$role"
}

# Privilege separation off: a separated token starts with no privileges and
# every call it makes is denied.
ensure_token() {
    local user="$1" token="$2"

    if pve_get "/access/users/$user/token/$token" >/dev/null; then
        log "token ${user}!${token} exists; its secret was shown once, when it was created"
        return
    fi
    change pveum user token add "$user" "$token" --privsep 0
    [[ "$DRY_RUN" == true ]] ||
        log "save the secret above now; Proxmox never shows it again. PROXMOX_VE_API_TOKEN is ${user}!${token}=<secret>"
}

# --content replaces the whole list, so the storage keeps what it had.
ensure_snippets() {
    local storage="$1" content

    content="$(pve_get "/storage/$storage" | grep -o '"content":"[^"]*"' | cut -d '"' -f 4)" ||
        die "storage ${storage} not found"
    [[ -n "$content" ]] || die "storage ${storage} not found"

    if [[ ",${content}," == *,snippets,* ]]; then
        log "storage ${storage} already carries snippets"
        return
    fi
    change pvesm set "$storage" --content "${content},snippets"
}

main() {
    while (($# > 0)); do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --with-vdi)
                WITH_VDI=true
                shift
                ;;
            --storage)
                [[ -n "${2:-}" ]] || usage
                SNIPPET_STORAGE="$2"
                shift 2
                ;;
            *) usage ;;
        esac
    done

    if ! command -v pveum >/dev/null 2>&1 || ! command -v pvesh >/dev/null 2>&1; then
        die "pveum and pvesh not found; run this on a Proxmox VE node"
    fi
    [[ "$DRY_RUN" == true ]] || require_root

    ensure_role "$AUTOMATION_ROLE" "${AUTOMATION_PRIVILEGES[@]}"
    ensure_user "$AUTOMATION_USER" "packertron-vms: Packer builds and OpenTofu deploys"
    ensure_acl / "$AUTOMATION_USER" "$AUTOMATION_ROLE"
    ensure_token "$AUTOMATION_USER" "$AUTOMATION_TOKEN"
    ensure_snippets "$SNIPPET_STORAGE"

    if [[ "$WITH_VDI" == true ]]; then
        ensure_role "$VDI_ROLE" "${VDI_PRIVILEGES[@]}"
        ensure_user "$VDI_USER" "cv4pve-vdi client"
        ensure_acl /vms "$VDI_USER" "$VDI_ROLE"
        # Interactive, and stdin here is this script when piped over SSH.
        log "set or change its password with: pveum passwd ${VDI_USER}"
    fi

    log "done"
}

# Piped to `bash -s` there is no source file at all, and that must run main
# too; only a test that sources this file skips it.
if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
    main "$@"
fi
