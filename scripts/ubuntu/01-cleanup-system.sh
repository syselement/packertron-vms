#!/usr/bin/env bash
#
# Seal an Ubuntu VM template: strip caches, logs and per-machine identity so
# clones start clean.
#
# This is a template-build step. It is destructive on a running system: it
# truncates the machine-id and deletes every file under /tmp and /var/tmp.
# 90-bootstrap-baremetal.sh deliberately never calls it. Set
# PACKERTRON_ALLOW_CLEANUP=true to run it somewhere the guard does not
# recognise as a template build.
#

set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

# Kept in step with lib/apt.sh by tests/cleanup-system.bats, but deliberately
# not sourced from there: Packer's shell provisioner uploads this script on its
# own, with no lib/ directory beside it, so it must stay self-contained.
run_apt_get() {
    DEBIAN_FRONTEND=noninteractive apt-get \
        -o DPkg::Lock::Timeout=300 \
        -o Acquire::Retries=3 \
        -o Acquire::http::Timeout=30 \
        -o Acquire::https::Timeout=30 \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold \
        "$@"
}

log() { printf '[cleanup] %s\n' "$*"; }
die() {
    printf '[cleanup] ERROR: %s\n' "$*" >&2
    exit 1
}

# Refuse to seal a machine that is not being built as a template. Packer sets
# PACKER_BUILD_NAME; anything else has to opt in explicitly.
require_template_build() {
    if [[ "${PACKERTRON_ALLOW_CLEANUP:-}" == "true" ]]; then
        log "cleanup explicitly allowed by PACKERTRON_ALLOW_CLEANUP"
        return 0
    fi

    [[ -n "${PACKER_BUILD_NAME:-}" || -n "${PACKER_BUILDER_TYPE:-}" ]] ||
        die "refusing to run outside a template build; this truncates the machine-id and clears /tmp (set PACKERTRON_ALLOW_CLEANUP=true to override)"
}

remove_package_caches() {
    log "apt autoremove/clean"
    run_apt_get -y autoremove --purge
    run_apt_get -y clean
    rm -rf /var/lib/apt/lists/*
}

vacuum_journal() {
    log "journal cleanup (best effort)"
    # Best effort: a template with no journal yet, or a read-only journal, is
    # not a reason to fail the build.
    journalctl --rotate || log "journal rotate skipped"
    journalctl --vacuum-time=1s || log "journal vacuum skipped"
}

# Failure here must be fatal: a template that keeps its machine-id produces
# clones that share DHCP DUIDs and journal identities, and the fault only
# appears after cloning.
reset_machine_id() {
    log "reset machine-id (for templating/cloning)"
    truncate -s 0 /etc/machine-id ||
        die "failed truncating /etc/machine-id"
    [[ ! -e /var/lib/dbus/machine-id ]] ||
        truncate -s 0 /var/lib/dbus/machine-id ||
        die "failed truncating /var/lib/dbus/machine-id"
}

remove_temporary_files() {
    log "remove temp files and history"
    rm -rf /tmp/* /var/tmp/* || log "temporary file removal incomplete"
}

# Also fatal: leftover cloud-init state marks the instance as already
# provisioned, so per-clone cloud-init never runs again.
reset_cloud_init() {
    command -v cloud-init >/dev/null 2>&1 || return 0

    log "cloud-init clean"
    cloud-init clean --logs ||
        die "failed cleaning cloud-init state"
    rm -rf /var/lib/cloud/* ||
        die "failed removing /var/lib/cloud contents"
}

main() {
    [[ "$EUID" -eq 0 ]] || die "run as root"

    require_template_build
    remove_package_caches
    vacuum_journal
    reset_machine_id
    remove_temporary_files
    reset_cloud_init

    log "done"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
