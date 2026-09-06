#!/usr/bin/env bash
#
# Run the template checks that CI runs, locally, before pushing.
#
# Mirrors .github/workflows/template-checks.yml: packer fmt -check and packer
# validate for every template directory, then cloud-init schema for every
# autoinstall seed. Finding a broken template here costs seconds; finding it in
# CI costs a round trip, and finding it in neither is how four templates ended
# up unable to build.
#
# Usage:
#   scripts/check-templates.sh            # everything
#   scripts/check-templates.sh packer     # templates only
#   scripts/check-templates.sh seeds      # cloud-init seeds only
#   scripts/check-templates.sh proxmox    # one hypervisor only

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# Template directories are discovered rather than listed, so a new one is
# covered the day it is added. Keep this skip list in step with the matrix in
# .github/workflows/template-checks.yml.
readonly -a SKIP_TEMPLATES=(
    # Unrepaired build block, and depends on a KeePass database that is not in
    # this repository.
    proxmox/win-11
)

failures=0

# Empty means every hypervisor; set from the command line to narrow the run.
HYPERVISOR=""

note() { printf '\n== %s\n' "$*"; }
pass() { printf '   ok   %s\n' "$*"; }
fail() {
    printf '   FAIL %s\n' "$*" >&2
    failures=$((failures + 1))
}

is_skipped() {
    local candidate="$1" skip
    for skip in "${SKIP_TEMPLATES[@]}"; do
        [[ "$candidate" == "$skip" ]] && return 0
    done
    return 1
}

# A template is identified by "<hypervisor>/<os>", which is exactly its path
# under templates/. That is also what the CI matrix lists, so the two stay in
# step without either side hard-coding a list.
template_directories() {
    local path directory
    for path in "$REPO_ROOT"/templates/*/*/*.pkr.hcl; do
        [[ -e "$path" ]] || continue
        directory="$(dirname -- "$path")"
        printf '%s\n' "${directory#"$REPO_ROOT"/templates/}"
    done | sort -u
}

check_templates() {
    local directory

    if ! command -v packer >/dev/null 2>&1; then
        fail "packer is not installed; see https://developer.hashicorp.com/packer/install"
        return
    fi

    while read -r directory; do
        [[ -n "$directory" ]] || continue
        # An explicit hypervisor narrows the run to templates/<hypervisor>/.
        if [[ -n "$HYPERVISOR" && "${directory%%/*}" != "$HYPERVISOR" ]]; then
            continue
        fi
        if is_skipped "$directory"; then
            printf '   skip %s (in SKIP_TEMPLATES)\n' "$directory"
            continue
        fi

        note "$directory"
        pushd "$REPO_ROOT/templates/$directory" >/dev/null || {
            fail "$directory: cannot enter"
            continue
        }

        if packer init . >/dev/null; then
            pass "packer init"
        else
            fail "$directory: packer init"
        fi

        if packer fmt -check -diff .; then
            pass "packer fmt"
        else
            fail "$directory: packer fmt (run: packer fmt .)"
        fi

        # The Proxmox builder refuses to validate without a username and a
        # token. These values are throwaway and never reach a node: validate
        # does not contact the API. Templates without those variables ignore
        # the flags.
        if grep -q 'proxmox-iso' ./*.pkr.hcl 2>/dev/null; then
            if packer validate \
                -var 'proxmox_api_token_id=local@pve!local' \
                -var 'proxmox_api_token_secret=not-a-real-secret' \
                -var 'ssh_password=not-a-real-secret' \
                . >/dev/null; then
                pass "packer validate"
            else
                fail "$directory: packer validate"
            fi
        elif packer validate . >/dev/null; then
            pass "packer validate"
        else
            fail "$directory: packer validate"
        fi

        popd >/dev/null || true
    done < <(template_directories)
}

check_seeds() {
    local file documents

    if ! command -v cloud-init >/dev/null 2>&1; then
        fail "cloud-init is not installed (apt-get install cloud-init)"
        return
    fi

    note "cloud-init seeds"
    for file in "$REPO_ROOT"/scripts/ubuntu/autoinstall-*.yaml "$REPO_ROOT"/templates/*/*/http/user-data; do
        [[ -f "$file" ]] || continue
        local relative="${file#"$REPO_ROOT"/}"

        # cloud-init reads the first document and silently ignores the rest, so
        # a second one is dead text that still looks live.
        documents="$(grep -c '^#cloud-config' "$file" || true)"
        if ((documents > 1)); then
            fail "$relative: $documents #cloud-config documents; only the first is read"
            continue
        fi

        if cloud-init schema --config-file "$file" >/dev/null 2>&1; then
            pass "$relative"
        else
            fail "$relative: schema"
            cloud-init schema --config-file "$file" --annotate 2>&1 | tail -20 >&2 || true
        fi
    done
}

main() {
    local scope="${1:-all}"

    # A hypervisor name is accepted wherever a scope is, because "check just
    # the Proxmox templates" is the common case while a build is being brought
    # up on a node. It is validated against the directories that exist rather
    # than a hard-coded list.
    if [[ -n "$scope" && -d "$REPO_ROOT/templates/$scope" ]]; then
        HYPERVISOR="$scope"
        scope="${2:-all}"
    fi

    case "$scope" in
        all)
            check_templates
            check_seeds
            ;;
        packer) check_templates ;;
        seeds) check_seeds ;;
        *)
            printf 'usage: %s [<hypervisor>] [all|packer|seeds]\n' "${BASH_SOURCE[0]##*/}" >&2
            printf 'hypervisors: %s\n' "$(cd "$REPO_ROOT/templates" && echo */)" >&2
            exit 2
            ;;
    esac

    printf '\n'
    if ((failures > 0)); then
        printf '%d check(s) failed\n' "$failures" >&2
        exit 1
    fi
    printf 'all checks passed\n'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
