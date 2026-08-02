# Ubuntu Provisioning Scripts

Provisioning and customization scripts for Ubuntu Desktop and Ubuntu Server.

The same scripts support Packer template builds, Vagrant provisioning, manual runs, and unattended bare-metal installation through cloud-init/autoinstall.

The set covers:

- base OS updates and VMware or QEMU/KVM guest tooling
- cleanup and template hygiene
- baseline sysadmin/devops/IaC tooling installation
- Server-compatible user tooling
- Desktop applications, GNOME preferences, and user configuration
- retryable first-boot orchestration for autoinstall

`02-provision-system.sh` and `03-customize-system.sh` share `lib/ubuntu-context.sh`. The helper verifies Ubuntu, detects Desktop or Server from installed Ubuntu metapackages, defaults to Server when no flavor metapackage is installed, records whether execution is interactive, and resolves the non-root target user.
Set `TARGET_USER` explicitly when an automated root run has more than one eligible local user.

---

## Files

### `00-update-system.sh`
Updates the base system and installs a minimal baseline required for the VM itself. It:

- runs `apt-get update` and `apt-get dist-upgrade`
- installs basic packages such as `net-tools` and `unzip`
- waits up to 300 seconds for the dpkg lock on every APT operation
- detects the VM platform with `systemd-detect-virt --vm`
- installs `open-vm-tools` on VMware guests
- adds `open-vm-tools-desktop` only on Ubuntu Desktop when the package exists
- installs `qemu-guest-agent` on QEMU/KVM guests, including Proxmox VMs

Use this during a VM template build. Bare-metal provisioning intentionally skips it because guest agents are not applicable there.

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
Installs the main tooling stack for Ubuntu Desktop or Server. It:

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

This script can be used by itself when only system provisioning is required.

---

### `03-customize-system.sh`
Installs common user tooling on both variants and applies the Desktop layer only when Ubuntu Desktop is detected. It:

- logs to `/var/log/customize-system-<run_id>.log`
- checks internet and DNS connectivity
- updates the OS and refreshes snaps on Desktop
- installs common and variant-specific package groups
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
- applies GNOME settings only on Desktop
- prints variant-specific manual post-install instructions
- reboots at the end

Set `REBOOT_AT_END=false` when an orchestrator such as Vagrant owns the reboot.

---

### `90-bootstrap-baremetal.sh`

Orchestrates first-boot provisioning for autoinstall and bare-metal systems. It:

- runs `02-provision-system.sh` and `03-customize-system.sh` without their individual reboots
- records revision-bound step markers under `/var/lib/packertron-bootstrap`
- resumes incomplete work without repeating completed steps for the same revision
- schedules the final reboot only after both steps succeed
- logs to `/var/log/packertron-bootstrap.log`

It is an orchestrator, not an additional step to run after manually completing `02` and `03`.

---

### Autoinstall YAML files

- `autoinstall-desktop.yaml` installs Ubuntu Desktop and creates the retryable first-boot service.
- `autoinstall-server.yaml` installs Ubuntu Server and creates the same first-boot workflow.
- `autoinstall-noscripts.yaml` is the intentional negative control: it performs the unattended installation but invokes no provisioning scripts.

The scripted YAML files write `/usr/local/sbin/packertron-firstboot` and a temporary systemd service. The runner checks out one fixed repository revision and invokes `90-bootstrap-baremetal.sh`. Transient failures are retried; after a successful run the service disables and removes itself.

---

## Execution paths

### Packer template build

```text
00-update-system.sh → 01-cleanup-system.sh
```

### Vagrant-provisioned workstation

```text
02-provision-system.sh → Vagrant reboot → 03-customize-system.sh → Vagrant reboot
```

Vagrant sets `REBOOT_AT_END=false` and waits for SSH after each managed reboot.

### Autoinstall / bare-metal first boot

```text
autoinstall YAML → packertron-firstboot.service → 90-bootstrap-baremetal.sh
                                                   ├─ 02-provision-system.sh
                                                   └─ 03-customize-system.sh
```

### Manual provisioning

Run `02` by itself for system-only provisioning:

```bash
sudo ./02-provision-system.sh
```

Run customization without an automatic reboot:

```bash
sudo env REBOOT_AT_END=false ./03-customize-system.sh
```

---

## Intended script order

The repository keeps the following logical order:

```bash
00-update-system.sh
01-cleanup-system.sh
02-provision-system.sh
03-customize-system.sh
90-bootstrap-baremetal.sh  # orchestration entry point where applicable
```

`00` and `01` are template-build stages. `90` invokes `02` and `03` itself, so do not run all five sequentially on an already installed machine.

## Validation

Static and mocked tests can be run without changing the workstation:

```bash
bash -n ./*.sh ./lib/*.sh
shellcheck -x ./*.sh ./lib/*.sh
shfmt -d -i 4 -ci ./*.sh ./lib/*.sh
bats tests
git diff --check
```

APT, systemd, GNOME, virtualization and reboot behavior still require a disposable Ubuntu VM for integration testing.
