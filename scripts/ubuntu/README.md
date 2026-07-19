# Debian/Ubuntu Bash Scripts

Bootstrap and customization scripts for the Ubuntu Desktop workstation.

These scripts are designed to be run in order, typically from Vagrant shell provisioners, to turn a freshly built Ubuntu Desktop VM into a usable workstation for homelab, IaC, and daily operations.
The set currently covers:

- base OS update and VMware guest tooling
- cleanup and template hygiene
- baseline sysadmin/devops/IaC tooling installation
- desktop customization, user preferences, and extra apps

`02-provision-system.sh` and `03-customize-system.sh` share
`lib/ubuntu-context.sh`. The helper verifies Ubuntu, detects Desktop or Server
from installed Ubuntu metapackages, defaults to Server when no flavor
metapackage is installed, records whether execution is interactive, and
resolves the non-root target user. Set `TARGET_USER` explicitly when an
automated root run has more than one eligible local user.

---

## Files

### `00-update-system.sh`
Updates the base system and installs a minimal baseline required for the VM itself. It:

- runs `apt-get update` and `apt-get dist-upgrade`
- installs basic packages such as `net-tools` and `unzip`
- installs and enables VMware guest tools (`open-vm-tools`, `open-vm-tools-desktop` when available)

Use this early in the build to bring the OS up to date and make the VM behave correctly inside VMware.

---

### `01-cleanup-system.sh`
Performs cleanup and template hygiene. It:

- runs `apt autoremove` and `apt clean`
- removes cached apt lists
- rotates and vacuums journald logs
- truncates `/etc/machine-id` and `/var/lib/dbus/machine-id`
- removes temporary files
- cleans cloud-init state if present

Use this before packaging a template or box so clones start from a cleaner state.

---

### `02-provision-system.sh`
Installs the main tooling stack for the Ubuntu ops workstation. It:

- logs to `/var/log/provision-system-<run_id>.log`
- expands the root LVM volume if free space is available
- updates the system
- installs baseline packages needed for provisioning
- configures external repositories for:
  - Ansible
  - VS Code
  - Docker
  - OpenTofu
  - HashiCorp
- installs:
  - `ansible`
  - `code`
  - Docker Engine and Compose plugin
  - `packer`
  - `tofu`
- enables Docker and adds the configured user to the `docker` group
- waits for APT/dpkg locks and fails when required package or repository setup fails
- installs repository keys and source definitions only after validating staged files
- expands the standard Ubuntu LVM root when free extents exist (`EXPAND_LVM_ROOT=false` disables this)
- prints validation output and basic system information
- reboots at the end

This is the main “sysadmin + devops + IaC tools” bootstrap script.

---

### `03-customize-system.sh`
Applies desktop customization and installs additional user-facing tools. It:

- logs to `/var/log/customize-system-<run_id>.log`
- checks internet and DNS connectivity
- updates the OS and refreshes snaps
- installs a large desktop/tooling package set
- installs and configures:
  - Terminator
  - Sublime Text
  - Brave
  - DBeaver
  - Flameshot
  - Obsidian
  - Postman
  - Emote
  - `tldr` via `pipx`
  - JetBrainsMono Nerd Font
- applies GNOME settings through `dbus-run-session`
- configures dock and power/lock-screen preferences
- prints a manual post-run section for SSH key import and Flameshot shortcut setup
- reboots at the end

This is the customized desktop layer.

---

## Expected order

Recommended execution order:

```bash
00-update-system.sh
01-cleanup-system.sh
02-provision-system.sh
03-customize-system.sh
```

---
