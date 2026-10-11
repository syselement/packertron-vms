# [0.83.0](https://github.com/syselement/packertron-vms/compare/v0.82.0...v0.83.0) (2026-10-11)


### Bug Fixes

* **templates:** bound the VMware and Vagrant plugins for real ([cb9fb80](https://github.com/syselement/packertron-vms/commit/cb9fb80b805d40bb19134b1edc0f0dee21647020))
* **windows:** run winget.exe as SYSTEM for the first-boot utilities ([77a7246](https://github.com/syselement/packertron-vms/commit/77a72464a4101ba2a692a3a0b7e174b04068c175))


### Features

* **customize-system:** enhance update alias to handle package manager failures ([823f590](https://github.com/syselement/packertron-vms/commit/823f590440b6be025dfad3ab75e2e5af1d53841e))
* **deploy:** drop state encryption ([3d06085](https://github.com/syselement/packertron-vms/commit/3d060856926731e9b74512c3b6e57d86cf83bba7))
* **deploy:** encrypted state, per-VM os and network, Windows first boot ([13f55c7](https://github.com/syselement/packertron-vms/commit/13f55c74a0cc3ea8adf639760064f592117b0892))
* **proxmox:** stage the template ISOs and prepare a node with one script each ([4fa7fe6](https://github.com/syselement/packertron-vms/commit/4fa7fe6ea962948f73c973b2de4a0603379b4b41))
* **seeds:** the SSH key is a variable, never committed ([bc945e5](https://github.com/syselement/packertron-vms/commit/bc945e594ecf26a89226d2e9e030c23c1daa7964))
* **termix:** enhance installation logic to select the latest stable Flatpak bundle ([5fcd8c9](https://github.com/syselement/packertron-vms/commit/5fcd8c9382aad80e7a75c078c227d0a8e8634d35))
* **ubuntu:** install markdownlint-cli2 and sofka with Homebrew ([c208d69](https://github.com/syselement/packertron-vms/commit/c208d69701bfaa877acfc92c06aeafd44c799c71))
* **ubuntu:** install the repository's check tooling in 03 ([8b35e36](https://github.com/syselement/packertron-vms/commit/8b35e363db204dc4e27481521db059014b8768cf))
* **vmware:** build win-srv-2025 on the Proxmox Windows chain ([d771593](https://github.com/syselement/packertron-vms/commit/d771593470122b5cbd819037b689605e25ecd039))
* **windows:** add HWiNFO and a WinUtil shortcut to the utilities ([72aad06](https://github.com/syselement/packertron-vms/commit/72aad0670ea0159cf76cedf39236495ce3ed6535))
* **windows:** install the utilities through winget ([7a110dc](https://github.com/syselement/packertron-vms/commit/7a110dc6c5917945a6ddaf820f7cb1badb813923))
* **windows:** install Windows on bare metal from a USB stick ([1a05532](https://github.com/syselement/packertron-vms/commit/1a05532da6d0e8824e571cea92a13c188c593fe7))



# [0.82.0](https://github.com/syselement/packertron-vms/compare/v0.81.0...v0.82.0) (2026-10-04)


### Features

* add GitHub CLI support and update Ubuntu ISO references to 24.04.5 ([d05631f](https://github.com/syselement/packertron-vms/commit/d05631fc4c4fd8db7f3a9b314c402ea00f8ebf05))



# [0.81.0](https://github.com/syselement/packertron-vms/compare/v0.80.0...v0.81.0) (2026-10-03)


### Bug Fixes

* **ubuntu:** install the plain RustDesk package, not a sibling build ([d236f82](https://github.com/syselement/packertron-vms/commit/d236f82ddb6c19f3179c23d8c315e3ebdc505592))


### Features

* **proxmox:** SPICE and staged ISOs for the Linux templates ([86a2f16](https://github.com/syselement/packertron-vms/commit/86a2f16b1079f7eee513afafa031cb8dc14537ef))
* **ubuntu:** add cv4pve-vdi, virt-viewer and asciinema ([9825e1e](https://github.com/syselement/packertron-vms/commit/9825e1e5cd7e2b634345db3f6fe04bbaf43765e5))



# [0.80.0](https://github.com/syselement/packertron-vms/compare/v0.79.0...v0.80.0) (2026-10-03)


### Bug Fixes

* **windows:** harden the VMware-path PowerShell scripts ([61ac75e](https://github.com/syselement/packertron-vms/commit/61ac75ea1119ca416b23d89c51415fd99353caac))


### Features

* **deploy:** clone straight to datastore_id ([5280f6f](https://github.com/syselement/packertron-vms/commit/5280f6f5940f24b4edc10d723914cc0b756f32ac))
* **deploy:** deploy the Windows templates ([8e0b63e](https://github.com/syselement/packertron-vms/commit/8e0b63e2edaff8020f8daa5d578b406297fb10c4))
* **proxmox:** add Windows 10, 11 and Server 2025 templates ([f7e3336](https://github.com/syselement/packertron-vms/commit/f7e33362504160283200b91c54c9ef8d562ca1ea))



# [0.79.0](https://github.com/syselement/packertron-vms/compare/v0.78.0...v0.79.0) (2026-09-27)


### Features

* update dock favorites to include Visual Studio Code ([5a4fed3](https://github.com/syselement/packertron-vms/commit/5a4fed3058ca085903d935eaf1ac29f7a2f4ccb9))



