#!/usr/bin/env bash
#
# First-boot orchestration for Ubuntu workstations and for clones that ask for
# provisioning. Runs the steps PACKERTRON_STEPS names, 02 and 03 by default,
# and deliberately never runs 01 - that would seal a machine someone uses.
#
# Docs:
#   README.md  the bare-metal path, PACKERTRON_STEPS, and the logs
#
# Run:
#   sudo env TARGET_USER="$USER" ./90-bootstrap-baremetal.sh
#   sudo env TARGET_USER="$USER" PACKERTRON_STEPS=02 ./90-bootstrap-baremetal.sh
#   git clone https://github.com/syselement/packertron-vms.git && cd packertron-vms/scripts/ubuntu && sudo env TARGET_USER="$USER" ./90-bootstrap-baremetal.sh
#

set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
)"

STATE_DIR="${PACKERTRON_STATE_DIR:-/var/lib/packertron-bootstrap}"
LOG_FILE="${PACKERTRON_LOG_FILE:-/var/log/packertron-bootstrap.log}"
LOCK_FILE="${PACKERTRON_LOCK_FILE:-/run/lock/packertron-bootstrap.lock}"
BOOTSTRAP_REVISION=""

# Which steps a run is allowed to perform, as a comma-separated list of the
# numeric prefixes below. A clone that wants a clean machine sets it empty;
# the default is what a workstation has always done.
STEPS="${PACKERTRON_STEPS-02,03}"

# 00 and 01 are deliberately absent, not merely unlisted: 00 is VM-template
# update and guest-agent work, and 01 seals an image, which would strip the
# machine someone is about to use.
# -g because this file is sourced: a bare `declare -A` inside a function - which
# is where a sourcing caller runs it - would make the array local to that
# function and invisible to selected_steps.
declare -gA AVAILABLE_STEPS=(
    [02]="02-provision-system.sh"
    [03]="03-customize-system.sh"
)

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

# Create a directory only when it is missing, leaving the mode and ownership of
# an existing one untouched.
ensure_directory() {
    local directory="$1"

    [[ -d "$directory" ]] || install -d -m 0755 "$directory"
}

resolve_bootstrap_revision() {
    local revision="${PACKERTRON_BOOTSTRAP_REVISION:-}"

    if [[ -z "$revision" ]]; then
        revision="$(git -C "$SCRIPT_DIR/../.." rev-parse --verify HEAD 2>/dev/null)" ||
            die "cannot determine bootstrap revision; set PACKERTRON_BOOTSTRAP_REVISION"
    fi

    [[ "$revision" =~ ^[0-9a-fA-F]{40,64}$ ]] ||
        die "invalid bootstrap revision: ${revision}"

    printf '%s\n' "${revision,,}"
}

marker_matches_revision() {
    local marker="$1"

    [[ -f "$marker" ]] && [[ "$(<"$marker")" == "$BOOTSTRAP_REVISION" ]]
}

write_revision_marker() {
    local marker="$1"
    local temporary_marker="${marker}.tmp"

    printf '%s\n' "$BOOTSTRAP_REVISION" >"$temporary_marker"
    chmod 0600 "$temporary_marker"
    mv -f -- "$temporary_marker" "$marker"
}

run_step() {
    local name="$1"
    local script="$2"
    local marker="$STATE_DIR/${name}.done"

    if marker_matches_revision "$marker"; then
        printf 'SKIP: %s already completed for %s\n' "$name" "$BOOTSTRAP_REVISION"
        return
    fi

    [[ -f "$SCRIPT_DIR/$script" ]] || die "missing bootstrap script: ${SCRIPT_DIR}/${script}"

    printf 'RUN: %s (%s)\n' "$name" "$BOOTSTRAP_REVISION"

    # TARGET_USER is passed through explicitly when set. Under systemd there is
    # no SUDO_USER, so without it the step falls back to discovering a single
    # eligible account, which fails permanently once a second one exists.
    local -a step_environment=(REBOOT_AT_END=false)
    [[ -z "${TARGET_USER:-}" ]] || step_environment+=("TARGET_USER=${TARGET_USER}")

    env "${step_environment[@]}" bash "$SCRIPT_DIR/$script"

    write_revision_marker "$marker"
    printf 'DONE: %s (%s)\n' "$name" "$BOOTSTRAP_REVISION"
}

# An unknown step is fatal rather than skipped: it almost always means a typo
# in a deployment's firstboot.conf, and silently provisioning less than was
# asked for is the failure that gets noticed last.
selected_steps() {
    local step
    local -a requested=()

    IFS=',' read -ra requested <<<"$STEPS"
    for step in "${requested[@]}"; do
        step="${step//[[:space:]]/}"
        [[ -n "$step" ]] || continue
        [[ -n "${AVAILABLE_STEPS[$step]:-}" ]] ||
            die "unknown provisioning step '${step}'; available: $(
                printf '%s\n' "${!AVAILABLE_STEPS[@]}" | sort | tr '\n' ' '
            )"
        printf '%s\n' "$step"
    done
}

schedule_reboot() {
    sync

    # Warn anyone already logged in: provisioning can take long enough for a
    # desktop session to be in use by the time this fires.
    wall 'Packertron bootstrap finished; this system reboots in 2 minutes.' 2>/dev/null || true

    systemd-run \
        --unit=packertron-bootstrap-reboot \
        --on-active=2m \
        /usr/bin/systemctl reboot ||
        die "failed scheduling the required reboot; bootstrap remains incomplete"
}

finalize_bootstrap() {
    # schedule_reboot dies on failure today, so this guard is belt-and-braces:
    # completion must never be recorded unless the reboot timer was accepted.
    schedule_reboot || return 1
    write_revision_marker "$STATE_DIR/complete"
}

main() {
    [[ "$EUID" -eq 0 ]] || die "run as root"

    BOOTSTRAP_REVISION="$(resolve_bootstrap_revision)"

    install -d -m 0700 "$STATE_DIR"
    # Only create these when they are missing. "install -d -m" also applies the
    # mode to directories that already exist, and the defaults here are
    # /var/log and /run/lock: forcing 0755 on those strips group-write from
    # /var/log (rsyslog can then no longer create files) and clears the sticky
    # bit on /run/lock.
    ensure_directory "$(dirname -- "$LOG_FILE")"
    ensure_directory "$(dirname -- "$LOCK_FILE")"
    touch "$LOG_FILE"
    chmod 0600 "$LOG_FILE"

    exec > >(tee -a "$LOG_FILE") 2>&1

    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        # Must not return success: systemd removes the first-boot service once
        # ExecStart succeeds, which would tear down the retry mechanism without
        # any provisioning having happened.
        die "another bootstrap execution is already running"
    fi

    if marker_matches_revision "$STATE_DIR/complete"; then
        printf 'Bare-metal bootstrap already completed for %s\n' "$BOOTSTRAP_REVISION"
        return
    fi

    local -a steps=()
    local step selected

    # Command substitution, not a process substitution: die() inside the latter
    # exits only that subshell, so an unrecognised step would be reported and
    # then quietly treated as "nothing to run".
    selected="$(selected_steps)" || exit 1
    [[ -z "$selected" ]] || mapfile -t steps <<<"$selected"

    # Still record completion: the caller's service retries on failure, and a
    # run that was asked to do nothing has succeeded. Rebooting would be the
    # only visible effect, so it is skipped.
    if ((${#steps[@]} == 0)); then
        printf 'No provisioning steps selected; nothing to run\n'
        write_revision_marker "$STATE_DIR/complete"
        printf 'Bare-metal bootstrap completed successfully for %s\n' "$BOOTSTRAP_REVISION"
        return
    fi

    for step in "${steps[@]}"; do
        run_step "${AVAILABLE_STEPS[$step]%.sh}" "${AVAILABLE_STEPS[$step]}"
    done

    # The persistent first-boot service is ordered after cloud-final. Record
    # completion only after systemd accepts the required reboot timer.
    finalize_bootstrap

    printf 'Bare-metal bootstrap completed successfully for %s\n' "$BOOTSTRAP_REVISION"
    printf 'Log: %s\n' "$LOG_FILE"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
