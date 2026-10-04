# Ubuntu Server 24.04 - VMware template

Ubuntu Server 24.04 LTS for VMware Workstation, installed by the autoinstall seed in `http/` and provisioned at build time. Requirements and the build are in [README.md](../README.md).

Written with [ynlamy/packer-ubuntuserver24_04](https://github.com/ynlamy/packer-ubuntuserver24_04) as a reference for the `vmware-iso` settings.

| | |
| --- | --- |
| Result | a VM in `output/`, named `ubuntu-24.04-server` |
| ISO | `ubuntu-24.04.5-live-server-amd64.iso`, checked against `releases.ubuntu.com/noble/SHA256SUMS` |
| `cpus` / `memory` / `disk_size` | 2 / 2048 / 30 GB |
| Provisioning | `00-update-system.sh`, then the whole `scripts/ubuntu/` tree staged for `02-provision-system.sh`, then `01-cleanup-system.sh` last |

A fat image: everything is baked in at build time, the opposite of the thin [Proxmox template](../../proxmox/ubuntu-24.04-server/README.md). cloud-init stays pinned, and the SSH host keys are kept, so treat a VM built from it as one machine, not an image to clone - see [SECURITY.md](../../../SECURITY.md).
