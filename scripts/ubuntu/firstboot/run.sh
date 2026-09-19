#!/usr/bin/env bash
#
# Choose the repository revision a first boot provisions from, retry it a
# bounded number of times, and hand off to 90-bootstrap-baremetal.sh.
#
# The pin keeps one run coherent across retries and reboots. The attempt
# ceiling is what stops a bad revision retrying forever: without it a commit
# that cannot succeed is retried every RestartSec and a fix pushed to the
# branch is never picked up.
#
# This was duplicated verbatim inside every autoinstall seed, where no linter
# and no test could reach it. It is a file so that both can.
#
# Docs:
#   cloud-init  https://cloudinit.readthedocs.io/en/latest/
#   README.md   ../README.md, the first-boot runner and its settings
#
# Run:
#   stub.sh installs this to /run and execs it; not meant to be run by hand.
#   Lint it with: ../../check-templates.sh shell

set -Eeuo pipefail

REPO_BRANCH="${PACKERTRON_REPO_BRANCH:-main}"
REPO_DIR="${PACKERTRON_REPO_DIR:-/opt/packertron-vms}"
STATE_DIR="${PACKERTRON_STATE_DIR:-/var/lib/packertron-bootstrap}"
INSTALL_USER="${PACKERTRON_TARGET_USER:-}"
STEPS="${PACKERTRON_STEPS:-}"

# After this many failed attempts on one pinned revision, adopt the current
# branch head instead.
MAX_PINNED_ATTEMPTS="${PACKERTRON_MAX_PINNED_ATTEMPTS:-3}"

REVISION_FILE="$STATE_DIR/revision"
ATTEMPTS_FILE="$STATE_DIR/attempts"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

# Record the revision the next run should start from, and echo it back.
pin_revision() {
    printf '%s\n' "$1" >"$REVISION_FILE.tmp"
    chmod 0600 "$REVISION_FILE.tmp"
    mv -f "$REVISION_FILE.tmp" "$REVISION_FILE"
    printf '%s\n' "$1"
}

branch_head() {
    git -C "$REPO_DIR" rev-parse --verify "origin/${REPO_BRANCH}^{commit}"
}

bootstrap_already_complete() {
    [[ -s "$STATE_DIR/complete" && -s "$REVISION_FILE" ]] &&
        [[ "$(<"$STATE_DIR/complete")" == "$(<"$REVISION_FILE")" ]]
}

# The recorded pin is read back from disk, so it is checked before it reaches
# git: a malformed value would otherwise be passed straight to a revision
# argument.
resolve_revision() {
    local revision

    if [[ -s "$REVISION_FILE" ]]; then
        revision="$(<"$REVISION_FILE")"
        [[ "$revision" =~ ^[0-9a-fA-F]{40,64}$ ]] ||
            die "invalid recorded bootstrap revision: $revision"
    else
        revision="$(pin_revision "$(branch_head)")"
    fi

    # A pinned commit that has disappeared - force-push, garbage collection -
    # would fail on every retry. Fall back to the branch head and re-pin.
    if ! git -C "$REPO_DIR" cat-file -e "${revision}^{commit}" 2>/dev/null; then
        printf 'Pinned revision %s is unavailable; re-pinning to origin/%s\n' \
            "$revision" "$REPO_BRANCH" >&2
        revision="$(pin_revision "$(branch_head)")"
    fi

    printf '%s\n' "$revision"
}

recorded_attempts() {
    local revision="$1" recorded_revision recorded_attempts

    [[ -s "$ATTEMPTS_FILE" ]] || {
        printf '0\n'
        return
    }
    read -r recorded_revision recorded_attempts <"$ATTEMPTS_FILE" || true
    if [[ "$recorded_revision" == "$revision" && "$recorded_attempts" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$recorded_attempts"
    else
        printf '0\n'
    fi
}

record_attempt() {
    local revision="$1" attempts="$2"

    printf '%s %s\n' "$revision" "$attempts" >"$ATTEMPTS_FILE.tmp"
    chmod 0600 "$ATTEMPTS_FILE.tmp"
    mv -f "$ATTEMPTS_FILE.tmp" "$ATTEMPTS_FILE"
}

# Returns the revision to run, which is the branch head when the pinned one has
# exhausted its attempts and the branch has since moved on.
revision_after_attempt_ceiling() {
    local revision="$1" attempts="$2" head

    ((attempts >= MAX_PINNED_ATTEMPTS)) || {
        printf '%s\n' "$revision"
        return
    }

    head="$(branch_head)"
    if [[ "$head" != "$revision" ]]; then
        printf 'Pinned revision %s failed %s times; adopting origin/%s (%s)\n' \
            "$revision" "$attempts" "$REPO_BRANCH" "$head" >&2
        pin_revision "$head" >/dev/null
        printf '%s\n' "$head"
        return
    fi

    printf 'WARNING: pinned revision %s has failed %s times and origin/%s still points at it; push a fix to recover\n' \
        "$revision" "$attempts" "$REPO_BRANCH" >&2
    printf '%s\n' "$revision"
}

main() {
    local revision attempts

    install -d -m 0700 "$STATE_DIR"

    if bootstrap_already_complete; then
        printf 'Packertron bootstrap already completed for %s\n' "$(<"$REVISION_FILE")"
        return 0
    fi

    revision="$(resolve_revision)"
    attempts="$(recorded_attempts "$revision")"
    revision="$(revision_after_attempt_ceiling "$revision" "$attempts")"
    [[ "$(recorded_attempts "$revision")" == "$attempts" ]] || attempts=0

    record_attempt "$revision" "$((attempts + 1))"
    printf 'Bootstrap attempt %s for revision %s\n' "$((attempts + 1))" "$revision"

    git -C "$REPO_DIR" checkout --detach "$revision"
    git -C "$REPO_DIR" reset --hard "$revision"

    # TARGET_USER is resolved by the caller and passed down: under systemd
    # there is no SUDO_USER, and discovery fails once a second account exists.
    local -a step_environment=("PACKERTRON_BOOTSTRAP_REVISION=$revision")
    [[ -z "$INSTALL_USER" ]] || step_environment+=("TARGET_USER=$INSTALL_USER")
    [[ -z "$STEPS" ]] || step_environment+=("PACKERTRON_STEPS=$STEPS")

    exec env "${step_environment[@]}" \
        "$REPO_DIR/scripts/ubuntu/90-bootstrap-baremetal.sh"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
