#!/usr/bin/env bash
#
# Stage the installer ISOs the Proxmox templates expect on the node, and check
# each against the checksum its template pins. Packer itself never checks a
# staged ISO, so this is where that check happens.
#
# Reads every template's own iso_file, iso and checksum defaults (and the
# virtio_ ones), so there is no second list to keep in step. A file already on
# the node is verified and left alone; a missing one is downloaded on the node,
# verified, and only then moved into place.
#
# Docs:
#   pvesm      https://pve.proxmox.com/pve-docs/pvesm.1.html
#   README.md  ../../templates/proxmox/README.md, staging and the build
#
# Run:
#   scripts/proxmox/stage-isos.sh --node root@pve02                # every template
#   scripts/proxmox/stage-isos.sh --node root@pve02 win-11 kali    # some of them
#   scripts/proxmox/stage-isos.sh --node root@pve02 --dry-run      # what it would do
#   scripts/proxmox/stage-isos.sh                                  # on the node itself

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${PACKERTRON_TEMPLATES_DIR:-$SCRIPT_DIR/../../templates/proxmox}"

NODE=""
DRY_RUN=false
# Tests only: stage into this directory instead of asking pvesm for the path.
ISO_DIR="${PACKERTRON_ISO_DIR:-}"

log() { printf '[stage] %s\n' "$*"; }
error() { printf '[stage] error: %s\n' "$*" >&2; }
die() {
    error "$*"
    exit 1
}

usage() {
    printf 'usage: %s [--node <user@host>] [--dry-run] [template ...]\n' "${BASH_SOURCE[0]##*/}" >&2
    printf 'templates: %s\n' "$(template_names | tr '\n' ' ')" >&2
    exit 2
}

template_names() {
    local path
    for path in "$TEMPLATES_DIR"/*/*.pkr.hcl; do
        [[ -e "$path" ]] || continue
        basename -- "$(dirname -- "$path")"
    done | sort -u
}

# The single-line string default of one variable block. Every template
# declares its ISO variables that way; anything else is not staged.
hcl_default() {
    local file="$1" variable="$2"

    awk -v name="$variable" '
        $0 ~ "^variable \"" name "\" \\{" { inside = 1; next }
        inside && /^}/ { exit }
        inside && /^[[:space:]]*default[[:space:]]*=/ {
            if (match($0, /"[^"]*"/)) { print substr($0, RSTART + 1, RLENGTH - 2) }
            exit
        }
    ' "$file"
}

# Prints the sha256 a checksum setting promises for the file at url:
# "sha256:<hex>" as written, "file:<SHA256SUMS URL>" by the line naming it.
expected_sha256() {
    local checksum="$1" url="$2" name sums hash

    case "$checksum" in
        sha256:*)
            hash="${checksum#sha256:}"
            ;;
        file:*)
            name="${url##*/}"
            sums="$(curl --fail --silent --show-error --location "${checksum#file:}")" ||
                die "cannot fetch ${checksum#file:}"
            hash="$(awk -v name="$name" '{ file = $2; sub(/^\*/, "", file) } file == name { print $1; exit }' <<<"$sums")"
            [[ -n "$hash" ]] || die "${checksum#file:} lists no ${name}"
            ;;
        *)
            die "unsupported checksum ${checksum}; expected sha256:<hex> or file:<url>"
            ;;
    esac

    [[ "${hash,,}" =~ ^[0-9a-f]{64}$ ]] || die "not a sha256: ${hash}"
    printf '%s\n' "${hash,,}"
}

# Runs where the ISO lives - on the node over SSH, or here - so it carries no
# dependency beyond curl, sha256sum and, on a node, pvesm. Exit 3 means a file
# is already there and fails its check; it is never overwritten.
stage_one() {
    local volid="$1" url="$2" expected="$3" iso_dir="${4:-}" path actual

    if [[ -n "$iso_dir" ]]; then
        path="${iso_dir}/${volid##*/}"
    else
        path="$(pvesm path "$volid")" || {
            printf '[stage] error: pvesm cannot resolve %s\n' "$volid" >&2
            return 1
        }
    fi

    if [[ -e "$path" ]]; then
        actual="$(sha256sum "$path" | cut -d ' ' -f 1)"
        if [[ "$actual" == "$expected" ]]; then
            printf '[stage] ok      %s (already staged, checksum matches)\n' "$volid"
            return 0
        fi
        printf '[stage] error: %s is on the node but its sha256 is %s, not %s; move it away and rerun\n' \
            "$path" "$actual" "$expected" >&2
        return 3
    fi

    printf '[stage] fetch   %s\n' "$url"
    install -d -m 0755 "$(dirname -- "$path")"
    # Downloaded under a temporary name, so an interrupted run never leaves a
    # file Packer would take for a finished ISO.
    if ! curl --fail --location --progress-bar --retry 3 --output "${path}.partial" "$url"; then
        rm -f -- "${path}.partial"
        printf '[stage] error: download failed: %s\n' "$url" >&2
        return 1
    fi

    actual="$(sha256sum "${path}.partial" | cut -d ' ' -f 1)"
    if [[ "$actual" != "$expected" ]]; then
        rm -f -- "${path}.partial"
        printf '[stage] error: %s downloaded with sha256 %s, not %s; nothing staged\n' \
            "$url" "$actual" "$expected" >&2
        return 1
    fi

    mv -f -- "${path}.partial" "$path"
    printf '[stage] staged  %s (checksum matches)\n' "$volid"
}

run_stage_one() {
    if [[ -n "$NODE" ]]; then
        # Shipping the function keeps the node free of any copy of this repo.
        # shellcheck disable=SC2029 # the arguments are meant to expand here
        {
            declare -f stage_one
            printf 'stage_one "$@"\n'
        } |
            ssh -- "$NODE" bash -s -- "$(printf '%q ' "$@")"
    else
        stage_one "$@"
    fi
}

# Called from an || list, where set -e does not apply, so every step checks
# its own status: an unchecked failure here would download an ISO against an
# empty checksum.
stage_template() {
    local template="$1" file prefix volid url checksum expected

    file="$(find "$TEMPLATES_DIR/$template" -maxdepth 1 -name '*.pkr.hcl' -print -quit 2>/dev/null)"
    [[ -n "$file" ]] || {
        error "no template named ${template} under ${TEMPLATES_DIR}"
        return 1
    }

    for prefix in "" virtio_; do
        volid="$(hcl_default "$file" "${prefix}iso_file")" || return 1
        # Empty means the template downloads that ISO itself.
        [[ -n "$volid" ]] || continue
        [[ "$volid" =~ ^[A-Za-z0-9._-]+:iso/[^/]+\.iso$ ]] || {
            error "${template}: ${prefix}iso_file is not storage:iso/<name>.iso: ${volid}"
            return 1
        }

        url="$(hcl_default "$file" "${prefix}iso")" || return 1
        checksum="$(hcl_default "$file" "${prefix}checksum")" || return 1
        [[ "$url" == https://* ]] || {
            error "${template}: ${prefix}iso is not an https URL: ${url}"
            return 1
        }
        [[ -n "$checksum" ]] || {
            error "${template}: no ${prefix}checksum default"
            return 1
        }

        expected="$(expected_sha256 "$checksum" "$url")" || return 1

        if [[ "$DRY_RUN" == true ]]; then
            log "would stage ${volid} from ${url} (sha256 ${expected})"
            continue
        fi

        run_stage_one "$volid" "$url" "$expected" "$ISO_DIR" || return 1
    done
}

main() {
    local -a templates=()
    local template failures=0

    while (($# > 0)); do
        case "$1" in
            --node)
                [[ -n "${2:-}" ]] || usage
                NODE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h | --help) usage ;;
            -*) usage ;;
            *)
                templates+=("${1#proxmox/}")
                shift
                ;;
        esac
    done

    command -v curl >/dev/null 2>&1 || die "curl is required"
    ((${#templates[@]} > 0)) || mapfile -t templates < <(template_names)
    ((${#templates[@]} > 0)) || die "no templates found under ${TEMPLATES_DIR}"

    for template in "${templates[@]}"; do
        log "== ${template}"
        stage_template "$template" || failures=$((failures + 1))
    done

    ((failures == 0)) || die "${failures} template(s) not staged"
    log "done"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
