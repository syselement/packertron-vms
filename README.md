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

Check what is missing, and install it, with the scripts in `scripts/`. Both
report by default and change nothing until you ask them to install:

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

The repository's own checks are Bash and need `cloud-init`, which has no
Windows build - so on Windows run them under WSL with the Linux script. VMware
Workstation and the Vagrant VMware plugin stay manual: the download needs a
Broadcom account, and the plugin has to be installed as the user who runs
Vagrant.

### System Requirements

- **Windows 10/11** or **Linux**
- **VMware Workstation Pro** for the VMware templates, or a **Proxmox VE** node
  for the Proxmox ones

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
│   │   ├── ubuntu-24.04-server/
│   │   ├── kali/                         stub, does not build yet
│   │   └── win-11/                       unrepaired, excluded from CI
│   └── vmware/                      <- kept working alongside
│       ├── ubuntu-24.04-desktop/   ubuntu-26.04-desktop/
│       ├── ubuntu-24.04-server/    ubuntu-26.04-server/
│       └── win-srv-2025/
├── scripts/             provisioners, shared by every template
│   ├── ubuntu/              Bash chain, lib/, autoinstall seeds, bats tests
│   ├── windows/             PowerShell and batch provisioners
│   ├── check-templates.sh   run the CI checks locally
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
| API token, SSH password | environment, `PKR_VAR_*` | never |
| Node name, storage pools, bridge | `templates/proxmox/proxmox.pkrvars.hcl` | no, only the `.example` |
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

- On the Proxmox node, create an API token for a user that may create VMs - `Datacenter -> Permissions -> API Tokens`.
- Give it `PVE.Admin` on `/`, or at minimum `VM.Allocate`, `VM.Config.*`, `VM.Monitor`, `VM.PowerMgmt`, `Datastore.Allocate` and `Datastore.AllocateSpace` on the storages involved.
- Leave *Privilege Separation* unticked, or the token inherits nothing.

Then, in the shell you build from - these never touch the filesystem:

```bash
export PKR_VAR_proxmox_api_token_id="packer@pve!templates"
export PKR_VAR_proxmox_api_token_secret="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export PKR_VAR_ssh_password="the password in the autoinstall seed"
```

Build:

```bash
cd templates/proxmox/ubuntu-24.04-server
packer init .
packer build -var-file=../proxmox.pkrvars.hcl .
```

- The result is a Proxmox **template** (`vm_id` 80024 by default) that is thin on purpose: base OS, `qemu-guest-agent`, and cloud-init left able to run again.
- Per-VM provisioning happens at first boot on each clone, not in the image.

Before pushing any template change:

```bash
scripts/check-templates.sh proxmox
```

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
    - [ ] Templates from the official Ubuntu cloud image, plus an ISO + autoinstall path for parity with the bare-metal install
    - [ ] Provisioning at first boot per VM, through the existing `packertron-firstboot` service, so templates stay thin and every VM picks up current scripts
    - [ ] Credentials from the environment (`PROXMOX_VE_*` / `PKR_VAR_proxmox_api_token_*`) - never committed, never KeePass
- [ ] OpenTofu layer to create and manage the VMs cloned from those templates
- [ ] O.S Packer builds:
    - [ ] Win11
    - [x] Ubuntu Server (24.04 and 26.04)
    - [x] Ubuntu Desktop (24.04 and 26.04)
    - [ ] Kali Linux - template validates, but still needs `http/kali.preseed`
- [ ] Integration with **Ansible** for advanced provisioning

---

🚀 **Happy Virtualizing with [packertron-vms](#packertron-vms)!**