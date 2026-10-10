# Ubuntu Desktop 26.04 - Proxmox template

Ubuntu Desktop 26.04 LTS from the official desktop ISO, installed by the autoinstall seed in `http/`. Shared Linux behaviour is in [LINUX.md](../LINUX.md); staging and building in [README.md](../README.md).

> **Status: built and cloned on a real node** (Proxmox VE, q35/OVMF, 26.04.1, ~12 minutes). Cloned through [`deploy/`](../../../deploy/README.md) as a workstation with `provisioning_steps = "02,03"`, which ran to completion on first boot.

| | |
| --- | --- |
| `vm_id` / `template_name` | 80126 / `ubuntu-26.04-desktop-template` |
| `iso_file` | `local:iso/ubuntu-26.04.1-desktop-amd64.iso` |
| Checksum | `SHA256SUMS` in `releases.ubuntu.com/resolute`, which follows each point release |
| Install source | `ubuntu-desktop` |
| `cores` / `memory` / `disk_size` | 4 / 8192 / 64G |
| Display | `qxl`, 32MB - the 16MB default boots GNOME and little more |
| `ssh_timeout` | 60m - the desktop install fetches language packs and takes far longer than the server one |

**Still thin.** It installs the desktop base and the guest agent, nothing else, so one template serves a plain desktop VM and a full workstation: the workstation asks for `02,03` when it is cloned. A clone needs a console password - see [`deploy/`](../../../deploy/README.md#console-access).

---
