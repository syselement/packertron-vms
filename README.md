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

Ensure you have the following installed before proceeding:

### System Requirements

- **Windows 10/11** or **Linux**
- **VMware Workstation Pro** (or Proxmox in future support)

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

- **Requirement**: [Install Vagrant VMware Utility](https://developer.hashicorp.com/vagrant/install/vmware) using the binary (for Win).
- Install `vagrant-vmware-desktop` plugin

```powershell
# choco install vagrant-vmware-utility -y
# ^^ may not work anymore since vmwareworkstation dependency URL is broken
# ^^ use binary

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
├── win-srv-2025/
│   ├── config/          # Configuration files (autounattend.xml, unattend.xml)
│   ├── output/          # VM build output
│   ├── scripts/         # Automation scripts (Powershell, Batch)
│   ├── vagrant/         # Vagrant Automation scripts (Powershell, Batch)
│   ├── README.md        # Readme file
│   ├── Vagrantfile      # Vagrant configuration
│   ├── winserver2025.pkr.hcl      # Packer HCL template
│   ├── winserver2025.pkrvars.hcl  # Packer variables
└── .gitignore           # Ignore unnecessary files (ISO, temp builds)
```

---

## 🚀 Build & Deploy VMs

### 1️⃣ Open Visual Studio Code

```powershell
cd packertron-vms
code .
```

### 2️⃣ Packer: Initialize & Build Windows Server 2025

Setup the necessary variables inside the `win-srv-2025\winserver2025.pkrvars.hcl` file, adjusting them accordingly based on your ISO folder, name and checksum.

Open VMware Workstation Pro (before running Packer build).

Proceed with Packer initialize and build.

```powershell
cd win-srv-2025
packer init .
packer build .
```

### 3️⃣ Deploy VM with Vagrant

```powershell
cd win-srv-2025
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
- [ ] O.S Packer builds:
    - [ ] Win11
    - [ ] Ubuntu Server
    - [x] Ubuntu Desktop
    - [ ] Kali Linux
- [ ] Integration with **Ansible** for advanced provisioning

---

🚀 **Happy Virtualizing with [packertron-vms](#packertron-vms)!**