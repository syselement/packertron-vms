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

readonly UNIT_PATH=/etc/systemd/system/regenerate-ssh-host-keys.service

# Overridable only so verify_cloud_init_unpinned can be exercised against a
# fixture directory. Nothing in the build sets it.
CLOUD_CFG_DIR="${CLOUD_CFG_DIR:-/etc/cloud/cloud.cfg.d}"
readonly CLOUD_CFG_DIR

# The seed removes subiquity's cloud-init pinning in late-commands, with rm -f.
# That is a silent operation: if a file is ever renamed - and it has been, the
# networking drop-in ships as 00-subiquity-disable-cloudinit-networking.cfg,
# not the bare name older recipes use - rm matches nothing and still exits 0.
# The install then succeeds and produces a template whose clones never read
# their cloud-init drive: no hostname, no user, no key, no address, and no
# error anywhere to explain it.
#
# Checking it here, over SSH, where a non-zero exit fails the build, is the
# only cheap way to find that out before a clone does.
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
        die "subiquity's cloud-init pinning survived the install; clones would ignore their cloud-init drive"
    fi

    if grep -rqs -E 'config: *disabled' "$CLOUD_CFG_DIR"; then
        die "cloud-init networking is still disabled in ${CLOUD_CFG_DIR}; clones would come up with no address"
    fi

    [[ -f "$CLOUD_CFG_DIR/99-pve.cfg" ]] ||
        die "missing ${CLOUD_CFG_DIR}/99-pve.cfg; the seed did not set datasource_list"

    grep -qs '^manage_etc_hosts:' "$CLOUD_CFG_DIR/99-pve.cfg" ||
        die "99-pve.cfg does not set manage_etc_hosts; clones would keep the template's name in /etc/hosts"
}

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

# Subiquity writes its own netplan, and it pins the stanza to the build VM's
# MAC address, not just its interface name. Observed on a real Proxmox install:
#
#   ethernets:
#     ens18:
#       dhcp4: true
#       match: {macaddress: bc:24:11:b8:a4:5b}
#       set-name: ens18
#
# Proxmox gives a clone a new MAC, so that match can never succeed there. The
# file is dead config that silently configures nothing - which is worse than it
# sounds, because it is the first place anyone looks when a clone comes up with
# no address, and it hides the fact that cloud-init is the only thing actually
# configuring the NIC. Remove it so 50-cloud-init.yaml is the whole story.
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
    [[ "$EUID" -eq 0 ]] || die "run as root"

    verify_cloud_init_unpinned
    install_host_key_regeneration
    remove_host_keys
    remove_installer_netplan
    remove_random_seed
    log "done"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
