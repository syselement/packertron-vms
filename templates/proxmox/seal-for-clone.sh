#!/usr/bin/env bash
#
# Remove per-machine state that must not survive a clone. Runs as the last provisioner of a Proxmox template build, after 01-cleanup-system.sh.
#
# Proxmox-only, not part of 01, because 01 is shared with the VMware templates
# where cloud-init stays pinned: there nothing would regenerate any of this, so
# the image would come up with no sshd and no address.
#
# All of it is state a running system recreates, so this must run after the last reboot of the build.
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

# - The seed removes subiquity's pinning with `rm -f`, which exits 0 whether or not it matched.
# - A miss produces a template whose clones never read their cloud-init drive - no hostname, user, key or address, and nothing in any log to say why.
# - This runs over SSH, where a non-zero exit fails the build.
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

# - Host keys identify the machine, not the image: shipped in a template, every clone answers with the same fingerprint and swapping one for another warns nobody.
# - Deleting them alone would leave sshd unable to start, so a one-shot unit regenerates them first.
# - ConditionPathExists makes it a no-op on later boots, so it never has to disable itself.
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

    # Fatal on purpose: an unenabled unit means a clone with no host keys and no sshd, which is far worse to debug than a failed build.
    systemctl enable regenerate-ssh-host-keys.service ||
        die "failed enabling regenerate-ssh-host-keys.service"
}

remove_host_keys() {
    log "remove SSH host keys"
    rm -f /etc/ssh/ssh_host_* || die "failed removing SSH host keys"
}

# - Subiquity pins its netplan stanza to the build VM's MAC, not just the interface name, so on a clone it matches nothing and configures nothing.
# - It is then the first file anyone opens when a clone has no address, hiding the fact that cloud-init is doing all the work.
# - Remove it.
remove_installer_netplan() {
    log "remove installer netplan"
    rm -f /etc/netplan/00-installer-config*.yaml ||
        die "failed removing installer netplan"
}

# Shipping one means every clone starts from the same entropy seed.
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
