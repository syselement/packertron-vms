# packertron-vms

> **Lab VMs from installer ISOs, with Packer, OpenTofu and Vagrant** - Proxmox VE first, VMware Workstation alongside.

[![syselement - packertron-vms](https://img.shields.io/static/v1?label=syselement&message=packertron-vms&color=blue&logo=github)](https://github.com/syselement/packertron-vms) [![stars - packertron-vms](https://img.shields.io/github/stars/syselement/packertron-vms?style=social)](https://github.com/syselement/packertron-vms) [![forks - packertron-vms](https://img.shields.io/github/forks/syselement/packertron-vms?style=social)](https://github.com/syselement/packertron-vms) [![License](https://img.shields.io/badge/License-MIT-orange)](#-license "Go to license section")

[![Packer](https://img.shields.io/badge/Packer->=1.12.0-brightgreen?logo=packer)](https://developer.hashicorp.com/packer "Go to Packer homepage") [![OpenTofu](https://img.shields.io/badge/OpenTofu->=1.6.0-brightgreen?logo=opentofu)](https://opentofu.org "Go to OpenTofu homepage") [![Vagrant](https://img.shields.io/badge/Vagrant->=2.4.3-brightgreen?logo=vagrant)](https://developer.hashicorp.com/vagrant "Go to Vagrant homepage")

Packer builds thin Proxmox VE templates from installer ISOs - Ubuntu, Kali and Windows - and OpenTofu clones them into VMs that provision themselves at first boot only when asked. The same Ubuntu provisioning scripts run on VMware Workstation images and on bare metal.

## 🚀 Quick start - Proxmox VE

| Step | | Docs |
| --- | --- | --- |
| 1 | Install the host tools and checks | [scripts/README.md](scripts/README.md#checks) |
| 2 | Prepare the node: role, API token, snippets | [templates/proxmox/README.md](templates/proxmox/README.md#1-prepare-the-node-once) |
| 3 | Stage the installer ISOs, verified | [templates/proxmox/README.md](templates/proxmox/README.md#3-stage-the-isos) |
| 4 | Build a template | [templates/proxmox/README.md](templates/proxmox/README.md#4-build) |
| 5 | Clone it into VMs with OpenTofu | [deploy/README.md](deploy/README.md) |
| 6 | Provision them at first boot, or a bare-metal install | [deploy/README.md](deploy/README.md#first-boot-provisioning), [scripts/ubuntu/README.md](scripts/ubuntu/README.md) |

For VMware Workstation and Vagrant, start at [templates/vmware/README.md](templates/vmware/README.md).

## 📚 Documentation

| Document | Covers |
| --- | --- |
| [templates/README.md](templates/README.md) | the template layout, and where each value goes |
| [templates/proxmox/README.md](templates/proxmox/README.md) | Proxmox: node, token, staging, building, the role |
| [templates/proxmox/LINUX.md](templates/proxmox/LINUX.md) | the Ubuntu and Kali templates: seed, SSH key, sealing |
| [templates/proxmox/WINDOWS.md](templates/proxmox/WINDOWS.md) | the Windows templates: build chain, cloudbase-init, evaluation period |
| [templates/vmware/README.md](templates/vmware/README.md) | VMware Workstation and Vagrant |
| [deploy/README.md](deploy/README.md) | OpenTofu: VMs from templates, first-boot provisioning, state |
| [scripts/README.md](scripts/README.md) | the scripts and every check |
| [scripts/ubuntu/README.md](scripts/ubuntu/README.md) | the Ubuntu provisioning chain, bare metal and autoinstall |
| [SECURITY.md](SECURITY.md) | the credential model - read it before putting a VM on a network |
| [AGENTS.md](AGENTS.md) | the repository's standards |

## 📁 Layout

```text
packertron-vms/
├── templates/
│   ├── proxmox/        the primary target: Ubuntu, Kali, Windows
│   └── vmware/         VMware Workstation and Vagrant
├── deploy/             OpenTofu: templates into VMs
├── scripts/            provisioners, node tooling, checks
│   ├── ubuntu/         the provisioning chain and its tests
│   ├── windows/        the Windows build chain
│   └── proxmox/        node preparation and ISO staging
└── .github/workflows/  CI, releases, and the weekly pin check
```

## 🗺️ Roadmap

- [x] Proxmox templates from ISO - Ubuntu Server 24.04 and 26.04, Ubuntu Desktop 26.04, Kali, Windows 10, 11 and Server 2025, all built and cloned
- [x] OpenTofu layer that clones them, with first-boot provisioning per VM
- [x] VMware Workstation - Ubuntu Server 24.04 and 26.04, Ubuntu Desktop 24.04, Windows Server 2025
- [ ] VMware Workstation - retest Ubuntu Desktop 26.04 on 26.04.1, and Windows Server 2025 on its new build chain
- [ ] Proxmox templates from the Ubuntu cloud image
- [ ] Proxmox LXC containers through OpenTofu - Packer's Proxmox plugin builds only VMs
- [ ] Ansible for advanced provisioning

## 📜 License

Released under the [MIT License](LICENSE) by [@syselement](https://github.com/syselement). Code adapted from other projects carries its upstream notice beside it: the Kali and Windows Proxmox READMEs, and the cloudbase-init configuration files.

## 🤝 Contributing

Pull requests are welcome. Follow [AGENTS.md](AGENTS.md), and run `scripts/check-templates.sh` before pushing.
