# Windows Server 2025 - VMware template

Windows Server 2025 Standard with the Desktop Experience for VMware Workstation, packaged as a Vagrant box. Requirements, the build and Vagrant are in [README.md](../README.md).

> **Status: the build chain is new and not yet built on VMware.** It now runs the same chain as the [Proxmox Windows templates](../../proxmox/WINDOWS.md#the-build).

| | |
| --- | --- |
| Result | `output/win2025_gui.box`, about 17 GB |
| ISO | `26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso`, from `C:/ISO/windows/` when present; SHA-256 `d0ef4502e350e3c6c53c15b1b3020d38a5ded011bf04998e950720ac8579b23d` |
| `cpus` / `memory` / `disk_size` | 4 / 8192 / 60 GB, set in `win-srv-2025.auto.pkrvars.hcl` |
| Build login | `Administrator`, `ssh_password` - the answer files in `config/` set it |

The build installs from `config/autounattend.xml` on a floppy, adds VMware Tools, then runs the Proxmox chain: `09_system_settings.ps1`, the `rgl/windows-update` loop, `10_wait_for_servicing.ps1`, then `03_cleanup.ps1` and `12_sysprep.ps1` with `config/unattend.xml`. There is no cloudbase-init here, which `12_sysprep.ps1` is told with `PACKERTRON_CLOUDBASE_INIT=false`. The shutdown command, [`packer_shutdown.bat`](../../../scripts/windows/packer_shutdown.bat), blocks inbound SSH and shuts the generalized image down; on the box's first boot, `04_startup.ps1` opens SSH again once that boot has finished.

The [`Vagrantfile`](Vagrantfile) defines one machine, `win2025srv01` (2 vCPUs, 4 GB, NAT), runs [`install_utils.ps1`](../../../scripts/windows/install_utils.ps1) on it - Chocolatey, its utilities and UniGetUI - and renames it.
