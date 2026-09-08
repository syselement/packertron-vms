#!/usr/bin/env bash
#
# Run the checks that .github/workflows/template-checks.yml runs, locally,
# before pushing.
#
# Docs:
#   Packer CLI   https://developer.hashicorp.com/packer/docs/commands
#   cloud-init   https://cloudinit.readthedocs.io/en/latest/reference/cli.html
#   README.md    repository layout and where a template belongs
#
# Run:
#   scripts/check-templates.sh            # everything
#   scripts/check-templates.sh packer     # templates only
#   scripts/check-templates.sh seeds      # cloud-init seeds only
#   scripts/check-templates.sh matrix     # CI matrix vs the templates on disk
#   scripts/check-templates.sh shell      # shellcheck/shfmt outside scripts/ubuntu/
#   scripts/check-templates.sh proxmox    # one hypervisor only

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

readonly WORKFLOW="\
.github/workflows/template-checks.yml"

# - Discovered rather than listed, so a new template is covered the day it is added.
# - The CI matrix cannot discover them - GitHub evaluates it before any
#   checkout - so check_matrix below keeps that one hand-written list honest.
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

# A template is named "<hypervisor>/<os>", its path under templates/ and also
# what the CI matrix lists.
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

        # The Proxmox builder will not validate without a username and token.
        # Throwaway values: validate never contacts the API.
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

# Both drift directions are quiet failures: a template missing from the matrix
# is never checked by CI, and a matrix entry for a directory that no longer
# exists fails every run with a path error instead of a useful message.
matrix_templates() {
    awk '
        /^ *template: *$/ { inlist = 1; next }
        inlist && /^ *- / { sub(/^ *- +/, ""); sub(/ *(#.*)?$/, ""); print; next }
        inlist && !/^ *#/ { inlist = 0 }
    ' "$REPO_ROOT/$WORKFLOW"
}

check_matrix() {
    local expected actual

    note "CI matrix vs templates on disk"

    if [[ ! -f "$REPO_ROOT/$WORKFLOW" ]]; then
        fail "$WORKFLOW: not found"
        return
    fi

    expected="$(
        while read -r directory; do
            [[ -n "$directory" ]] || continue
            is_skipped "$directory" || printf '%s\n' "$directory"
        done < <(template_directories) | sort
    )"
    actual="$(matrix_templates | sort)"

    if [[ "$expected" == "$actual" ]]; then
        pass "$(printf '%s' "$actual" | grep -c .) template(s) listed, and no others exist"
        return
    fi

    # Process substitution, not a pipe: a piped loop runs in a subshell, so
    # fail() would increment a copy of $failures and the script would exit 0
    # while reporting failures.
    while read -r missing; do
        [[ -n "$missing" ]] || continue
        fail "$missing exists on disk but is not in the $WORKFLOW matrix, so CI never checks it"
    done < <(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"))

    while read -r extra; do
        [[ -n "$extra" ]] || continue
        fail "the $WORKFLOW matrix lists $extra, which is not a template directory (or is in SKIP_TEMPLATES)"
    done < <(comm -13 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"))
}

# Everything outside scripts/ubuntu/, which ubuntu-static-checks.yml covers.
# Discovered, so a new script is linted the day it is added.
repository_shell_scripts() {
    local path
    for path in "$REPO_ROOT"/scripts/*.sh "$REPO_ROOT"/templates/*/*.sh "$REPO_ROOT"/templates/*/*/*.sh; do
        [[ -f "$path" ]] || continue
        printf '%s\n' "${path#"$REPO_ROOT"/}"
    done | sort -u
}

check_shell() {
    local relative tool missing=0

    note "shell scripts outside scripts/ubuntu/"

    for tool in bash shellcheck shfmt; do
        command -v "$tool" >/dev/null 2>&1 || {
            fail "$tool is not installed"
            missing=1
        }
    done
    ((missing == 0)) || return

    while read -r relative; do
        [[ -n "$relative" ]] || continue
        if bash -n "$REPO_ROOT/$relative" &&
            shellcheck -x "$REPO_ROOT/$relative" &&
            shfmt -d -i 4 -ci "$REPO_ROOT/$relative"; then
            pass "$relative"
        else
            fail "$relative: syntax, shellcheck or shfmt"
        fi
    done < <(repository_shell_scripts)
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

    # A hypervisor name is accepted wherever a scope is, validated against the
    # directories that exist rather than a hard-coded list.
    if [[ -n "$scope" && -d "$REPO_ROOT/templates/$scope" ]]; then
        HYPERVISOR="$scope"
        scope="${2:-all}"
    fi

    case "$scope" in
        all)
            check_templates
            check_seeds
            check_shell
            check_matrix
            ;;
        packer) check_templates ;;
        seeds) check_seeds ;;
        matrix) check_matrix ;;
        shell) check_shell ;;
        *)
            printf 'usage: %s [<hypervisor>] [all|packer|seeds|shell|matrix]\n' "${BASH_SOURCE[0]##*/}" >&2
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
