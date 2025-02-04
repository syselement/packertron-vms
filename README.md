# packertron-vms

**Automated VM deployment with Packer, Vagrant, Ansible across hypervisors**

> [!WARNING]
> 🚧 **Project instructions and commands under review** 🚧  
> The setup and deployment instructions are currently being tested and refined.  
> Expect updates and improvements as I validate each step.  

`packertron-vms` is a **collection of templates for automated VM deployment**, designed for home lab environments and testing setups. Using **Packer and Vagrant**, it simplifies the creation, provisioning, and management of virtual machines. The templates currently support **VMware Workstation** (with planned enhancements for **Ansible** automation and additional hypervisors like **VirtualBox**, **Proxmox**, and more).

---

## 📖 Table of Contents

- [packertron-vms](#packertron-vms)
  - [📖 Table of Contents](#-table-of-contents)
  - [🚀 Features](#-features)
  - [🛠 Requirements](#-requirements)
    - [**System Requirements**](#system-requirements)
    - [**Software Dependencies**](#software-dependencies)
  - [🔧 Installation](#-installation)
    - [**1️⃣ Install Chocolatey (Windows Users Only)**](#1️⃣-install-chocolatey-windows-users-only)
    - [**2️⃣ Install Dependencies**](#2️⃣-install-dependencies)
    - [**3️⃣ Install Vagrant VMware Plugin**](#3️⃣-install-vagrant-vmware-plugin)
    - [**4️⃣ Clone packertron-vms Repository**](#4️⃣-clone-packertron-vms-repository)
  - [📁 Directory Structure](#-directory-structure)
  - [🚀 Build \& Deploy VMs](#-build--deploy-vms)
    - [**1️⃣ Open Visual Studio Code**](#1️⃣-open-visual-studio-code)
    - [**2️⃣ Packer: Initialize \& Build Windows Server 2025**](#2️⃣-packer-initialize--build-windows-server-2025)
    - [**3️⃣ Deploy VM with Vagrant**](#3️⃣-deploy-vm-with-vagrant)
    - [**4️⃣ Manage VM Lifecycle**](#4️⃣-manage-vm-lifecycle)
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

------

## 🛠 Requirements

Ensure you have the following installed before proceeding:

### **System Requirements**

- **Windows 10/11** or **Linux**
- **VMware Workstation Pro** (or Proxmox in future support)

### **Software Dependencies**

- **[Chocolatey](https://chocolatey.org/)** (Windows package manager)
- **[VMware Workstation](https://support.broadcom.com/group/ecx/downloads)**
- **[HashiCorp Packer](https://www.packer.io/)**
- **[HashiCorp Vagrant](https://developer.hashicorp.com/vagrant/install?product_intent=vagrant)**
- **[Vagrant VMware Utility](https://developer.hashicorp.com/vagrant/docs/providers/vmware/vagrant-vmware-utility)**
- **[Vagrant VMware Plugin](https://developer.hashicorp.com/vagrant/docs/providers/vmware/installation)**
- **[Visual Studio Code](https://code.visualstudio.com/)**

------

## 🔧 Installation

### **1️⃣ Install Chocolatey (Windows Users Only)**

Open **PowerShell as Administrator** and run:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

Verify installation:

```powershell
choco -?
```

### **2️⃣ Install Dependencies**

```powershell
choco install vmwareworkstation packer vagrant jq vscode -y
```

### **3️⃣ Install Vagrant VMware Plugin**

```powershell
choco install vagrant-vmware-utility -y
vagrant plugin install vagrant-vmware-desktop
```

### **4️⃣ Clone packertron-vms Repository**

```bash
git clone https://github.com/syselement/packertron-vms.git
cd packertron-vms
```

------

## 📁 Directory Structure

```
packertron-vms/
├── Win2025/
│   ├── config/          # Configuration files (autounattend.xml, unattend.xml)
│   ├── scripts/         # Automation scripts (Powershell, Batch)
│   ├── variables.pkrvars.hcl  # Packer variables
│   ├── win2025.pkr.hcl  # Packer HCL template
│   ├── vagrantfile      # Vagrant configuration
│   ├── output/          # VM build output
└── .gitignore           # Ignore unnecessary files (ISO, temp builds)
```

------

## 🚀 Build & Deploy VMs

### **1️⃣ Open Visual Studio Code**

```powershell
cd packertron-vms
code .
```

### **2️⃣ Packer: Initialize & Build Windows Server 2025**

```powershell
cd Win2025
packer init .
packer validate --var-file="winserver2025.pkrvars.hcl" win2025.pkr.hcl
packer build --var-file="winserver2025.pkrvars.hcl" win2025.pkr.hcl
```

### **3️⃣ Deploy VM with Vagrant**

```powershell
cd Win2025
vagrant up
```

### **4️⃣ Manage VM Lifecycle**

```powershell
# Shut down VM
vagrant halt

# Restart VM
vagrant up

# Destroy VM
vagrant destroy -f
```

------

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

------

## 📜 License

MIT License - See [LICENSE](LICENSE) for details.

## 🤝 Contributing

Pull requests and improvements are welcome! Ensure your code follows the repo’s standards.

## 🌍 Future Roadmap

✅ Proxmox support ✅ Ubuntu & Kali Linux Packer builds ✅ Integration with Ansible for advanced provisioning

------

🚀 **Happy Virtualizing with packertron-vms!**
