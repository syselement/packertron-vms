#!/usr/bin/env bats

# Covers templates/proxmox/seal-for-clone.sh, the last provisioner of every
# Linux Proxmox template: it decides what each clone inherits. Every path it
# touches is pointed at a fixture under BATS_TEST_TMPDIR before the script is
# sourced, so no test can reach the real /etc.

setup() {
    export CLOUD_CFG_DIR="$BATS_TEST_TMPDIR/etc/cloud/cloud.cfg.d"
    export CLOUD_DISABLED_FILE="$BATS_TEST_TMPDIR/etc/cloud/cloud-init.disabled"
    export UDEV_RULES_DIR="$BATS_TEST_TMPDIR/etc/udev/rules.d"
    export FSTAB_FILE="$BATS_TEST_TMPDIR/etc/fstab"
    export SSH_HOST_KEY_DIR="$BATS_TEST_TMPDIR/etc/ssh"
    export RANDOM_SEED_FILE="$BATS_TEST_TMPDIR/var/lib/systemd/random-seed"
    mkdir -p "$CLOUD_CFG_DIR" "$UDEV_RULES_DIR" "$SSH_HOST_KEY_DIR" \
        "$(dirname -- "$RANDOM_SEED_FILE")"

    # shellcheck disable=SC1091
    source "$BATS_TEST_DIRNAME/../../../templates/proxmox/seal-for-clone.sh"
}

@test "seal writes the Proxmox datasource list and host management" {
    write_pve_cloud_init_config

    [[ "$(<"$CLOUD_CFG_DIR/99-pve.cfg")" == $'datasource_list: [ NoCloud, ConfigDrive ]\nmanage_etc_hosts: localhost' ]]
    [[ "$(stat -c '%a' "$CLOUD_CFG_DIR/99-pve.cfg")" == "644" ]]
}

@test "seal re-enables cloud-init and is a no-op where it was never disabled" {
    : >"$CLOUD_DISABLED_FILE"

    enable_cloud_init
    [[ ! -e "$CLOUD_DISABLED_FILE" ]]

    run enable_cloud_init
    [[ "$status" -eq 0 ]]
}

@test "seal accepts a cloud-init configuration that nothing pins" {
    printf 'datasource_list: [ NoCloud, ConfigDrive ]\n' >"$CLOUD_CFG_DIR/99-pve.cfg"
    printf 'system_info:\n  default_user:\n    name: ubuntu\n' >"$CLOUD_CFG_DIR/90_dpkg.cfg"

    run verify_cloud_init_unpinned

    [[ "$status" -eq 0 ]]
}

@test "seal fails the build when subiquity's installer config survives" {
    printf 'datasource_list: [ None ]\n' >"$CLOUD_CFG_DIR/99-installer.cfg"

    run verify_cloud_init_unpinned

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"99-installer.cfg"* ]]
    [[ "$output" == *"clones would ignore their cloud-init drive"* ]]
}

@test "seal fails the build when cloud-init networking is disabled" {
    printf 'network: {config: disabled}\n' >"$CLOUD_CFG_DIR/subiquity-disable-cloudinit-networking.cfg"

    run verify_cloud_init_unpinned
    [[ "$status" -ne 0 ]]

    rm -f "$CLOUD_CFG_DIR/subiquity-disable-cloudinit-networking.cfg"
    printf 'network:\n  config: disabled\n' >"$CLOUD_CFG_DIR/50-local.cfg"

    run verify_cloud_init_unpinned
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"clones would come up with no address"* ]]
}

@test "seal fails the build when cloud-init is still switched off" {
    : >"$CLOUD_DISABLED_FILE"

    run verify_cloud_init_unpinned

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"cloud-init would never run on a clone"* ]]
}

@test "seal removes only the installer's cdrom entry and keeps the fstab's mode" {
    cat >"$FSTAB_FILE" <<'FSTAB'
# /media/cdrom0 was the install medium
/dev/mapper/vg-root /               ext4    errors=remount-ro 0       1
UUID=1234-ABCD      /boot/efi       vfat    umask=0077        0       1
/dev/sr0            /media/cdrom0   udf,iso9660 user,noauto   0       0
FSTAB
    chmod 0640 "$FSTAB_FILE"

    remove_cdrom_fstab_entry

    ! grep -q '^/dev/sr0' "$FSTAB_FILE"
    grep -q '^# /media/cdrom0 was the install medium' "$FSTAB_FILE"
    grep -q '^/dev/mapper/vg-root ' "$FSTAB_FILE"
    grep -q '^UUID=1234-ABCD ' "$FSTAB_FILE"
    [[ "$(stat -c '%a' "$FSTAB_FILE")" == "640" ]]
}

@test "seal leaves an fstab with no cdrom entry untouched" {
    printf '/dev/mapper/vg-root / ext4 defaults 0 1\n' >"$FSTAB_FILE"
    local before
    before="$(stat -c '%Y %s' "$FSTAB_FILE")"
    sleep 1

    remove_cdrom_fstab_entry

    [[ "$(stat -c '%Y %s' "$FSTAB_FILE")" == "$before" ]]
}

@test "seal hides the cloud-init drive from udisks" {
    hide_cloud_init_drive

    [[ "$(<"$UDEV_RULES_DIR/99-hide-cidata.rules")" == 'ENV{ID_FS_LABEL}=="cidata", ENV{UDISKS_IGNORE}="1"' ]]
    [[ "$(stat -c '%a' "$UDEV_RULES_DIR/99-hide-cidata.rules")" == "644" ]]
}

@test "seal removes the host keys and the random seed, and nothing else" {
    local key
    for key in ssh_host_ed25519_key ssh_host_ed25519_key.pub ssh_host_rsa_key ssh_host_rsa_key.pub; do
        printf 'key\n' >"$SSH_HOST_KEY_DIR/$key"
    done
    printf 'Port 22\n' >"$SSH_HOST_KEY_DIR/sshd_config"
    printf 'seed\n' >"$RANDOM_SEED_FILE"

    remove_host_keys
    remove_random_seed

    [[ -z "$(find "$SSH_HOST_KEY_DIR" -name 'ssh_host_*')" ]]
    [[ -f "$SSH_HOST_KEY_DIR/sshd_config" ]]
    [[ ! -e "$RANDOM_SEED_FILE" ]]
}

@test "seal refuses to run without root" {
    if ((EUID == 0)); then
        skip "the suite is running as root"
    fi

    run main

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"run as root"* ]]
    [[ ! -e "$CLOUD_CFG_DIR/99-pve.cfg" ]]
}

@test "a Kali build seals: cloud-init re-enabled, cdrom entry gone, nothing pinned" {
    : >"$CLOUD_DISABLED_FILE"
    printf '/dev/sr0 /media/cdrom0 udf,iso9660 user,noauto 0 0\n' >"$FSTAB_FILE"
    printf 'key\n' >"$SSH_HOST_KEY_DIR/ssh_host_ed25519_key"

    # main's own order, without its root check.
    write_pve_cloud_init_config
    enable_cloud_init
    verify_cloud_init_unpinned
    remove_cdrom_fstab_entry
    hide_cloud_init_drive
    remove_host_keys
    remove_random_seed

    [[ ! -e "$CLOUD_DISABLED_FILE" ]]
    [[ ! -s "$FSTAB_FILE" ]]
    [[ -f "$CLOUD_CFG_DIR/99-pve.cfg" ]]
    [[ ! -e "$SSH_HOST_KEY_DIR/ssh_host_ed25519_key" ]]
}
