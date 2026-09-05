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

- Set `TARGET_USER` explicitly when an automated root run has more than one eligible local user.

`02-provision-system.sh` and `03-customize-system.sh` share `lib/apt.sh` (one hardened `run_apt_get` with dpkg lock timeout, acquire retries, network timeouts and noninteractive conffile handling) and `lib/download.sh` (`fetch_file` with an outer retry loop and stall detection, plus `fetch_file_range` for reading package metadata without a full download).

`03-customize-system.sh` also sources `lib/custom-tools.sh`, which holds every third-party and custom tool installer grouped by how the tool is distributed (APT repository, direct `.deb` URL, GitHub release, Snap, vendor install script, archive, checksum-verified binary, pipx). **Add new tools there, following the template comment on the matching section.**

`00-update-system.sh` and `01-cleanup-system.sh` each keep their own copy of the APT wrapper, because Packer's shell provisioner uploads those two on their own with no `lib/` directory beside them. `tests/update-system.bats` and `tests/cleanup-system.bats` assert the copies stay identical to the shared one.

- The `Dpkg::Options::=--force-confdef` / `--force-confold` in that wrapper are not redundant with `DEBIAN_FRONTEND=noninteractive`: that governs debconf, while dpkg's own *"Configuration file '…' what would you like to do about it?"* prompt is separate. Without them, a run started from a terminal - the documented way to run `02` and `03` - blocks indefinitely on any locally modified conffile.

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
Seals a VM template so clones start clean. It:

- runs `apt autoremove` and `apt clean`
- removes cached apt lists
- rotates and vacuums journald logs (best effort)
- truncates `/etc/machine-id` and `/var/lib/dbus/machine-id`
- removes temporary files
- cleans cloud-init state if present

**This is destructive on a running system.**

- It truncates the machine-id (breaking systemd/D-Bus identity, journald and DHCP DUIDs on the next boot) and deletes everything under `/tmp` and `/var/tmp`, including other processes' files.
- It therefore refuses to run unless Packer set `PACKER_BUILD_NAME`/`PACKER_BUILDER_TYPE`, or `PACKERTRON_ALLOW_CLEANUP=true` is passed explicitly.

The machine-id truncation and the cloud-init clean are fatal on failure, deliberately. Both produce a template that looks fine and only misbehaves after cloning: clones sharing a machine-id collide on DHCP DUIDs and journal identities, and leftover cloud-init state marks every clone as already provisioned.

Run it last in a template build, after every other provisioning step.

`90-bootstrap-baremetal.sh` never calls it.

---

### `02-provision-system.sh`
Installs the main tooling stack for Ubuntu Desktop or Server. It:

- logs to `/var/log/provision-system-<run_id>.log`
- expands the root LVM volume if free space is available
- updates the system
- installs baseline packages needed for provisioning
- configures external repositories for:
  - Ansible
  - Docker
  - OpenTofu
  - HashiCorp
  - VS Code (Desktop only)
- installs:
  - `ansible`
  - Docker Engine and Compose plugin
  - `packer`
  - `tofu`
  - `vagrant`
  - `code` (Desktop only)
- enables Docker, then adds the configured user to the `docker` group
- waits for APT/dpkg locks and fails when required package or repository setup fails
- installs repository keys and source definitions only after validating staged files
- expands the standard Ubuntu LVM root when free extents exist (`EXPAND_LVM_ROOT=false` disables this)
- prints validation output and basic system information
- reports whether `/var/run/reboot-required` is set, naming the packages that need one
- reboots at the end

VS Code is Desktop-only: its repository, its package and its `code --version` check are all gated on the detected variant. On Server the package would drag in an unused X stack, and the version check would fail the whole run. Every other tool is a CLI and is installed on both variants.

Group membership is granted after the service is up, not before. A `usermod -aG` is persistent, so it must never outlive a daemon that failed to start.

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
- reports whether `/var/run/reboot-required` is set, naming the packages that need one
- reboots at the end

Set `REBOOT_AT_END=false` when an orchestrator such as Vagrant owns the reboot. With the reboot deferred, a pending-reboot report also prints the command to run by hand.

Desktop packages are installed with an availability check rather than a hard failure. The manifests are shared between releases, so a package that entered Ubuntu after 24.04 is simply absent there; skipped packages are listed in a single warning line, because a third-party repository that failed to configure looks the same as a release difference.

On Server, Syncthing's user service is enabled and lingering is turned on for the target user, so systemd starts the user manager at boot. Without it an "enabled" user service on a headless host stays permanently stopped, because nothing ever logs in interactively.

---

### `90-bootstrap-baremetal.sh`

Orchestrates first-boot provisioning for autoinstall and bare-metal systems. It:

- runs `02-provision-system.sh` and `03-customize-system.sh` without their individual reboots
- passes `TARGET_USER` through to both steps when it is set
- records revision-bound step markers under `/var/lib/packertron-bootstrap`
- resumes incomplete work without repeating completed steps for the same revision
- warns logged-in users with `wall`, then schedules one reboot two minutes out
- records completion only after systemd accepts that reboot timer
- logs to `/var/log/packertron-bootstrap.log`

It is an orchestrator, not an additional step to run after manually completing `02` and `03`.

It deliberately skips `00` (guest agents do not apply to bare metal) and `01` (template hygiene, destructive here).

---

### Autoinstall YAML files

- `autoinstall-desktop.yaml` installs Ubuntu Desktop and creates the retryable first-boot service.
- `autoinstall-server.yaml` installs Ubuntu Server and creates the same first-boot workflow.
- `autoinstall-noscripts.yaml` is the intentional negative control: it performs the unattended installation but invokes no provisioning scripts.

The scripted YAML files write `/usr/local/sbin/packertron-firstboot` and a temporary systemd service.

- The runner checks out one fixed repository revision and invokes `90-bootstrap-baremetal.sh`.
- Transient failures are retried.
- After a successful run the service disables and removes itself.

---

## How to use these scripts

Pick the entry point, not the individual script. Each row is a complete way to build a machine; do not mix two of them on the same host.

| Goal | Entry point | What runs | Variants |
| --- | --- | --- | --- |
| Build a reusable VM template | `packer build` in a template directory | `00` → `01` (Desktop), `00` → `02` → `01` (24.04 Server) | Desktop and Server |
| Turn a prebuilt box into a workstation | `vagrant up provisioned` | `02` → reboot → `03` → reboot | Desktop |
| Install a physical machine unattended | `autoinstall-desktop.yaml` / `autoinstall-server.yaml` | firstboot service → `90` → `02` → `03` | Desktop and Server |
| Provision a machine you already installed | `sudo env TARGET_USER="$USER" ./90-bootstrap-baremetal.sh` | `90` → `02` → `03`, one reboot at the end | Desktop and Server |
| Add tooling to a machine by hand | `02` and/or `03` directly | only what you invoke | Desktop and Server |

Rules that follow from this:

- **`00` and `01` are template-build stages only.** `90` deliberately skips both. Never run `01` on a machine you care about; see its section above.
- **`90` is an orchestrator, not a fifth step.** It invokes `02` and `03` itself. Do not run `02`, `03` and then `90`.
- **`REBOOT_AT_END=false` is for orchestrators.** Vagrant, `90` and the Packer server template all set it and own the reboot themselves. Set it for a manual run too, then reboot when the pending-reboot report tells you to.
- **`TARGET_USER` is only needed when the target user cannot be inferred.** Under `sudo` it comes from `SUDO_USER`. Under systemd there is no `SUDO_USER`, so `90` and the firstboot runner pass it explicitly; without it the fallback requires exactly one eligible account and fails permanently once a second one exists.
- **The variant is detected, not configured.** `lib/ubuntu-context.sh` reads the installed Ubuntu flavor metapackages and defaults to Server when none is present. There is no flag to override it.

### Credentials

The autoinstall YAML files and the Packer `http/user-data` files contain **hardcoded credentials**, intentionally, for a single-operator lab:

- the `syselement` account's SHA-512 password hash is the same in every file, and the plaintext (`packer`) is documented alongside it - a published salt plus a published plaintext is a published console password. `allow-pw: false` only disables SSH password authentication; console, TTY and GDM login are unaffected.
- a fixed ed25519 public key is authorized on every image.
- `/etc/sudoers.d/99-syselement` grants permanent `NOPASSWD:ALL` and is never removed after bootstrap.

These images are not suitable for a shared or internet-reachable network as shipped. Change the hash (`mkpasswd -m sha-512`), the authorized key and the sudoers rule before building anything that leaves the lab.

---

## Execution paths

### Packer template build

```text
# Desktop templates
00-update-system.sh → 01-cleanup-system.sh

# 24.04 Server
00-update-system.sh → 02-provision-system.sh → 01-cleanup-system.sh
```

- `01` always runs last: it seals the template, and anything after it would put per-machine state straight back into the image.
- The Server template stages the whole `scripts/ubuntu` tree with a `file` provisioner before running `02`, because `02` sources `lib/*.sh` and a Packer `scripts` list uploads each file on its own with no `lib/` beside it.

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

Provision a machine you already installed, both steps with one reboot at the end:

```bash
git clone https://github.com/syselement/packertron-vms.git
cd packertron-vms/scripts/ubuntu
sudo env TARGET_USER="$USER" ./90-bootstrap-baremetal.sh
```

Run `02` by itself for system-only provisioning:

```bash
sudo ./02-provision-system.sh
```

Run customization without an automatic reboot:

```bash
sudo env REBOOT_AT_END=false ./03-customize-system.sh
```

Both print a pending-reboot report at the end, so a deferred run says what still needs a restart.

---

## Numbering and script order

The numeric prefixes describe the logical stage, not a sequence to run end to end:

```bash
00-update-system.sh        # template build: base updates and guest agents
01-cleanup-system.sh       # template build: seal the image, runs LAST
02-provision-system.sh     # tooling stack
03-customize-system.sh     # user tooling, applications, Desktop layer
90-bootstrap-baremetal.sh  # orchestrator, runs 02 and 03 itself
```

`01` is the exception to reading the numbers as an order: it seals a template and must be the final step of a build, after `02` where a build runs it. `90` invokes `02` and `03` itself, so do not run all five sequentially on an already installed machine.

### APT update behavior

The repeated APT metadata refreshes in the update and provisioning phases are intentional.

Each script must remain independently executable and cannot assume a previous phase completed successfully.

`02` and `03` therefore both run `dist-upgrade` unconditionally, including when `90` invokes them back to back.

## Validation

### Static checks

These are the only checks safe to run on a working machine. They change nothing:

```bash
bash -n ./*.sh ./lib/*.sh
shellcheck -x ./*.sh ./lib/*.sh
shfmt -d -i 4 -ci ./*.sh ./lib/*.sh
bats tests
git diff --check
```

The autoinstall files have their own offline check:

```bash
cloud-init schema --config-file autoinstall-desktop.yaml --annotate
cloud-init schema --config-file autoinstall-server.yaml --annotate
```

### Never run these on a machine you use

- `01-cleanup-system.sh` in full - it truncates the machine-id and clears `/tmp` and `/var/tmp`. The template guard now refuses, but do not override it.
- `90-bootstrap-baremetal.sh` - it runs `02` and `03` end to end and schedules a reboot.
- a complete `02` or `03` run - both `dist-upgrade`, add repositories and restart services.

Everything below needs a disposable VM or real hardware.

### Integration test matrix

Snapshot before each run. Record the release, the detected variant and the exact command.

| # | Configuration | Entry path | What to assert |
| --- | --- | --- | --- |
| 1 | 24.04 Desktop | Vagrant (`02` → `03`) | full toolchain; GNOME applied; `variant=desktop` in the log; the `24.*` release arm is taken (`software-properties-common`, fastfetch PPA); any package missing on noble is listed in the skip warning rather than failing the run |
| 2 | 24.04 Server | bare-metal autoinstall | no GNOME, dconf, flatpak or snap work attempted; VS Code **absent** and `02` still passes its toolchain validation; `loginctl show-user <user> --property=Linger` is `yes` and `systemctl --user status syncthing` is running after a reboot; `stat -c '%A' /var/log` is still group-writable (`drwxrwxr-x`) |
| 3 | 26.04 Desktop | Vagrant and bare-metal | as #1 but the `26.*` arm (PPA skipped) |
| 4 | 26.04 Server | bare-metal autoinstall only | as #2. No Packer or Vagrant path exists for this combination |
| 5 | Second execution | all four above | no `installing` or `downloading` lines; no repository rewrites; Cockpit not restarted; `SET … dock-position` is expected (a deliberate persisted value) |
| 6 | Packer build | `00` → `01`, plus `02` on 24.04 Server | template seals; guest agent matches the hypervisor; `/etc/machine-id` is empty; the staged `/var/tmp/packertron-ubuntu` tree is gone |
| 7 | Autoinstall | `autoinstall-{desktop,server}.yaml` | unattended completion; the firstboot service is created and enabled, and removes itself only after real work |
| 8 | Bare-metal bootstrap | `90` | markers under `/var/lib/packertron-bootstrap`; a resumed run skips completed steps; exactly one reboot scheduled after both steps; `/var/log` and `/run/lock` modes unchanged |

### Failure and edge-case scenarios

Run each on at least one Desktop and one Server.

| Scenario | How to induce | Expected |
| --- | --- | --- |
| Second run is a no-op | run the same entry point twice | no installs, no downloads, no repository rewrites, no service restarts |
| Interrupted bootstrap | kill `90` between steps | resumes at `03`, does not repeat `02` |
| Concurrent bootstrap | start `90` twice | the second exits **non-zero**, so the firstboot service keeps its retry instead of deleting itself |
| Two human accounts | `adduser`, then re-run unattended | `TARGET_USER` is passed explicitly, so the run still succeeds |
| Non-git `/opt/packertron-vms` | `mkdir` it, then run | the directory is replaced and the clone proceeds |
| Missing `git` | remove it before first boot | the runner reports git as missing, not an unreachable GitHub |
| Failed repository config | point a repository at an unreachable host | the APT transaction rolls back to the previous sources; clear failure |
| Network loss mid-run | drop the interface during downloads | retries, then a clear failure; no half-installed tree under `/opt` |
| Modified conffile | edit a packaged conffile, then run interactively | the run completes; dpkg keeps the local file instead of prompting |
| Pending reboot | `REBOOT_AT_END=false` after a kernel upgrade | the pending reboot is reported by name, with the command to run |
| Kernel upgrade under `90` | any bare-metal first boot | a `wall` warning, then one reboot two minutes later |
| Fresh snapd seeding | run `03` on a just-installed Desktop | snap installs are bounded at 15m rather than blocking forever |
| Cockpit already configured | run `03` twice, watch `cockpit.socket` | the drop-in is not rewritten and the socket is not restarted |
| Cockpit first install | run `03` once, watch the listening port | the socket only ever listens on 9443, never briefly on 9090 |
| Package absent on this release | add a package that exists on 26.04 only | it is skipped with a warning; the run completes |
| Unsupported release | run outside the 24.x/26.x branches | most branches warn; Tailscale and MKVToolNix fail explicitly |

---
