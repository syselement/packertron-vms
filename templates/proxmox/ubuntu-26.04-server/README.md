# Ubuntu Server 26.04 - Proxmox template

Ubuntu Server 26.04 LTS from the official ISO, installed by the autoinstall seed in `http/`. Shared Linux behaviour is in [LINUX.md](../LINUX.md); staging and building in [README.md](../README.md).

> **Status: built and cloned on a real node** (Proxmox VE, q35/OVMF, 26.04.1, ~7 minutes; cloned through [`deploy/`](../../../deploy/README.md)).

| | |
| --- | --- |
| `vm_id` / `template_name` | 80026 / `ubuntu-26.04-server-template` |
| `iso_file` | `local:iso/ubuntu-26.04.1-live-server-amd64.iso` |
| Checksum | `SHA256SUMS` in `releases.ubuntu.com/resolute`, which follows each point release |
| `cores` / `memory` / `disk_size` | 2 / 2048 / 30G |
| `ssh_timeout` | 30m |

The same template as [24.04](../ubuntu-24.04-server/README.md), with the release changed.
