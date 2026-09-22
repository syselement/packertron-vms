# Kali Linux - Proxmox template

Builds a Kali Linux template on Proxmox VE from the official installer ISO, driven by the debian-installer preseed in `http/`.

> **Status: built on a real node** (Proxmox VE, q35/OVMF, Kali 2026.2, ~10 minutes, template 80200). **Cloning it has not been tested yet.** Three defects were found by building: the `http.kali.org` redirector handing apt an unverifiable HTTPS mirror, the rolling-release upgrade failing opaquely inside `pkgsel`, and `openssl-server` installed but left disabled so nothing listened on port 22. Each is covered in its own section below. The previous version of this directory was a stub with no seed at all, and a pinned checksum that did not match the ISO it named.

Adapted from [mttaggart/seclab](https://github.com/mttaggart/seclab) (`Packer/kali/config.pkr.hcl`); the pristine upstream copy is in `tmp/upstream-originals/kali/` for comparison. Everything the upstream did through KeePass and CA-certificate provisioners is gone: credentials come from the environment, and the build block runs the same `00` -> `01` -> seal chain as every other Proxmox template here.

Firmware, credentials, the SSH-agent login, the seal, and the clone-time model are identical to the Ubuntu templates and documented once, in [`../ubuntu-24.04-server/README.md`](../ubuntu-24.04-server/README.md). This file records only what Kali does differently.

## What differs from the Ubuntu templates

| | Ubuntu | Kali |
| --- | --- | --- |
| Installer | subiquity, `http/user-data` (cloud-config) | debian-installer, `http/kali.preseed` |
| Boot | `<esc>`, edit the GRUB entry | `c` for the GRUB console, start the kernel by hand |
| Seed check | `cloud-init schema` | `debconf-set-selections --checkonly` |
| `00-update-system.sh` | runs | runs - it carries the rolling-release upgrade, which the preseed skips |
| Guest agent | first-boot `user-data:` | `pkgsel/include`, from the network mirror |
| SSH | enabled by subiquity's `ssh: install-server` | installed but **disabled**; `late_command` enables it explicitly |
| cloud-init during the build | pinned to `None` by subiquity's `99-installer.cfg` | switched off by `/etc/cloud/cloud-init.disabled`; the seal removes it |
| Packages | base | `kali-linux-default` + `kali-desktop-xfce` |
| Disk / RAM | 30G / 2048 | 50G / 4096 |
| `vm_id` | 80024, 80026, 80126 | 80200 |

The `00` -> `01` -> seal chain runs unchanged from the Ubuntu templates. Both scripts are distro-agnostic on this path: `01` is apt, cloud-init, journalctl and truncate, with its only guard being "am I under Packer", and `00`'s one Ubuntu-specific check gates the VMware branch, which Proxmox never takes.

## Why cloud-init is switched off for the build

Packer attaches a cloud-init drive to the build VM (`cloud_init = true`, so the template carries one for clones to use). On Ubuntu that drive is ignored during the build because subiquity pins cloud-init to the `None` datasource. Kali's installer does nothing of the kind, so on the first boot cloud-init would consume Packer's drive: Proxmox's generated user-data carries `users: [default]` and `package_upgrade: true`, which means a `debian` account on the template and an `apt upgrade` running underneath the provisioners.

The preseed's `late_command` therefore creates `/etc/cloud/cloud-init.disabled`, cloud-init's own off switch. `seal-for-clone.sh` removes it as its last cloud-init step, and fails the build if it somehow survived, since a clone would then never read its drive.

## The mirror is pinned, deliberately

`mirror/http/hostname` is `kali.download`, not the usual `http.kali.org`. The redirector distributes each file across mirrors, and some of them serve HTTPS - three requests for the same `.deb` came back from three different hosts when this was checked. During the install `/target` has no `ca-certificates`, so apt cannot verify any certificate, and a redirect onto an HTTPS mirror fails with `certificate verify failed`.

That is what broke the first build: seven packages unfetchable, `pkgsel` exiting 100, and the installer stopping at "Select and install software". `ca-certificates` is in `pkgsel/include` so the installed system can use HTTPS afterwards, but it cannot help during the install - hence the plain-HTTP mirror.

## The preseed, in one pass

`late_command` does what the Ubuntu seeds' `ssh:` and `late-commands` sections do, and is the only place Kali-specific setup lives:

- authorised key for `syselement` and NOPASSWD sudo, validated with `visudo -c`
- `PasswordAuthentication no`, the same posture as the Ubuntu templates
- `systemctl enable ssh`, which Kali needs and Ubuntu does not
- the cloud-init off switch above

Everything else is standard debian-installer: `en_GB` / `it` / `Europe/Rome`, LVM on the whole disk, a network mirror with the cdrom entry disabled, and no `unattended-upgrades`. The user and password hash are the ones every seed in this repository uses.

`kali-linux-default` is the toolset; the ISO's own "Software selection" screen adds a desktop beside it, and `kali-desktop-xfce` is that default. Drop it from `pkgsel/include` for a headless template.

## Why the upgrade is not in the preseed

Kali is rolling, so the ISO is only a snapshot and a fresh template should not start life behind. That upgrade runs in `00-update-system.sh`, not as `pkgsel/upgrade`.

The reason is failure reporting. `pkgsel` is all-or-nothing and says only "Installation step failed" on the console; the first build here died there, and the cause - a TLS error against one mirror - was only visible after pulling `/var/log/syslog` off the installer. The same work in a provisioner names itself in Packer's output, is shellcheck'd and covered by the Bats suite, and can be retried without reinstalling the machine.

`qemu-guest-agent` stays in `pkgsel/include` regardless: Packer needs the agent to learn the VM's address before it can run any provisioner at all.

## Why SSH is enabled explicitly

Kali ships `openssh-server` installed but **disabled**, which is a deliberate posture difference from Debian and from Ubuntu. Putting it in `pkgsel/include` therefore gets the package and nothing listening: the machine boots to a desktop with port 22 closed, and the build sits out `ssh_timeout` having never been able to connect. `late_command` runs `in-target systemctl enable ssh` for that reason.

This cost a build here. It is also easy to misdiagnose, because the unit is `ssh.service` on Debian and Kali - `systemctl status sshd` reports "could not be found" whether or not SSH is actually configured, which looks like a missing package when it is not one.

## The installer's cdrom entry has to go

debian-installer writes an fstab line for the install media:

```
/dev/sr0        /media/cdrom0   udf,iso9660 user,noauto     0       0
```

It is stale as soon as the build ends, and on a clone it is actively wrong. Proxmox attaches the cloud-init drive as the only optical device, so `/dev/sr0` now *is* `cidata` - and a desktop clone shows a mounted "cdrom0" containing `user-data`, `network-config` and `vendor-data`. Confirmed on the first Kali clone: `lsblk` reported `sr0 cidata /media/cdrom0`.

The `99-hide-cidata.rules` udev rule does not help. It was present and correct on that clone, and the label really was `cidata`, so udisks was ignoring the device exactly as asked - fstab is simply a different mechanism, and gvfs honours it regardless. `seal-for-clone.sh` removes the line instead. Subiquity writes no such entry, so the Ubuntu templates are unaffected.

## Prior art

Two public Kali preseeds informed this one. Both are worth reading, for opposite reasons.

### badsectorlabs/ludus

[`ludus-server/packer/kali/http/kali-preseed.cfg`](https://gitlab.com/badsectorlabs/ludus/-/blob/main/ludus-server/packer/kali/http/kali-preseed.cfg) reached two of the same conclusions independently, which is the best evidence available that they are right: its mirror is `kali.download` rather than the redirector, and it sets `pkgsel/upgrade select none`. Its `in-target systemctl enable ssh` is where the fix above came from, after a build here installed `openssh-server` and still could not be reached.

It solves a different problem, though, so do not copy its package list. Ludus installs only `qemu-guest-agent openssh-server sudo python3 isc-dhcp-client` and provisions the toolset with Ansible afterwards; this template bakes `kali-linux-default` into the image instead. It also partitions with `partman-auto/method regular` rather than LVM, and hardcodes `grub-installer/bootdev` to `/dev/vda`, which assumes a virtio disk - `default` is used here so the setting does not depend on the controller.

One thing to watch if you borrow from its `late_command`: the first three commands have no `in-target` prefix, so its sudoers edit and its `apt install` land in the installer's ramdisk rather than the installed system and are gone after the reboot. Only the final `in-target systemctl enable ssh` reaches the machine being built.

### blink-zero/kali-2024.1-preseed

[blink-zero/kali-2024.1-preseed](https://github.com/blink-zero/kali-2024.1-preseed) solves the same problem - an unattended Kali install driven by Packer - and is worth reading, because one of its decisions is right and the way it implements that decision is the thing to avoid.

**What it gets right, and what this template took from it.** It sets `pkgsel/upgrade select none` and moves the heavy package work into `preseed/late_command` rather than leaving it in `pkgsel`. That instinct is correct for exactly the reason in the section above: `pkgsel` is all-or-nothing and reports nothing useful when it fails. This template reaches the same conclusion and puts the work in a Packer provisioner instead, where a failure names itself, the code is linted and tested, and a retry does not mean reinstalling.

**What it does not do is make the install more reliable.** Both apt commands in its `late_command` end in `|| true`, so a failed package fetch produces an install that reports success. Its mirror is `http.kali.org`, in the preseed and again in the `sources.list` its `late_command` writes - the same redirector that broke the first build here by handing apt an HTTPS mirror it could not verify. That failure mode is not fixed there, only silenced: the result would be a Kali template with no toolset, no error on the console, and nothing in any log to explain it. For an image that gets cloned repeatedly, a silent partial build is worse than a failed one, because it is discovered later and on a clone.

Two smaller things to be aware of if you borrow from it:

- `pkgsel/include` is set twice, in separate sections. The second assignment overrides the first, so the `kali-linux-core` and `kali-desktop-xfce` named earlier are probably never installed by `pkgsel` at all.
- Its `tasksel` line selects `kde-desktop` while `pkgsel/include` and the `late_command` both ask for `kali-desktop-xfce`.

Read both as evidence about which approaches exist, not as specifications.

## Build

```bash
cd templates/proxmox/kali
ssh-add -l                                            # the seed's key must be loaded
export PKR_VAR_proxmox_api_token_id="packer@pve!templates"
export PKR_VAR_proxmox_api_token_secret="..."
packer init .
packer validate -var-file=../proxmox.pkrvars.hcl .
packer build    -var-file=../proxmox.pkrvars.hcl .
```

Or from the ISO already on the node:

```bash
packer build -var-file=../proxmox.pkrvars.hcl -var 'iso_file=local:iso/kali-linux-2026.2-installer-amd64.iso' .
```

Expect a long build: `kali-linux-default` is large, and `00-update-system.sh` then full-upgrades a rolling release on top of it. The install itself is the shorter half, so most of the wait happens after Packer connects; `ssh_timeout` is 60m to cover the installer side with room to spare.

| Symptom | Cause | Fix |
| --- | --- | --- |
| The installer's menu starts by itself before anything is typed | GRUB's timeout beat `boot_wait` | lower `boot_wait` |
| `c` lands on the firmware splash | OVMF still posting | `-var 'boot_wait=20s'` |
| d-i stops at a question | an answer the preseed does not carry | read the question on the console; add the `d-i` line |
| "Waiting for SSH" with nothing reaching the VM | the guest agent is not up, or the role lacks `VM.GuestAgent.Audit` | `-var 'ssh_host=<VM IP>'` |

## Clone

Through [`deploy/`](../../../deploy/README.md), starting from [`deploy/kali.tfvars.example`](../../../deploy/kali.tfvars.example):

```bash
cd deploy
cp kali.tfvars.example kali.tfvars
export PROXMOX_VE_API_TOKEN='automation@pve!deploy=xxxxxxxx-...'
export TF_VAR_password='...'
tofu apply -var-file=kali.tfvars
```

Three settings differ from a server clone, and each one bites if it is missed:

- **`disk_size` must be at least 50.** The template's disk is 50G and Proxmox can grow a cloned disk but never shrink one, so the module's default of 32 fails the apply outright.
- **`TF_VAR_password` is required**, not optional. The image runs Xfce, and a display manager has no key login; cloud-init locks the account's password unless one is supplied, so a clone without it cannot be logged into at the console at all.
- **Leave `provisioning_steps` empty.** The `02`/`03` scripts are Ubuntu's and `ubuntu-context.sh` refuses to run elsewhere, which is correct - Kali's tooling comes from its own metapackages, in the image.

## Verify before pushing

```bash
../../../scripts/check-templates.sh proxmox
```
