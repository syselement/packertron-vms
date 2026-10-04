# Ubuntu Desktop 24.04 - VMware template

Ubuntu Desktop 24.04 LTS for VMware Workstation, installed by the autoinstall seed in `http/` and packaged as a Vagrant box. Requirements, the build and Vagrant are in [README.md](../README.md).

| | |
| --- | --- |
| Result | `output/ubuntu-24.04-x64-desktop-template-vmware.box`, about 5 GB, in about 15 minutes |
| ISO | `ubuntu-24.04.5.1-desktop-amd64.iso`, from `C:/ISO/linux/` when present, else downloaded; checked against `releases.ubuntu.com/noble/SHA256SUMS` |
| `cpus` / `memory` / `disk_size` | 4 / 8192 / 60 GB, set in `ubuntu-24.04-desktop.auto.pkrvars.hcl` |
| Provisioning at build time | `00-update-system.sh` and `01-cleanup-system.sh` |

The [`Vagrantfile`](Vagrantfile) defines two machines from the box, with the same hardware - 4 vCPUs, 16 GB, NAT:

| Machine | Gets |
| --- | --- |
| `base` | the box as built |
| `provisioned` | `02-provision-system.sh` then `03-customize-system.sh`, on its first `vagrant up` - the workstation layer |
