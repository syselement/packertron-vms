# Ubuntu Server 24.04 - Proxmox template

Ubuntu Server 24.04 LTS from the official ISO, installed by the autoinstall seed in `http/`. Shared Linux behaviour is in [LINUX.md](../LINUX.md); staging and building in [README.md](../README.md).

> **Status: built and verified on a real node** (Proxmox VE, q35/OVMF, 24.04.4, ~5 minutes). Two full clones were checked: SSH host keys, machine-id and the systemd random seed all differ; hostname, `/etc/hosts`, netplan and DHCP are correct on each; cloud-init reports `done` from `DataSourceNoCloud`.

| | |
| --- | --- |
| `vm_id` / `template_name` | 80024 / `ubuntu-24.04-server-template` |
| `iso_file` | `local:iso/ubuntu-24.04.5-live-server-amd64.iso` |
| Checksum | `SHA256SUMS` in `releases.ubuntu.com/noble`, which follows each point release |
| `cores` / `memory` / `disk_size` | 2 / 2048 / 30G |
| `ssh_timeout` | 30m |

---
