# packertron-vms

> **Automated VM deployment with Packer, Vagrant, Ansible across hypervisors**

[![syselement - packertron-vms](https://img.shields.io/static/v1?label=syselement&message=packertron-vms&color=blue&logo=github)](https://github.com/syselement/packertron-vms) [![stars - packertron-vms](https://img.shields.io/github/stars/syselement/packertron-vms?style=social)](https://github.com/syselement/packertron-vms) [![forks - packertron-vms](https://img.shields.io/github/forks/syselement/packertron-vms?style=social)](https://github.com/syselement/packertron-vms) [![License](https://img.shields.io/badge/License-MIT-orange)](#-license "Go to license section")

[![Package - Packer](https://img.shields.io/badge/Packer->=1.11.2-brightgreen?logo=packer&logoColor=acqua)](https://developer.hashicorp.com/packer "Go to Packer homepage") [![Package - Vagrant](https://img.shields.io/badge/Vagrant->=2.4.3-brightgreen?logo=vagrant&logoColor=blue)](https://developer.hashicorp.com/vagrant "Go to Vagrant homepage") [![Package - VMware Workstation Pro](https://img.shields.io/badge/VMwareWorkstationPro->17.x-brightgreen?logo=vmware&logoColor=white)](https://www.vmware.com/products/desktop-hypervisor/workstation-and-fusion "Go to VMware Workstation homepage")

> [!WARNING]
>
> 🚧 **Project instructions and commands under review** 🚧  
>
> The setup and deployment instructions in this README file are currently being tested and refined.
>
> Expect updates and improvements as I validate each step.  

`packertron-vms` is a **collection of templates for automated VM deployment**, designed for home lab environments and testing setups. Using **Packer and Vagrant**, it simplifies the creation, provisioning, and management of virtual machines. The templates currently support **VMware Workstation** (future plans include **Ansible** automation and expanding hypervisor support like **VirtualBox**, **Proxmox**, etc).

---

## 📖 Table of Contents

- [packertron-vms](#packertron-vms)
    - [📖 Table of Contents](#-table-of-contents)
    - [🚀 Features](#-features)
    - [🛠 Requirements](#-requirements)
        - [System Requirements](#system-requirements)
        - [Software Dependencies](#software-dependencies)
    - [🔧 Installation](#-installation)
        - [1️⃣ Install Chocolatey (Windows Users Only)](#1️⃣-install-chocolatey-windows-users-only)
        - [2️⃣ Install Dependencies](#2️⃣-install-dependencies)
        - [3️⃣ Install Vagrant VMware Plugin](#3️⃣-install-vagrant-vmware-plugin)
        - [4️⃣ Clone packertron-vms Repository](#4️⃣-clone-packertron-vms-repository)
    - [📁 Directory Structure](#-directory-structure)
    - [🚀 Build \& Deploy VMs](#-build--deploy-vms)
        - [Build a Proxmox template](#build-a-proxmox-template)
        - [Deploy a VM with OpenTofu](#deploy-a-vm-with-opentofu)
        - [Dedicated Role](#dedicated-role)
            - [CLI](#cli)
            - [UI](#ui)
        - [1️⃣ Open Visual Studio Code](#1️⃣-open-visual-studio-code)
        - [2️⃣ Packer: Initialize \& Build Windows Server 2025](#2️⃣-packer-initialize--build-windows-server-2025)
        - [3️⃣ Deploy VM with Vagrant](#3️⃣-deploy-vm-with-vagrant)
        - [4️⃣ Manage VM Lifecycle](#4️⃣-manage-vm-lifecycle)
    - [🛠 Troubleshooting](#-troubleshooting)
    - [📜 License](#-license)
    - [🤝 Contributing](#-contributing)
    - [🌍 Future Roadmap](#-future-roadmap)

---

## 🚀 Features

- Automated VM builds using **Packer**
- Provisioning with **Vagrant**
- Support for **multiple OS images** (Windows, Ubuntu, Kali Linux, etc)
- Customizable **HCL templates and scripts**
- Hypervisor-agnostic **VM automation**

---

## 🛠 Requirements

Check what is missing, and install it, with the scripts in `scripts/`. Both report by default and change nothing until you ask them to install:

```bash
# Linux (apt): the Proxmox path, and every check CI runs
scripts/install-requirements.sh                    # report
scripts/install-requirements.sh install            # install
scripts/install-requirements.sh install --with-vmware
```

```powershell
# Windows (winget, or Chocolatey as a fallback): the VMware path
powershell -ExecutionPolicy Bypass -File scripts\install-requirements.ps1
powershell -ExecutionPolicy Bypass -File scripts\install-requirements.ps1 -Install
```

The repository's own checks are Bash and need `cloud-init`, which has no Windows build - so on Windows run them under WSL with the Linux script. VMware Workstation and the Vagrant VMware plugin stay manual: the download needs a Broadcom account, and the plugin has to be installed as the user who runs Vagrant.

### System Requirements

- **Windows 10/11** or **Linux**
- **VMware Workstation Pro** for the VMware templates, or a **Proxmox VE** node for the Proxmox ones

### Software Dependencies

- [Chocolatey](https://chocolatey.org/) (Windows package manager)
- [VMware Workstation](https://support.broadcom.com/group/ecx/free-downloads)
- [HashiCorp Packer](https://www.packer.io/)
- [HashiCorp Vagrant](https://developer.hashicorp.com/vagrant/install?product_intent=vagrant)
- [Vagrant VMware Utility](https://developer.hashicorp.com/vagrant/docs/providers/vmware/vagrant-vmware-utility)
- [Vagrant VMware Plugin](https://developer.hashicorp.com/vagrant/docs/providers/vmware/installation)
- [Visual Studio Code](https://code.visualstudio.com/)

---

## 🔧 Installation

### 1️⃣ Install Chocolatey (Windows Users Only)

Open **PowerShell as Administrator** and run:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

Verify installation:

```powershell
choco -?
```

### 2️⃣ Install Dependencies

```powershell
choco install packer vagrant jq vscode -y

# choco install vmwareworkstation
# ^^ may not work anymore since vmwareworkstation URL is broken
# install with official installer - read bellow

# To upgrade
choco upgrade all
```

The latest **VMware Workstation Pro** version installer can be found at the [official Broadcom link](https://support.broadcom.com/group/ecx/productdownloads?subfamily=VMware%20Workstation%20Pro&freeDownloads=true) (login necessary for free download).

- More info at my wiki about the tool -> [vmware-workstation.md · syselement/blog](https://github.com/syselement/blog/blob/main/home-lab/hypervisors/vmware/vmware-workstation.md)

### 3️⃣ Install Vagrant VMware Plugins

**Requirements**

- [Install Vagrant VMware Utility](https://developer.hashicorp.com/vagrant/install/vmware) using the binary (for Win).

> If the installer cannot find VMware Workstation, in case of VMware Workstation Pro 26H1 (64bit) - [issue](https://github.com/hashicorp/vagrant-vmware-desktop/issues/177) - proceed by creating the registry keys the installer and its service is looking for.
>
> Run this in **PowerShell as Administrator**:
>
> ```powershell
> $src = "HKLM:\SOFTWARE\VMware, Inc.\VMware Workstation"
> $dstRoot = "HKLM:\SOFTWARE\WOW6432Node\VMware, Inc."
> $dst = "$dstRoot\VMware Workstation"
> 
> New-Item -Path $dstRoot -Force | Out-Null
> New-Item -Path $dst -Force | Out-Null
> 
> Set-ItemProperty -Path $dstRoot -Name "Core" -Value "VMware Workstation"
> 
> $props = Get-ItemProperty -Path $src
> 
> foreach ($name in "InstallPath", "InstallPath64", "ProductCode", "ProductVersion", "Version") {
>     if ($props.$name) {
>         Set-ItemProperty -Path $dst -Name $name -Value $props.$name
>     }
> }
> 
> # fallback if InstallPath64 does not exist in 26H1
> if (-not (Get-ItemProperty -Path $dst -Name InstallPath64 -ErrorAction SilentlyContinue)) {
>     Set-ItemProperty -Path $dst -Name "InstallPath64" -Value $props.InstallPath
> }
> ```
>
> Then rerun the Vagrant VMware Utility MSI as admin.
>
> After install, check if the service is running:
>
> ```powershell
> Get-Service *vagrant*vmware*
> Get-Service vagrant-vmware-utility
> ```

- Install the `vagrant-vmware-desktop` plugin

```powershell
vagrant plugin install vagrant-vmware-desktop
```

### 4️⃣ Clone packertron-vms Repository

```bash
git clone https://github.com/syselement/packertron-vms.git
cd packertron-vms
```

---

## 📁 Directory Structure

```
packertron-vms/
├── templates/           one directory per template, grouped by hypervisor
│   ├── proxmox/                     <- the primary target
│   │   ├── proxmox.pkrvars.hcl.example   node settings, shared by all of them
│   │   ├── seal-for-clone.sh             strips per-machine state before cloning
│   │   ├── ubuntu-24.04-server/    ubuntu-26.04-server/
│   │   ├── ubuntu-26.04-desktop/
│   │   ├── kali/                         stub, does not build yet
│   │   └── win-11/                       unrepaired, excluded from CI
│   └── vmware/                      <- kept working alongside
│       ├── ubuntu-24.04-desktop/   ubuntu-26.04-desktop/
│       ├── ubuntu-24.04-server/    ubuntu-26.04-server/
│       └── win-srv-2025/
├── deploy/              OpenTofu: clone one template into a running VM
├── scripts/             provisioners, shared by every template
│   ├── ubuntu/              Bash chain, lib/, autoinstall seeds, bats tests
│   │   └── firstboot/       the per-VM provisioning runner, embedded into seeds
│   ├── windows/             PowerShell and batch provisioners
│   ├── check-templates.sh   run the CI checks locally
│   ├── sync-firstboot.sh    re-embed firstboot/ into every seed that uses it
│   └── install-requirements.{sh,ps1}   host tooling, Linux and Windows
├── .github/workflows/   CI
├── AGENTS.md            repository standards: file headers, Bash, safety, review
├── SECURITY.md          credential model - read before pointing this at a network
└── CHANGELOG.md  LICENSE  README.md  version.yaml
```

Two levels, `<hypervisor>/<os>`, and that pair is the template's name everywhere: in the CI matrix, in `check-templates.sh` output, and on disk.

Inside a template directory:

| Path | Holds |
| --- | --- |
| `<os>/<os>.pkr.hcl` | the builder, variables and build block |
| `<os>/<os>.auto.pkrvars.hcl` | non-secret defaults, auto-loaded (ISO URL, sizing) |
| `<os>/http/` | the cloud-init seed served to the installer |
| `<os>/config/` | Windows answer files |
| `<os>/README.md` | how to build that one, and whether it currently can be |

Templates reach the shared provisioners through `${path.root}/../../../scripts/`.

### Where a value goes

| Kind | Where | Committed |
| --- | --- | --- |
| API token, SSH password | environment, `PKR_VAR_*` and `PROXMOX_VE_API_TOKEN` | never |
| Node name, storage pools, bridge | `templates/proxmox/proxmox.pkrvars.hcl` | no, only the `.example` |
| Which template to clone, VM sizing | `deploy/deploy.tfvars` | no, only the `.example` |
| ISO URL, checksum, sizing | the template's own `.pkr.hcl` / `.auto.pkrvars.hcl` | yes |

One node file rather than one per template, so adding a template inherits the node settings instead of copying them. See [SECURITY.md](SECURITY.md).

Build output, `packer_cache/`, `.vagrant/` and `tmp/` are generated or scratch and are excluded by `.gitignore`.

---

## 🚀 Build & Deploy VMs

### Build a Proxmox template

One-time setup, on the machine that runs Packer:

```bash
cd templates/proxmox
cp proxmox.pkrvars.hcl.example proxmox.pkrvars.hcl   # gitignored, never committed
$EDITOR proxmox.pkrvars.hcl                          # node name, storage pools, bridge
```

On the Proxmox node, create the token described in [Dedicated Role](#dedicated-role) below. Then, in the shell you build from - these never touch the filesystem:

```bash
export PKR_VAR_proxmox_api_token_id="automation@pve!deploy"
export PKR_VAR_proxmox_api_token_secret="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

Build:

```bash
cd templates/proxmox/ubuntu-24.04-server   # or ubuntu-26.04-server, ubuntu-26.04-desktop
packer init .
packer build -var-file=../proxmox.pkrvars.hcl .
```

| Template | `vm_id` | Installs |
| --- | --- | --- |
| `ubuntu-24.04-server` | 80024 | Ubuntu Server 24.04 LTS |
| `ubuntu-26.04-server` | 80026 | Ubuntu Server 26.04 LTS |
| `ubuntu-26.04-desktop` | 80126 | Ubuntu Desktop 26.04 LTS |

Each result is a Proxmox **template** that is thin on purpose: base OS, `qemu-guest-agent`, and cloud-init left able to run again. None of them bakes in the tooling from `02-provision-system.sh` or `03-customize-system.sh`.

That is what lets one template serve both cases. A clone gets the tooling only if it asks for it, at first boot, from a fresh checkout - so a VM created a year from now runs the current scripts rather than whatever was current when its template was built. See [Deploy a VM](#deploy-a-vm-with-opentofu).

Before pushing any template change:

```bash
scripts/check-templates.sh proxmox
```

### Deploy a VM with OpenTofu

[`deploy/`](deploy/README.md) clones one template into a running VM. It is deliberately small - one VM, no composition, no remote state - because fleet-wide homelab infrastructure belongs in its own repository, which can consume this module by git ref.

```bash
cd deploy
cp deploy.tfvars.example deploy.tfvars   # gitignored, never committed
$EDITOR deploy.tfvars

export PROXMOX_VE_API_TOKEN='automation@pve!deploy=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
tofu init
tofu apply -var-file=deploy.tfvars
```

Provisioning is opt-in, through one variable:

| `provisioning_steps` | The clone gets |
| --- | --- |
| `""` (default) | nothing. It is exactly the template |
| `"02"` | baseline and developer tooling |
| `"02,03"` | the full toolchain, GNOME preferences and shell configuration |

So a throwaway server and a workstation built to match the bare-metal PC come from the same template and differ by one line of configuration. The steps run in the background well after `tofu apply` returns; `deploy/README.md` covers following them.

**How the request reaches the clone.** Proxmox generates the clone's cloud-init user-data itself (hostname, account, keys, network) and offers exactly one way to add to it: `cicustom`, which takes a file from a datastore with the **snippets** content type. So when `provisioning_steps` is set, OpenTofu renders a small cloud-config - `git`, the first-boot conf, stub and unit - uploads it to the node as a snippet, and attaches it as **vendor-data**. vendor-data is merged alongside what Proxmox generated; user-data would replace it, and the clone would come up with no account. A clone that asks for nothing gets no snippet at all.

Two one-time things on the node follow from that. Proxmox has no API for writing snippets, so the provider uploads over SSH as root - which is why `providers.tf` carries an `ssh` block. And `local` does not accept snippets by default:

```bash
# on the node, once - --content replaces the list, so keep what was there
pvesm set local --content backup,iso,vztmpl,snippets
```

### Dedicated Role

Create a dedicated `automation@pve` user, give it a restricted role, and create a token with Privilege Separation unticked. Do not use a root token.

- [Roles](https://pve.proxmox.com/pve-docs/chapter-pveum.html#pveum_roles)
- [Privileges](https://pve.proxmox.com/pve-docs/chapter-pveum.html#_privileges)

For the restricted role use these privileges for template builds:

| Category | Privileges to select |
| --- | --- |
| Datastore | `Datastore.Allocate`, `Datastore.AllocateSpace`, `Datastore.AllocateTemplate`, `Datastore.Audit` |
| VM | `SDN.Use`, `VM.Allocate`, `VM.Audit`, `VM.Clone`, `VM.Config.CDROM`, `VM.Config.CPU`, `VM.Config.Cloudinit`, `VM.Config.Disk`, `VM.Config.HWType`, `VM.Config.Memory`, `VM.Config.Network`, `VM.Config.Options`, `VM.Console`, `VM.PowerMgmt`, `VM.GuestAgent.Audit` |

This is a practical starting role, not a guaranteed exact minimum. It covers the normal Packer ISO-build operations and the [`deploy/`](deploy/README.md) OpenTofu workflow of cloning a template, configuring its hardware and cloud-init, and starting or stopping it.

`VM.GuestAgent.Audit` is the one that is easy to miss. Packer asks the guest agent for the VM's address, and without it the lookup returns nothing: the build sits on "Waiting for SSH" for the full timeout without a single connection ever reaching the VM. On PVE 8 it replaced the older `VM.Monitor`, which no longer exists.

`iso_download_pve` would additionally need `Sys.AccessNetwork`, which is why the templates leave it off and let Packer do the download - see [templates/proxmox/ubuntu-24.04-server/README.md](templates/proxmox/ubuntu-24.04-server/README.md).

Asking a clone to provision itself needs no further API privilege either: Proxmox has no API for writing snippets, so the provider uploads that one file over SSH instead. What it does need is a storage with the **snippets** content type enabled.

The same role covers the intended workflow:

```
Packer
  → create Ubuntu VM
  → configure hardware
  → attach ISO
  → install and provision
  → convert to template

OpenTofu
  → clone template
  → configure CPU/RAM/disk/network
  → configure cloud-init
  → start/stop VM
```

If you later add snapshots, backups, migration, replication, PCI passthrough, or other advanced operations, you may need additional privileges. Do not add those now just because they exist.

If a build returns `403`, find the missing privilege rather than switching the role to `Administrator`.

#### CLI

Run on the Proxmox node as root:

```bash
pveum user add automation@pve --comment "IAC deployment automation"
# no password is ok

pveum role add IACDeploy --privs "Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit SDN.Use VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Console VM.PowerMgmt VM.GuestAgent.Audit"

pveum acl modify / -user automation@pve -role IACDeploy

pveum user token add automation@pve deploy -privsep 0

pveum user permissions automation@pve
```

Save the secret printed by `pveum user token add` - it is shown once and never again. The token ID is:

```
automation@pve!deploy
```

A password is only needed for interactive login, which this user does not do:

```bash
# pveum passwd automation@pve
```

#### UI

1. `Datacenter → Permissions → Users → Add` - create `automation` in the `pve` realm.
2. `Datacenter → Permissions → Roles → Create` - create `IACDeploy` with the privileges in the table above.
3. `Datacenter → Permissions → Add → User Permission` - assign `IACDeploy` to `automation@pve` at `/` for a single-node setup.
4. `Datacenter → Permissions → API Tokens → Add` - User `automation@pve`, Token ID `deploy`, **Privilege Separation unticked**. Ticked, the token inherits nothing and every call is denied.
5. Copy the token secret immediately.

### 1️⃣ Open Visual Studio Code

```powershell
cd packertron-vms
code .
```

### 2️⃣ Packer: Initialize & Build Windows Server 2025

Setup the necessary variables inside the `templates\vmware\win-srv-2025\win-srv-2025.auto.pkrvars.hcl` file, adjusting them accordingly based on your ISO folder, name and checksum.

Open VMware Workstation Pro (before running Packer build).

Proceed with Packer initialize and build.

```powershell
cd templates/vmware/win-srv-2025
packer init .
packer build .
```

### 3️⃣ Deploy VM with Vagrant

```powershell
cd templates/vmware/win-srv-2025
vagrant up
```

### 4️⃣ Manage VM Lifecycle

```powershell
# Shut down VM
vagrant halt

# Restart VM
vagrant up

# Destroy VM
vagrant destroy -f
```

---

## 🛠 Troubleshooting

- **VMware Workstation Not Detected?** Ensure it is installed and running.
- ISO Checksum Mismatch?

   Run:

  ```powershell
  Get-FileHash C:\ISO\windows\your_iso.iso
  ```
- Vagrant Plugin Issues?

   Reinstall:

  ```powershell
  vagrant plugin repair
  ```

---

## 📜 License

Released under [MIT](/LICENSE) by [@syselement](https://github.com/syselement).

## 🤝 Contributing

Pull requests and improvements are welcome! Ensure your code follows the repo’s standards.

## 🌍 Future Roadmap

- [ ] Proxmox support
    - [x] ISO + autoinstall templates, for parity with the bare-metal install
    - [ ] Templates from the official Ubuntu cloud image
    - [x] Provisioning at first boot per VM, through the `packertron-firstboot` service, so templates stay thin and every VM picks up current scripts
    - [x] Credentials from the environment (`PROXMOX_VE_*` / `PKR_VAR_proxmox_api_token_*`) - never committed, never KeePass
- [x] OpenTofu layer to create the VMs cloned from those templates, in [`deploy/`](deploy/README.md)
- [ ] Proxmox LXC containers - out of reach for Packer, whose Proxmox plugin builds only `iso` and `clone`, so they would come from OpenTofu and an upstream LXC template
- [ ] O.S Packer builds:
    - [ ] Win11
    - [x] Ubuntu Server (24.04 and 26.04)
    - [x] Ubuntu Desktop (24.04 and 26.04)
    - [ ] Kali Linux - template validates, but still needs `http/kali.preseed`
- [ ] Integration with **Ansible** for advanced provisioning

---

🚀 **Happy Virtualizing with [packertron-vms](#packertron-vms)!**