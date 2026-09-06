#!/usr/bin/env bash
#
# Remove the per-machine state that survives an image but must not survive a
# clone. Runs as the last provisioner of a Proxmox template build, after
# scripts/ubuntu/01-cleanup-system.sh.
#
# 01 handles what every template needs: it truncates the machine-id and clears
# /var/lib/cloud so a clone is treated as a new instance. The rest is here
# rather than in 01 because 01 is shared with the VMware templates, and there
# subiquity leaves cloud-init pinned. On those images nothing would regenerate
# what this removes: no host keys means sshd cannot start, and no installer
# netplan means no address. Both are safe here precisely because the Proxmox
# seed unpins cloud-init.
#
# Everything below is state a running system recreates, so this has to run
# after 01 and after the last reboot of the build.

set -Eeuo pipefail

log() { printf '[seal] %s\n' "$*"; }
die() {
    printf '[seal] error: %s\n' "$*" >&2
    exit 1
}

[[ "$EUID" -eq 0 ]] || die "run as root"

readonly UNIT_PATH=/etc/systemd/system/regenerate-ssh-host-keys.service

# Host keys identify the machine, not the image. Shipped in a template, every
# clone answers with the same fingerprint: a client cannot tell two of them
# apart, and swapping one for another raises no warning on a host it has
# connected to before.
#
# Deleting them alone would leave sshd unable to start, so a one-shot unit
# regenerates them before ssh does. ConditionPathExists makes it a no-op on
# every later boot, so it never needs to disable itself.
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

    # Fatal on purpose. If the unit is not enabled, the clone comes up with no
    # host keys and no sshd, which is a far worse failure to debug later than
    # a failed build now.
    systemctl enable regenerate-ssh-host-keys.service ||
        die "failed enabling regenerate-ssh-host-keys.service"
}

remove_host_keys() {
    log "remove SSH host keys"
    rm -f /etc/ssh/ssh_host_* || die "failed removing SSH host keys"
}

# Subiquity writes its own netplan, naming the interface the build VM happened
# to have. cloud-init writes 50-cloud-init.yaml on the clone, so leaving this
# behind gives netplan two sources of truth for one machine, one of them
# describing a device that may not exist there.
remove_installer_netplan() {
    log "remove installer netplan"
    rm -f /etc/netplan/00-installer-config*.yaml ||
        die "failed removing installer netplan"
}

# systemd recreates this on first boot. Shipping one means every clone starts
# from the same entropy seed.
remove_random_seed() {
    log "remove systemd random seed"
    rm -f /var/lib/systemd/random-seed || die "failed removing random seed"
}

main() {
    install_host_key_regeneration
    remove_host_keys
    remove_installer_netplan
    remove_random_seed
    log "done"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
