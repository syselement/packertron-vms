# Kali Linux - Proxmox template

Kali Linux from the official installer ISO, installed by the debian-installer preseed in `http/`. Shared Linux behaviour is in [LINUX.md](../LINUX.md); staging and building in [README.md](../README.md). This page covers what Kali does differently.

> **Status: built and cloned on a real node** (Proxmox VE, q35/OVMF, Kali 2026.2, ~10 minutes; cloned through [`deploy/`](../../../deploy/README.md) with `kali.tfvars.example`).

Adapted from [mttaggart/seclab](https://github.com/mttaggart/seclab) (`Packer/kali/config.pkr.hcl`), without its KeePass and CA-certificate provisioners: credentials come from the environment, and the build runs the same `00` -> `01` -> seal chain as the Ubuntu templates.

| | Ubuntu | Kali |
| --- | --- | --- |
| `vm_id` / `template_name` | 80024, 80026, 80126 | 80200 / `kali-template` |
| `iso_file` | | `local:iso/kali-linux-2026.2-installer-amd64.iso`, checked against `cdimage.kali.org/kali-2026.2/SHA256SUMS` |
| Installer and seed | subiquity, `http/user-data` | debian-installer, `http/kali.preseed` |
| Boot | `<esc>`, then edit the GRUB entry | `c` for GRUB's console, then start the kernel by hand |
| Seed check | `cloud-init schema` | `debconf-set-selections --checkonly`, plus a type check |
| Guest agent | first-boot `user-data:` | `pkgsel/include`, from the network mirror |
| SSH | enabled by subiquity | installed **disabled**; `late_command` enables it |
| cloud-init during the build | pinned by subiquity | switched off by `/etc/cloud/cloud-init.disabled`; the seal removes it |
| Packages | base | `kali-linux-default` and `kali-desktop-xfce` |
| `cores` / `memory` / `disk_size` | 2-4 / 2048-8192 / 30-64G | 4 / 4096 / 50G |
| `ssh_timeout` | 30-60m | 60m - `kali-linux-default` is large, and `00` full-upgrades a rolling release on top of it |

`00` and `01` run unchanged: both are distro-agnostic on this path.

## Decisions

**cloud-init is off for the build.** Packer attaches the cloud-init drive only once the VM is a template, so on the build VM cloud-init would run its first-boot pass with nothing from Proxmox to read. Ubuntu pins it to the `None` datasource; Kali's installer does nothing equivalent, and what Debian's cloud-init would do instead - probe other datasources, or create a `debian` account - is not something a template should depend on. `late_command` writes `/etc/cloud/cloud-init.disabled`; the seal removes it and fails the build if it survived.

**The mirror is `kali.download`, not `http.kali.org`.** The redirector hands some requests to HTTPS mirrors, and during the install `/target` has no `ca-certificates`, so apt fails with `certificate verify failed` and the install stops at "Select and install software".

**The upgrade runs in `00-update-system.sh`, not `pkgsel/upgrade`.** Kali is rolling, so the ISO is only a snapshot. `pkgsel` is all-or-nothing and reports only "Installation step failed"; the same work in a provisioner names its failure in Packer's output and can be retried without reinstalling.

**SSH is enabled explicitly.** Kali installs `openssh-server` disabled, so the machine would boot with port 22 closed. `late_command` runs `systemctl enable ssh`. The unit is `ssh.service` on Kali: `systemctl status sshd` reports "could not be found" either way.

**The installer's cdrom fstab line goes.** debian-installer writes `/dev/sr0 /media/cdrom0`, and on a clone `/dev/sr0` is the cloud-init drive, which a desktop clone then shows as a mounted "cdrom0". The udisks rule cannot hide an fstab entry, so the seal removes the line. A template built before that change still carries it; rebuild it.

`late_command` also authorizes the key from `ssh_authorized_key`, sets `NOPASSWD` sudo (checked with `visudo -c`) and `PasswordAuthentication no`. Drop `kali-desktop-xfce` from `pkgsel/include` for a headless template.

## Prior art

- **[badsectorlabs/ludus](https://gitlab.com/badsectorlabs/ludus/-/blob/main/ludus-server/packer/kali/http/kali-preseed.cfg)** reached the same mirror and `pkgsel/upgrade select none` independently, and is where `systemctl enable ssh` came from. It installs a minimal system and provisions with Ansible, partitions without LVM, and hardcodes `/dev/vda`; three of its `late_command` steps lack `in-target` and land in the installer's ramdisk.
- **[blink-zero/kali-2024.1-preseed](https://github.com/blink-zero/kali-2024.1-preseed)** also moves the package work out of `pkgsel`, but ends its apt commands in `|| true` and keeps the `http.kali.org` redirector, so a failed fetch produces an install that reports success with no toolset. It also sets `pkgsel/include` twice, the second overriding the first.

## Cloning

Use [`deploy/kali.tfvars.example`](../../../deploy/kali.tfvars.example):

- `disk_size` of at least 50, the template's own;
- `TF_VAR_password`: Xfce has no key login, so without one the console cannot be logged into;
- `os = "kali"`: `deploy/` then refuses `provisioning_steps`, since the `02`/`03` scripts are Ubuntu's.

| Symptom | Fix |
| --- | --- |
| The installer's menu starts before anything is typed | GRUB's timeout beat `boot_wait`: lower it |
| `c` lands on the firmware splash | OVMF is still posting: `-var 'boot_wait=20s'` |
| d-i stops at a question | the preseed lacks that answer; add its `d-i` line |

## Upstream license

This template adapts code from [mttaggart/seclab](https://github.com/mttaggart/seclab), which is released under the MIT License; its notice is reproduced here as that license requires.

```text
MIT License

Copyright (c) 2021 Michael Taggart

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
