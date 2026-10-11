#!/usr/bin/env bash
#
# Compare every pinned upstream version Dependabot cannot see with the latest
# upstream release, and report what is behind: the Ubuntu and Kali ISOs, the
# virtio-win ISO, cloudbase-init, the Packer plugins, the OpenTofu provider and
# the linters CI installs. Read-only: it changes nothing, it only reports.
#
# Docs:
#   GitHub REST  https://docs.github.com/en/rest/releases/releases
#   README.md    scripts/README.md, the weekly workflow that runs this
#
# Run:
#   scripts/check-pins.sh               # a table; exit 1 when something is behind
#   scripts/check-pins.sh --markdown    # a Markdown list, the body of the issue
#
# Exit status: 0 all current, 1 something behind, 2 a lookup failed. Set
# GH_TOKEN to lift GitHub's anonymous rate limit.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${PACKERTRON_REPO_ROOT:-$(cd -- "$SCRIPT_DIR/.." && pwd)}"

MARKDOWN=false
behind=0
lookup_failures=0
declare -a rows=()

die() {
    printf 'error: %s\n' "$*" >&2
    exit 2
}

fetch() {
    curl --fail --silent --show-error --location --max-time 60 "$@"
}

github_latest_tag() {
    local -a auth=()

    [[ -z "${GH_TOKEN:-}" ]] || auth=(--header "Authorization: Bearer ${GH_TOKEN}")
    fetch "${auth[@]}" --header "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$1/releases/latest" | jq -r '.tag_name // empty'
}

# True when version $1 sorts after version $2.
version_gt() {
    [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" == "$1" ]]
}

# record <what> <pinned> <latest> <where>; an empty latest is a failed lookup.
record() {
    local what="$1" pinned="$2" latest="$3" where="$4" state

    if [[ -z "$latest" ]]; then
        state="unknown"
        lookup_failures=$((lookup_failures + 1))
    elif version_gt "$latest" "$pinned"; then
        state="behind"
        behind=$((behind + 1))
    else
        state="current"
    fi
    rows+=("${state}|${what}|${pinned}|${latest:-?}|${where}")
}

hcl_default() {
    awk -v name="$2" '
        $0 ~ "^variable \"" name "\" \\{" { inside = 1; next }
        inside && /^}/ { exit }
        inside && /^[[:space:]]*default[[:space:]]*=/ {
            if (match($0, /"[^"]*"/)) { print substr($0, RSTART + 1, RLENGTH - 2) }
            exit
        }
    ' "$1"
}

check_ubuntu_isos() {
    local file variable url name series flavor pinned latest sums
    local -A seen=()

    for file in "$REPO_ROOT"/templates/*/*/*.pkr.hcl; do
        for variable in iso iso_url iso_fallback_url; do
            url="$(hcl_default "$file" "$variable")"
            [[ "$url" =~ ^https://releases\.ubuntu\.com/.*/ubuntu-([0-9]+\.[0-9]+)(\.[0-9.]+)?-(live-server|desktop)-amd64\.iso$ ]] ||
                continue
            name="${url##*/}"
            [[ -z "${seen[$name]:-}" ]] || continue
            seen[$name]=1
            series="${BASH_REMATCH[1]}"
            flavor="${BASH_REMATCH[3]}"
            pinned="${name#ubuntu-}"
            pinned="${pinned%-"${flavor}"-amd64.iso}"

            # The series directory lists every point release still served.
            sums="$(fetch "https://releases.ubuntu.com/${series}/SHA256SUMS" || true)"
            latest="$(sed -n -E "s/^[0-9a-f]{64} \*?ubuntu-([0-9.]+)-${flavor}-amd64\.iso$/\1/p" <<<"$sums" | sort -V | tail -n 1)"
            record "Ubuntu ${series} ${flavor} ISO" "$pinned" "$latest" "templates/*/ubuntu-${series}-*"
        done
    done
}

check_kali_iso() {
    local file="$REPO_ROOT/templates/proxmox/kali/kali.pkr.hcl" url pinned latest

    [[ -f "$file" ]] || return 0
    url="$(hcl_default "$file" iso)"
    pinned="$(sed -n -E 's/.*kali-linux-([0-9]+\.[0-9]+[a-z]?)-installer-amd64\.iso$/\1/p' <<<"$url")"
    latest="$(fetch https://cdimage.kali.org/current/SHA256SUMS 2>/dev/null |
        sed -n -E 's/.*kali-linux-([0-9]+\.[0-9]+[a-z]?)-installer-amd64\.iso$/\1/p' | head -n 1 || true)"
    record "Kali installer ISO" "$pinned" "$latest" "templates/proxmox/kali"
}

check_virtio() {
    local file pinned="" latest location

    for file in "$REPO_ROOT"/templates/proxmox/win-*/*.pkr.hcl; do
        [[ -f "$file" ]] || continue
        pinned="$(hcl_default "$file" virtio_iso | sed -n -E 's/.*virtio-win-([0-9.]+)\.iso$/\1/p')"
        [[ -n "$pinned" ]] && break
    done
    [[ -n "$pinned" ]] || return 0

    # latest-virtio redirects into the archive directory of the newest build.
    location="$(curl --silent --head --max-time 60 \
        https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso |
        tr -d '\r' | sed -n -E 's/^[Ll]ocation: .*virtio-win-([0-9.]+)-[0-9]+\/.*/\1/p' | head -n 1 || true)"
    latest="$location"
    record "virtio-win ISO" "$pinned" "$latest" "templates/proxmox/win-*"
}

check_cloudbase_init() {
    local file="$REPO_ROOT/scripts/windows/11_cloudbase_init.ps1" pinned latest

    [[ -f "$file" ]] || return 0
    pinned="$(sed -n -E "s/^\\\$Version = '([0-9.]+)'.*/\1/p" "$file" | head -n 1)"
    latest="$(github_latest_tag cloudbase/cloudbase-init || true)"
    record "cloudbase-init" "$pinned" "${latest#v}" "scripts/windows/11_cloudbase_init.ps1"
}

check_windows_update_plugin() {
    local file pinned="" latest

    for file in "$REPO_ROOT"/templates/proxmox/win-*/*.pkr.hcl; do
        pinned="$(awk '/windows-update = \{/ { inside = 1 } inside && /version/ { gsub(/[^0-9.]/, ""); print; exit }' "$file")"
        [[ -n "$pinned" ]] && break
    done
    [[ -n "$pinned" ]] || return 0
    latest="$(github_latest_tag rgl/packer-plugin-windows-update || true)"
    record "rgl/windows-update plugin" "$pinned" "${latest#v}" "templates/proxmox/win-*"
}

# A bounded plugin is behind only when upstream has released past the bound:
# the templates already take every release inside it.
check_plugin_bound() {
    local repository="$1" below="$2" what="$3" latest

    latest="$(github_latest_tag "$repository" || true)"
    latest="${latest#v}"
    if [[ -z "$latest" ]]; then
        record "$what" "< ${below}" "" "templates/*/*.pkr.hcl"
    elif version_gt "$below" "$latest"; then
        rows+=("current|${what}|< ${below}|${latest}|templates/*/*.pkr.hcl")
    else
        rows+=("behind|${what}|< ${below}|${latest}|templates/*/*.pkr.hcl")
        behind=$((behind + 1))
    fi
}

check_opentofu_provider() {
    local file="$REPO_ROOT/deploy/versions.tf" pinned latest

    [[ -f "$file" ]] || return 0
    pinned="$(sed -n -E 's/^ *version *= *"~> *([0-9.]+)".*/\1/p' "$file" | head -n 1)"
    latest="$(github_latest_tag bpg/terraform-provider-proxmox || true)"
    record "bpg/proxmox OpenTofu provider" "$pinned" "${latest#v}" "deploy/versions.tf"
}

check_ci_linters() {
    local workflow="$REPO_ROOT/.github/workflows/template-checks.yml" pinned latest

    [[ -f "$workflow" ]] || return 0
    pinned="$(sed -n -E 's/^ *ACTIONLINT_VERSION: *"([0-9.]+)".*/\1/p' "$workflow")"
    latest="$(github_latest_tag rhysd/actionlint || true)"
    [[ -z "$pinned" ]] || record "actionlint (CI)" "$pinned" "${latest#v}" ".github/workflows/template-checks.yml"

    pinned="$(sed -n -E 's/^ *ZIZMOR_VERSION: *"([0-9.]+)".*/\1/p' "$workflow")"
    latest="$(github_latest_tag zizmorcore/zizmor || true)"
    [[ -z "$pinned" ]] || record "zizmor (CI)" "$pinned" "${latest#v}" ".github/workflows/template-checks.yml"
}

print_report() {
    local row state what pinned latest where

    if [[ "$MARKDOWN" == true ]]; then
        printf '| State | Pin | Pinned | Latest | Where |\n| --- | --- | --- | --- | --- |\n'
        for row in "${rows[@]}"; do
            IFS='|' read -r state what pinned latest where <<<"$row"
            # shellcheck disable=SC2016 # the backticks are Markdown code spans
            printf '| %s | %s | `%s` | `%s` | `%s` |\n' "$state" "$what" "$pinned" "$latest" "$where"
        done
        return
    fi
    for row in "${rows[@]}"; do
        IFS='|' read -r state what pinned latest where <<<"$row"
        printf '%-8s %-44s %-12s %-12s %s\n' "$state" "$what" "$pinned" "$latest" "$where"
    done
}

main() {
    case "${1:-}" in
        "") ;;
        --markdown) MARKDOWN=true ;;
        *) die "usage: check-pins.sh [--markdown]" ;;
    esac
    command -v curl >/dev/null 2>&1 || die "curl is required"
    command -v jq >/dev/null 2>&1 || die "jq is required"

    check_ubuntu_isos
    check_kali_iso
    check_virtio
    check_cloudbase_init
    check_windows_update_plugin
    check_plugin_bound hashicorp/packer-plugin-proxmox 2.0.0 "hashicorp/proxmox plugin"
    check_plugin_bound hashicorp/packer-plugin-vmware 3.0.0 "hashicorp/vmware plugin"
    check_plugin_bound hashicorp/packer-plugin-vagrant 2.0.0 "hashicorp/vagrant plugin"
    check_opentofu_provider
    check_ci_linters

    print_report
    ((lookup_failures == 0)) || exit 2
    ((behind == 0)) || exit 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
