#!/usr/bin/env bash
#
# First-boot orchestration for physical Ubuntu workstations.
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

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
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

    REBOOT_AT_END=false \
        bash "$SCRIPT_DIR/$script"

    write_revision_marker "$marker"
    printf 'DONE: %s (%s)\n' "$name" "$BOOTSTRAP_REVISION"
}

schedule_reboot() {
    sync

    systemd-run \
        --unit=packertron-bootstrap-reboot \
        --on-active=2m \
        /usr/bin/systemctl reboot -i ||
        die "failed scheduling the required reboot; bootstrap remains incomplete"
}

finalize_bootstrap() {
    schedule_reboot || return
    write_revision_marker "$STATE_DIR/complete"
}

main() {
    [[ "$EUID" -eq 0 ]] || die "run as root"

    BOOTSTRAP_REVISION="$(resolve_bootstrap_revision)"

    install -d -m 0700 "$STATE_DIR"
    install -d -m 0755 "$(dirname -- "$LOG_FILE")" "$(dirname -- "$LOCK_FILE")"
    touch "$LOG_FILE"
    chmod 0600 "$LOG_FILE"

    exec > >(tee -a "$LOG_FILE") 2>&1

    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        printf 'Another bootstrap execution is already running\n'
        return
    fi

    if marker_matches_revision "$STATE_DIR/complete"; then
        printf 'Bare-metal bootstrap already completed for %s\n' "$BOOTSTRAP_REVISION"
        return
    fi

    # Intentionally omitted:
    # 00-update-system.sh  - VM template updates and guest agents
    # 01-cleanup-system.sh - template hygiene, unsafe/unnecessary here
    run_step "02-provision-system" "02-provision-system.sh"
    run_step "03-customize-system" "03-customize-system.sh"

    # The persistent first-boot service is ordered after cloud-final. Record
    # completion only after systemd accepts the required reboot timer.
    finalize_bootstrap

    printf 'Bare-metal bootstrap completed successfully for %s\n' "$BOOTSTRAP_REVISION"
    printf 'Log: %s\n' "$LOG_FILE"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
