#!/usr/bin/env bash
#
# Remove per-machine state that must not survive a clone, and write the
# cloud-init config a clone needs. Runs as the last provisioner of a Proxmox
# template build, after 01-cleanup-system.sh.
#
# Proxmox-only, not part of 01, because 01 is shared with the VMware templates
# where cloud-init stays pinned: there nothing would regenerate any of this, so
# the image would come up with no sshd.
#
# Deliberately small. 01 already truncates the machine-id, clears
# /var/lib/cloud, and runs `cloud-init clean`, which takes subiquity's own
# drop-ins with it. Only what 01 cannot do belongs here.
#
# Docs:
#   cloud-init      https://cloudinit.readthedocs.io/en/latest/
#   Proxmox cloning https://pve.proxmox.com/wiki/VM_Templates_and_Clones
#   README.md       ../ubuntu-24.04-server/README.md, "What the build removes"
#
# Run:
#   Packer invokes this as a provisioner; it is not meant to be run by hand.
#   Lint it with: ../../scripts/check-templates.sh shell

set -Eeuo pipefail

log() { printf '[seal] %s\n' "$*"; }
die() {
    printf '[seal] error: %s\n' "$*" >&2
    exit 1
}

readonly UNIT_PATH=/etc/systemd/system/regenerate-ssh-host-keys.service

# Overridable only so the check below can be run against a fixture.
CLOUD_CFG_DIR="${CLOUD_CFG_DIR:-/etc/cloud/cloud.cfg.d}"
readonly CLOUD_CFG_DIR

# Written here, not at install time. Setting datasource_list before the first
# boot drops None from it, and None is the datasource that carries subiquity's
# 99-installer.cfg - so cloud-init would find no datasource, apply nothing, and
# the seed's ssh: section would never reach the machine.
#
# - datasource_list narrows a clone to the drive Proxmox attaches.
# - manage_etc_hosts keeps /etc/hosts in step with the hostname cloud-init sets.
#   Ubuntu leaves it unset and has no `myhostname` in nsswitch to cover for it,
#   so a clone would be renamed while /etc/hosts still named the template and
#   every sudo would print "unable to resolve host". `localhost` fixes only the
#   127.0.1.1 line; `true` would rewrite the whole file on every boot.
write_pve_cloud_init_config() {
    log "write ${CLOUD_CFG_DIR}/99-pve.cfg"
    cat >"$CLOUD_CFG_DIR/99-pve.cfg" <<'CFG'
datasource_list: [ NoCloud, ConfigDrive ]
manage_etc_hosts: localhost
CFG
    chmod 0644 "$CLOUD_CFG_DIR/99-pve.cfg"
}

# `cloud-init clean` in 01 removes subiquity's drop-ins, so nothing here has to.
# This only checks that it did: a leftover that pins the datasource or disables
# networking produces a template whose clones come up with no hostname, user,
# key or address, and nothing in any log to say why. Failing the build is the
# only way that gets noticed before a clone does.
verify_cloud_init_unpinned() {
    local leftovers

    log "verify cloud-init is unpinned"

    leftovers="$(
        find "$CLOUD_CFG_DIR" -maxdepth 1 -type f \
            \( -name '*installer*' -o -name '*disable-cloudinit-networking*' \) \
            -printf '%f\n' 2>/dev/null
    )"
    if [[ -n "$leftovers" ]]; then
        printf '[seal] still present in %s:\n%s\n' "$CLOUD_CFG_DIR" "$leftovers" >&2
        die "subiquity's cloud-init config survived; clones would ignore their cloud-init drive"
    fi

    if grep -rqs -E 'config: *disabled' "$CLOUD_CFG_DIR"; then
        die "cloud-init networking is disabled in ${CLOUD_CFG_DIR}; clones would come up with no address"
    fi
}

# Host keys identify the machine, not the image: shipped in a template, every
# clone answers with the same fingerprint and swapping one for another warns
# nobody. Deleting them alone would leave sshd unable to start, so a one-shot
# unit regenerates them first. ConditionPathExists makes it a no-op on later
# boots, so it never has to disable itself.
install_host_key_regeneration() {
    log "install ${UNIT_PATH}"
    cat >"$UNIT_PATH" <<'UNIT'
[Unit]
Description=Regenerate SSH host keys on the first boot of a clone
Before=ssh.service ssh.socket
ConditionPathExists=!/etc/ssh/ssh_host_ed25519_key

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/ssh-keygen -A

[Install]
WantedBy=multi-user.target
UNIT
    chmod 0644 "$UNIT_PATH"

    # Fatal on purpose: an unenabled unit means a clone with no host keys and
    # no sshd, which is far worse to debug than a failed build.
    systemctl enable regenerate-ssh-host-keys.service ||
        die "failed enabling regenerate-ssh-host-keys.service"
}

remove_host_keys() {
    log "remove SSH host keys"
    rm -f /etc/ssh/ssh_host_* || die "failed removing SSH host keys"
}

# systemd credits this to the entropy pool at boot and recreates it. Shipping
# one means every clone starts from the same seed.
remove_random_seed() {
    log "remove systemd random seed"
    rm -f /var/lib/systemd/random-seed || die "failed removing random seed"
}

main() {
    [[ "$EUID" -eq 0 ]] || die "run as root"

    write_pve_cloud_init_config
    verify_cloud_init_unpinned
    install_host_key_regeneration
    remove_host_keys
    remove_random_seed
    log "done"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
