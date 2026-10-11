# Ubuntu Desktop 26.04 - VMware template

Ubuntu Desktop 26.04 LTS for VMware Workstation, installed by the autoinstall seed in `http/` and packaged as a Vagrant box. Requirements, the build and Vagrant are in [README.md](../README.md).

> **Status: unverified.** The 26.04 build stopped on [subiquity bug 2150197](https://bugs.launchpad.net/subiquity/+bug/2150197). The [Proxmox desktop template](../../proxmox/ubuntu-26.04-desktop/README.md) builds from 26.04.1, and this one is to be retested with it.

| | |
| --- | --- |
| Result | `output/ubuntu-26.04-x64-desktop-template-vmware.box`, about 5 GB, in about 15 minutes |
| ISO | `ubuntu-26.04.1-desktop-amd64.iso`, from `C:/ISO/linux/` when present, else downloaded; checked against `releases.ubuntu.com/resolute/SHA256SUMS` |
| `cpus` / `memory` / `disk_size` | 4 / 8192 / 60 GB, set in `ubuntu-26.04-desktop.auto.pkrvars.hcl` |
| Provisioning at build time | `00-update-system.sh` and `01-cleanup-system.sh` |

The [`Vagrantfile`](Vagrantfile) defines two machines from the box, with the same hardware - 4 vCPUs, 16 GB, NAT:

| Machine | Gets |
| --- | --- |
| `base` | the box as built |
| `provisioned` | `02-provision-system.sh` then `03-customize-system.sh`, on its first `vagrant up` - the workstation layer |

---
