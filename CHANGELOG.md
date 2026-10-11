## [1.0.1](https://github.com/syselement/packertron-vms/compare/v1.0.0...v1.0.1) (2026-10-11)


### Bug Fixes

* check the release workflow after the 1.0.0 changelog repair ([44d6b26](https://github.com/syselement/packertron-vms/commit/44d6b263388fc76a7f3fdb3efdf2d86def706006))
* **windows:** say why setup-windows.ps1 ends with a restart ([f18ab47](https://github.com/syselement/packertron-vms/commit/f18ab470f2e4140a3408aab13aedc433738a00a4))



# [1.0.0](https://github.com/syselement/packertron-vms/compare/v0.82.0...v1.0.0) (2026-10-11)


### Bug Fixes

* **templates:** bound the VMware and Vagrant plugins for real ([cb9fb80](https://github.com/syselement/packertron-vms/commit/cb9fb80b805d40bb19134b1edc0f0dee21647020))
* **windows:** run winget.exe as SYSTEM for the first-boot utilities ([77a7246](https://github.com/syselement/packertron-vms/commit/77a72464a4101ba2a692a3a0b7e174b04068c175))


* feat!: release 1.0 - templates, deploy/ and checks reworked ([240bc48](https://github.com/syselement/packertron-vms/commit/240bc489bacf61c07785872f1fa28a0fa3f70f52))


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


### BREAKING CHANGES

* Linux builds need ssh_authorized_key; install_utils.ps1 moved to scripts/windows/; 02_win_updates.ps1 is gone; Windows deploy/ entries with provisioning_steps need os = "windows".



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



# [0.78.0](https://github.com/syselement/packertron-vms/compare/v0.77.0...v0.78.0) (2026-09-27)


### Features

* enhance deployment documentation and examples for VM provisioning ([283d1ef](https://github.com/syselement/packertron-vms/commit/283d1ef189287fb8067b82ecd2116d6b7a54b4c2))



# [0.77.0](https://github.com/syselement/packertron-vms/compare/v0.76.0...v0.77.0) (2026-09-23)


### Features

* **proxmox:** add task timeout for image conversion in Kali and Ubuntu templates ([d6069fa](https://github.com/syselement/packertron-vms/commit/d6069fad52ec6f6d4f7555d811f3d235421e447c))



# [0.76.0](https://github.com/syselement/packertron-vms/compare/v0.75.0...v0.76.0) (2026-09-23)


### Features

* **kali:** enhance Kali template support and update deployment configurations ([e1d8f0f](https://github.com/syselement/packertron-vms/commit/e1d8f0f7371e342dcce941c9798104015817b952))



# [0.75.0](https://github.com/syselement/packertron-vms/compare/v0.74.0...v0.75.0) (2026-09-22)


### Features

* **kali:** update fstab handling and improve tofu formatting checks ([867a0b3](https://github.com/syselement/packertron-vms/commit/867a0b3385de75b295491cf0073af6b1acfb633a))



# [0.74.0](https://github.com/syselement/packertron-vms/compare/v0.73.0...v0.74.0) (2026-09-22)


### Features

* **kali:** enhance Proxmox Kali template with debian-installer preseed and validation checks ([16b7c8a](https://github.com/syselement/packertron-vms/commit/16b7c8a4376876f8fb7a546bde4639f7dadb2865))



# [0.73.0](https://github.com/syselement/packertron-vms/compare/v0.72.0...v0.73.0) (2026-09-21)


### Bug Fixes

* update permissions and execution method for firstboot scripts to resolve permission issues ([420d938](https://github.com/syselement/packertron-vms/commit/420d938d5144d5226cd52251bcd2d9d889f6eb74))
* update README and example files to clarify password requirements for desktop clones ([20d2860](https://github.com/syselement/packertron-vms/commit/20d2860db460dbf014df9f82ab59098c12a4ce7c))


### Features

* **deploy:** add example configuration for VM clone profiles ([1a7d24e](https://github.com/syselement/packertron-vms/commit/1a7d24e8302f4bdaf902873a6050016ac8e24473))



# [0.72.0](https://github.com/syselement/packertron-vms/compare/v0.71.0...v0.72.0) (2026-09-19)


### Features

* **proxmox:** streamline SSH host key management and update README for clarity ([2356840](https://github.com/syselement/packertron-vms/commit/2356840904e1ae4291e95e9a2119b92bb321c2c5))



# [0.71.0](https://github.com/syselement/packertron-vms/compare/v0.70.0...v0.71.0) (2026-09-19)


### Features

* update runner handling to fetch from repository ref instead of working tree ([19655af](https://github.com/syselement/packertron-vms/commit/19655af9210eb1c36705492732762a9deb21217a))



# [0.70.0](https://github.com/syselement/packertron-vms/compare/v0.69.0...v0.70.0) (2026-09-09)


### Bug Fixes

* **proxmox:** authenticate over the SSH agent, and make the two first-build knobs tunable ([1321201](https://github.com/syselement/packertron-vms/commit/132120128e47ae137d5a462ba56dd3d4ea9eb463))
* **proxmox:** increase VM cores from 1 to 2 for improved performance ([28b4a3d](https://github.com/syselement/packertron-vms/commit/28b4a3d2b2f1d44d19594a53ddeff56a3fe8bd1e))
* update Proxmox template VM ID and enhance cloud-init handling ([7f4871b](https://github.com/syselement/packertron-vms/commit/7f4871b36a377dc2b2c1f0c3592259c2e44385d3))


### Features

* enhance template checks, add Markdown verification, and update README and user-data for clarity ([78d2af8](https://github.com/syselement/packertron-vms/commit/78d2af80a6370669c6f4695e8329ff6bc07e29b3))
* **packer:** add an Ubuntu Server 24.04 template for Proxmox ([38a556b](https://github.com/syselement/packertron-vms/commit/38a556bb567af5b0890be3b348b2ea18e1a48c85))
* **proxmox:** enhance ISO handling and update template description for clarity ([bf29ea0](https://github.com/syselement/packertron-vms/commit/bf29ea0c5343f5344956870a1ed156b29eb13792))
* **scripts:** add host requirement scripts for Linux and Windows ([e5a2106](https://github.com/syselement/packertron-vms/commit/e5a21060a118185e42f6d4ca476efae173d4a557))



# [0.69.0](https://github.com/syselement/packertron-vms/compare/v0.68.1...v0.69.0) (2026-09-05)


### Bug Fixes

* **ci:** push releases with a token that the ruleset lets through ([338c9c3](https://github.com/syselement/packertron-vms/commit/338c9c3d4f584c1fad01b35363175a5de1db10bc))


### Features

* **scripts:** add check-templates.sh to run the CI checks locally ([d83041e](https://github.com/syselement/packertron-vms/commit/d83041efa59d01f528212493f1ea14257aec96bb))



## [0.68.1](https://github.com/syselement/packertron-vms/compare/v0.68.0...v0.68.1) (2026-09-05)


### Bug Fixes

* **ci:** drop the custom Dependabot labels ([c9340bd](https://github.com/syselement/packertron-vms/commit/c9340bd9cd20ef4e0f2ddf5f98949e1d2556e73b))



# [0.68.0](https://github.com/syselement/packertron-vms/compare/v0.67.3...v0.68.0) (2026-09-05)


### Bug Fixes

* **packer:** make the Kali template validate, without KeePass ([756e254](https://github.com/syselement/packertron-vms/commit/756e254648f1454f192f6b81a020107394b0118a))
* **packer:** make the Ubuntu templates validate again ([5e9f6b7](https://github.com/syselement/packertron-vms/commit/5e9f6b747ba291415f1e3d5dd8117917fd78a011))
* **packer:** make the Windows Server 2025 template validate ([f69cc9e](https://github.com/syselement/packertron-vms/commit/f69cc9eddc27996ba24ec8cf4b052c8f5ab0310d))
* update comment formatting in .bash_aliases ([4fd13e7](https://github.com/syselement/packertron-vms/commit/4fd13e74d4d490b07760e9e5ddac2c04f9f15d2b))


### Features

* **packer:** add an Ubuntu Server 26.04 template ([975d403](https://github.com/syselement/packertron-vms/commit/975d403a06941ba10730104ab4f7df664eb151a0))



## [0.67.3](https://github.com/syselement/packertron-vms/compare/v0.67.2...v0.67.3) (2026-09-05)


### Bug Fixes

* **ubuntu:** increase reboot delay to 10 seconds after provisioning ([0c80538](https://github.com/syselement/packertron-vms/commit/0c805380c19d66a7d5b0885383d3bffd2c864c59))
* **ubuntu:** retry a Homebrew formula install before failing the run ([5e7c550](https://github.com/syselement/packertron-vms/commit/5e7c550f916bec31eafd5a62b87508851c17814f))



## [0.67.2](https://github.com/syselement/packertron-vms/compare/v0.67.1...v0.67.2) (2026-09-05)


### Bug Fixes

* **autoinstall:** let a pushed fix supersede a failing pinned revision ([affbdd2](https://github.com/syselement/packertron-vms/commit/affbdd23c168da8bde25ab2f1da264e751932171))
* detect a pending reboot and repair the 24.04 Server Packer template ([0f2ca43](https://github.com/syselement/packertron-vms/commit/0f2ca437b35147ac3fc9843155e021f4686c032d))
* **ubuntu:** keep VS Code on Desktop and tolerate absent Desktop packages ([d18a20a](https://github.com/syselement/packertron-vms/commit/d18a20aa364fbfe429eb9d5b74e35ef45e332fdd))
* **ubuntu:** make service configuration converge and bound snap operations ([29c4ff7](https://github.com/syselement/packertron-vms/commit/29c4ff77839d6f421842e9afe2b6512b8cb6b5ae))
* **ubuntu:** repair bare-metal bootstrap safety defects ([c07ef45](https://github.com/syselement/packertron-vms/commit/c07ef45526fd3d72f8faf6ee89a24d9094c2ae98))
* **ubuntu:** stop dpkg conffile prompts and harden 01-cleanup-system ([f786cd5](https://github.com/syselement/packertron-vms/commit/f786cd5e9acd8b977d539284538c282edb7dc696))
* **ubuntu:** stop dpkg progress meters filling the logs with blank lines ([14bf071](https://github.com/syselement/packertron-vms/commit/14bf071850b4202d7ee0f44cbedbaa8a056d1a3e))



## [0.67.1](https://github.com/syselement/packertron-vms/compare/v0.67.0...v0.67.1) (2026-09-05)


### Bug Fixes

* **logging:** remove redundant comments and improve log file handling ([082fcdb](https://github.com/syselement/packertron-vms/commit/082fcdb0dd778da5908c7ef4793281744478abc2))
* **ubuntu:** detect interactivity before stdout is redirected, tidy log output ([84b4780](https://github.com/syselement/packertron-vms/commit/84b478030ed17f7b9763855cabb7bb5a7847ef43))
* **ubuntu:** stop Termius and Yubico downloading before checking versions ([bc0d588](https://github.com/syselement/packertron-vms/commit/bc0d5883aad9a92df0efdce91048d38f554116ff))



# [0.67.0](https://github.com/syselement/packertron-vms/compare/v0.66.0...v0.67.0) (2026-09-05)


### Features

* add run_as_target_user_in_home function and update tests for home directory context ([f362356](https://github.com/syselement/packertron-vms/commit/f362356efba3d266332d863d4366ee819fc9d7fc))



# [0.66.0](https://github.com/syselement/packertron-vms/compare/v0.65.0...v0.66.0) (2026-08-31)


### Features

* add run_as_target_user_in_home function and update tests for home directory context ([0a4fd51](https://github.com/syselement/packertron-vms/commit/0a4fd5191f3ee0ed0e62719c8217a0ef1bd91025))



# [0.65.0](https://github.com/syselement/packertron-vms/compare/v0.64.0...v0.65.0) (2026-08-31)


### Features

* add support for user-level systemd services and update tests for Syncthing ([ec40b9a](https://github.com/syselement/packertron-vms/commit/ec40b9a85a5a046670951e1bc891a7ae6393e101))



# [0.64.0](https://github.com/syselement/packertron-vms/compare/v0.63.0...v0.64.0) (2026-08-30)


### Features

* update dock favorites to include Termix ([d7ceb89](https://github.com/syselement/packertron-vms/commit/d7ceb89a35d8117642a5d53fac8fa3506c1527aa))



# [0.63.0](https://github.com/syselement/packertron-vms/compare/v0.62.0...v0.63.0) (2026-08-23)


### Features

* add installation support for Clockify ([4c0f176](https://github.com/syselement/packertron-vms/commit/4c0f176fe137238d8ad18a02d8ad614bdc0172e2))
* add installation support for Strawberry Music Player and related tests, inxi and hardinfo2 tools ([5ac3d4d](https://github.com/syselement/packertron-vms/commit/5ac3d4d124fbf5eb75a40d864d008c5c0e871919))



# [0.62.0](https://github.com/syselement/packertron-vms/compare/v0.61.0...v0.62.0) (2026-08-22)


### Features

* add installation support for ChatGPT and update Obsidian release handling in customization script ([86d74bd](https://github.com/syselement/packertron-vms/commit/86d74bd0aa175114d9ddbb8d1888d97ee61be2a8))



# [0.61.0](https://github.com/syselement/packertron-vms/compare/v0.60.0...v0.61.0) (2026-08-20)


### Features

* add installation support for Yubico Authenticator and Zed in customization script ([0443b30](https://github.com/syselement/packertron-vms/commit/0443b30f4bd448566ff9b188a2ca6048ed605806))



# [0.60.0](https://github.com/syselement/packertron-vms/compare/v0.59.0...v0.60.0) (2026-08-17)


### Features

* add balenaEtcher installation and update Termix handling in customization script ([35d2bce](https://github.com/syselement/packertron-vms/commit/35d2bcefd4653337124bef37e960c9d4b25cd034))
* add MKVToolNix repository and related packages to customization script ([7cb280b](https://github.com/syselement/packertron-vms/commit/7cb280b090418bb53ee40eff40f84ed050090a10))



# [0.59.0](https://github.com/syselement/packertron-vms/compare/v0.58.1...v0.59.0) (2026-08-16)


### Features

* add Smile complementary extension and update keyboard shortcuts ([5228eea](https://github.com/syselement/packertron-vms/commit/5228eea7595bc4554437cd9ad6f3be2ebc59c53e))
* update dock favorites to include Claude and Typora ([b4b4160](https://github.com/syselement/packertron-vms/commit/b4b41607f7f04e5f515abeb6d4066cb9f4d735e4))



## [0.58.1](https://github.com/syselement/packertron-vms/compare/v0.58.0...v0.58.1) (2026-08-16)


### Bug Fixes

* add missing -y flag to brew upgrade in updateos alias for desktop users ([85603a7](https://github.com/syselement/packertron-vms/commit/85603a79f74939659e1cb0fe9b1d9a0665fd95df))



# [0.58.0](https://github.com/syselement/packertron-vms/compare/v0.57.0...v0.58.0) (2026-08-16)


### Features

* add Kubernetes CLI tools installation and Helm repository setup ([8acc829](https://github.com/syselement/packertron-vms/commit/8acc829dce777056c057fc3bf8b02a4e09914660))



# [0.57.0](https://github.com/syselement/packertron-vms/compare/v0.56.0...v0.57.0) (2026-08-16)


### Features

* add apparmor-utils and traceroute to common packages ([e7b2d72](https://github.com/syselement/packertron-vms/commit/e7b2d72fa24d36cf7d8b0b6378a8f03af8382df6))
* add Claude Code installation and verification to customization script ([1197831](https://github.com/syselement/packertron-vms/commit/1197831e2c86bb4d66e433786d27de556e62cca6))
* add Cryptomator FUSE access configuration and AppArmor profile management ([e2edf05](https://github.com/syselement/packertron-vms/commit/e2edf05f0e17c9f44a1c3af325548163e7f6d342))
* add custom keyboard shortcuts for Flameshot, Emote, and Claude new chat ([948b106](https://github.com/syselement/packertron-vms/commit/948b10644df3d804a6dcaf69faf8c553c2f0e54a))
* add documentation links to manual setup hints in customization script ([4a506f8](https://github.com/syselement/packertron-vms/commit/4a506f8a365908b1573da096fec774513284a8e4))
* add iximiuz Labs control (labctl) installation and verification to customization script ([468cdd5](https://github.com/syselement/packertron-vms/commit/468cdd554c91e2588185c1787e0db0d0e564611b))
* add Syncthing service configuration and repository setup ([5e7d0ab](https://github.com/syselement/packertron-vms/commit/5e7d0ab0ea52a85ad5ed67bd40d3d3610381b094))



# [0.56.0](https://github.com/syselement/packertron-vms/compare/v0.55.0...v0.56.0) (2026-08-09)


### Features

* update GNOME interface font settings to use Adwaita Sans ([e01f54c](https://github.com/syselement/packertron-vms/commit/e01f54c43b6587ab37943cb6dc662178c1c058f3))



# [0.55.0](https://github.com/syselement/packertron-vms/compare/v0.54.1...v0.55.0) (2026-08-09)


### Bug Fixes

* update Claude Desktop repository test to specify amd64 architecture ([1be2f86](https://github.com/syselement/packertron-vms/commit/1be2f8620f861c6b8bcd4b276f34722330f80144))


### Features

* add Claude Desktop repository and corresponding tests ([020a11d](https://github.com/syselement/packertron-vms/commit/020a11d1033d439fbe4b6ec5576b5507dcace622))
* add manual setup hints for Claude new chat and corresponding tests ([5c0b0a5](https://github.com/syselement/packertron-vms/commit/5c0b0a5b2d491673a8ed28b4413ff150f097df49))
* configure Cockpit to listen on port 9443 and update manual setup instructions ([a553c3c](https://github.com/syselement/packertron-vms/commit/a553c3cfef2ee9b64ba9647aad9e40d2c15b7454))



## [0.54.1](https://github.com/syselement/packertron-vms/compare/v0.54.0...v0.54.1) (2026-08-04)


### Bug Fixes

* update manual setup hints for consistency in settings navigation ([87d2be3](https://github.com/syselement/packertron-vms/commit/87d2be3a9a6c7e8604e41b7cbe4c4217e90ad8a4))



# [0.54.0](https://github.com/syselement/packertron-vms/compare/v0.53.0...v0.54.0) (2026-08-04)


### Features

* add support for Dim Background Windows GNOME extension and schema compilation ([a8c6476](https://github.com/syselement/packertron-vms/commit/a8c6476000606504eb3da71a869609b80b6c9b27))



# [0.53.0](https://github.com/syselement/packertron-vms/compare/v0.52.0...v0.53.0) (2026-08-04)


### Features

* configure mouse settings for improved user experience in GNOME ([0bdb41f](https://github.com/syselement/packertron-vms/commit/0bdb41f525ce53b652f2729ef552a349413c2fc2))



# [0.52.0](https://github.com/syselement/packertron-vms/compare/v0.51.0...v0.52.0) (2026-08-02)


### Features

* enhance logging format in customization script and tests for clarity ([9a36c73](https://github.com/syselement/packertron-vms/commit/9a36c73d3b7b5c35d09f837def96efb277d10fce))



# [0.51.0](https://github.com/syselement/packertron-vms/compare/v0.50.0...v0.51.0) (2026-08-02)


### Features

* remove ConditionPathExists check from autoinstall scripts and update tests ([806edbe](https://github.com/syselement/packertron-vms/commit/806edbe597023e2021e6d8c2ae8ac6e6df62b42b))
* update GNOME settings for workspace behavior and dock action ([5df5034](https://github.com/syselement/packertron-vms/commit/5df50346b77abd7a090e06800ee2ab2d0909d4ef))



# [0.50.0](https://github.com/syselement/packertron-vms/compare/v0.49.0...v0.50.0) (2026-08-02)


### Features

* add Homebrew installation support with CPU architecture checks and test cases ([167b778](https://github.com/syselement/packertron-vms/commit/167b778f4c4214bf69d289c0153b1503effe6792))



# [0.49.0](https://github.com/syselement/packertron-vms/compare/v0.48.0...v0.49.0) (2026-08-02)


### Features

* refactor package management to include release-optional packages and enhance testing ([9bfe481](https://github.com/syselement/packertron-vms/commit/9bfe4819edc1b87dcaa743d5f3e6557dba7d614c))



# [0.48.0](https://github.com/syselement/packertron-vms/compare/v0.47.0...v0.48.0) (2026-08-02)


### Features

* enhance logging and timeout settings in provisioning scripts ([85d4ba5](https://github.com/syselement/packertron-vms/commit/85d4ba546742e8bd417fece4ef0b2b7d705f2580))
* refactor update system script and enhance guest tool installation logic ([af00cc7](https://github.com/syselement/packertron-vms/commit/af00cc76ccf3c929d189c1ddb12479688a17baeb))



# [0.47.0](https://github.com/syselement/packertron-vms/compare/v0.46.0...v0.47.0) (2026-08-02)


### Features

* add alias for retrieving public IP address ([6b99d80](https://github.com/syselement/packertron-vms/commit/6b99d809dbd9e05c29eb49e2d237d2659926f4b1))
* add whois package to common packages list ([21227d4](https://github.com/syselement/packertron-vms/commit/21227d4bba8478b11d1f29ceec72b4f57253ffc7))
* implement APT transaction management for safer package updates and rollbacks ([117506b](https://github.com/syselement/packertron-vms/commit/117506b0d8f4c2ef4a52a3b8b96fe60132f00b66))
* update manual setup steps and add WireGuard connection instructions ([e0f6dc0](https://github.com/syselement/packertron-vms/commit/e0f6dc0ba7d017146246ac05696ff1b3bfaec022))
* update public IP alias to use ifconfig.me for better reliability ([a2488d3](https://github.com/syselement/packertron-vms/commit/a2488d3687d66a6d97b2518c54a3bc70d645ac7e))



# [0.46.0](https://github.com/syselement/packertron-vms/compare/v0.45.0...v0.46.0) (2026-07-28)


### Bug Fixes

* update shortcut for Emote command in manual setup hints ([e60071c](https://github.com/syselement/packertron-vms/commit/e60071cb61252c3867268ec3ff71ea228443ad93))


### Features

* add data directory creation in user workspace setup ([4aa688f](https://github.com/syselement/packertron-vms/commit/4aa688f83031b1eac20736b7272b7e3e1455094f))
* add de.swsnr.turnon Flatpak package to desktop environment setup ([d15f67d](https://github.com/syselement/packertron-vms/commit/d15f67df2f7aea5bf7833274f22fcebfaa64eebf))
* add Docker directory creation in user workspace setup ([8ce13dc](https://github.com/syselement/packertron-vms/commit/8ce13dcc0cea3327e4afa51332390d3c0b12f494))
* ensure Typora configuration and theme directories are created with correct ownership ([a9108b7](https://github.com/syselement/packertron-vms/commit/a9108b77792af50950642254e274ffeab1721965))
* refactor Vagrantfile to use inline provisioning scripts and add integration tests ([891e1dc](https://github.com/syselement/packertron-vms/commit/891e1dcfc8fe939cd267b4bae5013327a920dbce))



# [0.45.0](https://github.com/syselement/packertron-vms/compare/v0.44.0...v0.45.0) (2026-07-28)


### Features

* add cockpit-machines package to virtualization host packages ([ce85059](https://github.com/syselement/packertron-vms/commit/ce850591074216e52d1b2d732f0a6b8244a43c84))
* add virtualization support and related configuration to customization script ([2b6b52a](https://github.com/syselement/packertron-vms/commit/2b6b52ae41a487dcdabeb5254c67a27d6991e79f))
* update manual setup instructions and enhance test cases for virtualization ([afc39b3](https://github.com/syselement/packertron-vms/commit/afc39b36b079af498f544564e37ec187c1d54615))



# [0.44.0](https://github.com/syselement/packertron-vms/compare/v0.43.0...v0.44.0) (2026-07-28)


### Features

* add Cockpit socket configuration and related tests ([0259609](https://github.com/syselement/packertron-vms/commit/0259609cba6ce9e57c237d9a9219ced5f3b74374))
* enhance logging and manual setup instructions in customization script ([4111a3d](https://github.com/syselement/packertron-vms/commit/4111a3d55b897ab9fa766f8c9a14a420cbb150d6))
* enhance package installation logic to skip downloads for already installed versions ([bd2efb0](https://github.com/syselement/packertron-vms/commit/bd2efb017a884b94bda81ab9631b42a9064fc894))



# [0.43.0](https://github.com/syselement/packertron-vms/compare/v0.42.2...v0.43.0) (2026-07-27)


### Features

* add support for Vagrant and additional packages in provisioning scripts ([6a2ccd3](https://github.com/syselement/packertron-vms/commit/6a2ccd34399b93d701a08a7e9c410d390f4b8ab2))
* added io.github.sigmasd.pingmonitor to Flatpak packages ([b774f34](https://github.com/syselement/packertron-vms/commit/b774f347fdced08d954e2d4f3f6fea67d5c83c1a))



## [0.42.2](https://github.com/syselement/packertron-vms/compare/v0.42.1...v0.42.2) (2026-07-21)


### Bug Fixes

* update GNOME system monitor panel extension download URL and enhance autoinstall.yaml documentation ([4812989](https://github.com/syselement/packertron-vms/commit/481298914ca12b4afba34f6e73d0957cfc6f3e58))



## [0.42.1](https://github.com/syselement/packertron-vms/compare/v0.42.0...v0.42.1) (2026-07-19)


### Bug Fixes

* update Brave repository URL to remove trailing slash in customization script and tests ([3f4246b](https://github.com/syselement/packertron-vms/commit/3f4246beb952c21a0f531a7c5091c36a3c7a4de0))



# [0.42.0](https://github.com/syselement/packertron-vms/compare/v0.41.0...v0.42.0) (2026-07-19)


### Features

* add Mullvad VPN support and enhance repository management in customization script ([2a836ae](https://github.com/syselement/packertron-vms/commit/2a836aeed2b7dcd6338a8d0fb7b6297f24221020))



# [0.41.0](https://github.com/syselement/packertron-vms/compare/v0.40.1...v0.41.0) (2026-07-19)


### Features

* add 'bats', 'shellcheck', and 'shfmt' to common packages ([eb9628b](https://github.com/syselement/packertron-vms/commit/eb9628b37271e7201dabb3ac7a44b8193eb53970))



## [0.40.1](https://github.com/syselement/packertron-vms/compare/v0.40.0...v0.40.1) (2026-07-19)


### Bug Fixes

* update sudoers file naming convention for consistency ([48661e9](https://github.com/syselement/packertron-vms/commit/48661e9cdea26da9b8e84feb2fc35a2d1580a73b))



# [0.40.0](https://github.com/syselement/packertron-vms/compare/v0.39.0...v0.40.0) (2026-07-19)


### Features

* add support for Flatpak packages and configure Flathub remote ([55c8e52](https://github.com/syselement/packertron-vms/commit/55c8e5251cff4bf64d38139a8b26bf408a64fe69))



# [0.39.0](https://github.com/syselement/packertron-vms/compare/v0.38.0...v0.39.0) (2026-07-17)


### Features

* add configuration for Flameshot and install Ente Auth package ([1afc9df](https://github.com/syselement/packertron-vms/commit/1afc9df45fa8cc31ce30a518f4cc7881cd2281e9))



# [0.38.0](https://github.com/syselement/packertron-vms/compare/v0.37.0...v0.38.0) (2026-07-16)


### Features

* add fd-find to common packages and alias for fdfind ([e8a350e](https://github.com/syselement/packertron-vms/commit/e8a350e9c69a5443e19dbe1d4dca4bcc2709f090))



# [0.37.0](https://github.com/syselement/packertron-vms/compare/v0.36.0...v0.37.0) (2026-07-16)


### Features

* update GNOME screensaver settings for enhanced security and user experience ([905a83a](https://github.com/syselement/packertron-vms/commit/905a83a5a921c1c97f0d7202630583f60cd8b0d3))



# [0.36.0](https://github.com/syselement/packertron-vms/compare/v0.35.0...v0.36.0) (2026-07-16)


### Features

* add functionality to clone and synchronize Packertron repository for desktop wallpaper configuration ([38f51d7](https://github.com/syselement/packertron-vms/commit/38f51d754d6c98b8a9383967fc8f170269076bfa))



# [0.35.0](https://github.com/syselement/packertron-vms/compare/v0.34.0...v0.35.0) (2026-07-16)


### Features

* add gsetting value comparison function and update GNOME settings ([335bc5a](https://github.com/syselement/packertron-vms/commit/335bc5ae9c35bf4f5a0704dbaf402674e2847561))



# [0.34.0](https://github.com/syselement/packertron-vms/compare/v0.33.0...v0.34.0) (2026-07-16)


### Features

* enhance GNOME settings and add wallpaper configuration ([b453075](https://github.com/syselement/packertron-vms/commit/b4530755ddecb21dd667cdb80ffd9c900bd61d44))



# [0.33.0](https://github.com/syselement/packertron-vms/compare/v0.32.0...v0.33.0) (2026-07-14)


### Features

* update manual setup hints for keyboard shortcuts and add Emote command ([c4196ba](https://github.com/syselement/packertron-vms/commit/c4196ba6bba55a64a335c31898c5330a26762831))



# [0.32.0](https://github.com/syselement/packertron-vms/compare/v0.31.0...v0.32.0) (2026-07-14)


### Features

* add new aliases for Brave browser and improved command utilities ([4e8a44c](https://github.com/syselement/packertron-vms/commit/4e8a44c148db60d375beffb0c3dc44355f161abb))



# [0.31.0](https://github.com/syselement/packertron-vms/compare/v0.30.1...v0.31.0) (2026-07-14)


### Features

* enhance user workspace setup and add Homebrew installation instructions ([0619183](https://github.com/syselement/packertron-vms/commit/06191838c76afa6f75d9c9d59891662326938e98))



## [0.30.1](https://github.com/syselement/packertron-vms/compare/v0.30.0...v0.30.1) (2026-07-12)


### Bug Fixes

* correct Obsidian desktop entry name in GNOME favorites ([0e926a7](https://github.com/syselement/packertron-vms/commit/0e926a758ff7dd36fc89f21f89b0ec0516df8ae2))



# [0.30.0](https://github.com/syselement/packertron-vms/compare/v0.29.0...v0.30.0) (2026-07-12)


### Features

* replace Obsidian snap installation with direct Debian package installation and adjust GNOME settings ([6616e6e](https://github.com/syselement/packertron-vms/commit/6616e6ec0f2113c44d7ec6318f676e5c45da9cab))



# [0.29.0](https://github.com/syselement/packertron-vms/compare/v0.28.1...v0.29.0) (2026-07-12)


### Features

* add Bitwarden and Discord snap installation functions and create new autoinstall configuration file ([7377b73](https://github.com/syselement/packertron-vms/commit/7377b73591e5c6967acdc1434a26c9fe002b0934))



## [0.28.1](https://github.com/syselement/packertron-vms/compare/v0.28.0...v0.28.1) (2026-07-12)


### Bug Fixes

* suppress errors for version checks and improve reboot handling in bootstrap script ([e1ea59a](https://github.com/syselement/packertron-vms/commit/e1ea59a5d87253ffcd3541ff6422529905f1b4c2))



# [0.28.0](https://github.com/syselement/packertron-vms/compare/v0.27.0...v0.28.0) (2026-07-12)


### Features

* add first-boot orchestration and autoinstall configuration for Ubuntu 26.04 ([4be123e](https://github.com/syselement/packertron-vms/commit/4be123e7453095f625a1a46d8ca1b442979246a1))



# [0.27.0](https://github.com/syselement/packertron-vms/compare/v0.26.0...v0.27.0) (2026-07-12)


### Features

* update Flameshot command to include clipboard and save path ([eec45b7](https://github.com/syselement/packertron-vms/commit/eec45b76feb992738985fae65d040878fae250fa))



# [0.26.0](https://github.com/syselement/packertron-vms/compare/v0.25.0...v0.26.0) (2026-07-12)


### Features

* improve installation process for System Monitor Panel extension ([e169d65](https://github.com/syselement/packertron-vms/commit/e169d6539be9de78740d55dcf1f503f4f42a12f5))



# [0.25.0](https://github.com/syselement/packertron-vms/compare/v0.24.0...v0.25.0) (2026-07-12)


### Features

* add support for System Monitor Panel extension installation and management ([2a15ecb](https://github.com/syselement/packertron-vms/commit/2a15ecb13e34847f2c3ce8b1f2883ef0303be9c9))



# [0.24.0](https://github.com/syselement/packertron-vms/compare/v0.23.0...v0.24.0) (2026-07-12)


### Features

* remove SnapX installation and add Flameshot installation script ([b9a7f7c](https://github.com/syselement/packertron-vms/commit/b9a7f7c528596a6fc570a7e44c80c4d757a8d780))



# [0.23.0](https://github.com/syselement/packertron-vms/compare/v0.22.0...v0.23.0) (2026-07-12)


### Features

* add function to install SnapX snap if not already present ([5ad0edb](https://github.com/syselement/packertron-vms/commit/5ad0edbf81595f3d0e9a9968c6c8193e8589ea23))



# [0.22.0](https://github.com/syselement/packertron-vms/compare/v0.21.0...v0.22.0) (2026-07-12)


### Features

* enhance GNOME settings and add battery health preservation functionality ([ed6be33](https://github.com/syselement/packertron-vms/commit/ed6be3350916ced4498d72c705fcf56c340aacbe))



# [0.21.0](https://github.com/syselement/packertron-vms/compare/v0.20.0...v0.21.0) (2026-07-12)


### Features

* add function to configure Git identity for user ([bc9124d](https://github.com/syselement/packertron-vms/commit/bc9124d4520277a4fb155fed5fc7e2eb1e9aa8e4))
* update Git configuration function to include pull-rebase policy ([3400b51](https://github.com/syselement/packertron-vms/commit/3400b51d2d2a436a91913eb681d67928bce9116b))



# [0.20.0](https://github.com/syselement/packertron-vms/compare/v0.19.1...v0.20.0) (2026-07-12)


### Bug Fixes

* update file permissions for bash scripts and custom GNOME settings ([bf5cd61](https://github.com/syselement/packertron-vms/commit/bf5cd61b7fce312ae4b3a2e6e98d35a0dc2cf329))


### Features

* enhance GNOME preferences application and remove deprecated backup script ([21b58e2](https://github.com/syselement/packertron-vms/commit/21b58e2073f9c67e3e1e61da86c57a81019b883c))



## [0.19.1](https://github.com/syselement/packertron-vms/compare/v0.19.0...v0.19.1) (2026-07-03)


### Bug Fixes

* update HISTTIMEFORMAT handling in bash configuration ([138c750](https://github.com/syselement/packertron-vms/commit/138c7501d7fd20f98eb59b57c7903213f09629a5))



# [0.19.0](https://github.com/syselement/packertron-vms/compare/v0.18.0...v0.19.0) (2026-07-03)


### Features

* add fastfetch support to bash configuration ([879590b](https://github.com/syselement/packertron-vms/commit/879590be5e1dc9d0faa0f93d8205aaaff5692143))



# [0.18.0](https://github.com/syselement/packertron-vms/compare/v0.17.0...v0.18.0) (2026-07-02)


### Features

* update format strings in Starship configuration for enhanced terminal output ([58a63d7](https://github.com/syselement/packertron-vms/commit/58a63d7624b9f24fc6cd0f4af763e9f483d132e2))



# [0.17.0](https://github.com/syselement/packertron-vms/compare/v0.16.0...v0.17.0) (2026-07-02)


### Features

* update FZF options and enhance Starship configuration for improved terminal experience ([2a9da85](https://github.com/syselement/packertron-vms/commit/2a9da8596bcd6a0248fea3f898fffbf5164c805a))



# [0.16.0](https://github.com/syselement/packertron-vms/compare/v0.15.3...v0.16.0) (2026-07-01)


### Features

* enhance system customization script for Ubuntu with package management and user configuration ([0dd8cc2](https://github.com/syselement/packertron-vms/commit/0dd8cc27fcc1857debeb6f2306abcd00940b1565))



## [0.15.3](https://github.com/syselement/packertron-vms/compare/v0.15.2...v0.15.3) (2026-07-01)


### Bug Fixes

* update package list in install_packages function to include coreutils, dnsutils, lm-sensors, openjdk-21-jre-headless, s-tui, and stress ([4f1a943](https://github.com/syselement/packertron-vms/commit/4f1a943844a5c71735aa5417d9b49390cf34e9ad))



## [0.15.2](https://github.com/syselement/packertron-vms/compare/v0.15.1...v0.15.2) (2026-06-14)


### Bug Fixes

* update package installation and source list handling in provisioning scripts ([01e3122](https://github.com/syselement/packertron-vms/commit/01e3122b438b081deda20b7bfee6b3f6eef4da53))



## [0.15.1](https://github.com/syselement/packertron-vms/compare/v0.15.0...v0.15.1) (2026-05-21)


### Bug Fixes

* rename kali hcl placeholder ([f8cd177](https://github.com/syselement/packertron-vms/commit/f8cd1776437b238ac9e284daf9fc20812594826d))



# [0.15.0](https://github.com/syselement/packertron-vms/compare/v0.14.0...v0.15.0) (2026-05-08)


### Features

* add Ubuntu 26.04 Desktop build scripts and cloud-init configuration; fixed doc ([9d84a84](https://github.com/syselement/packertron-vms/commit/9d84a84d9590151ba07d9e5d30a2c70e569438fc))



# [0.14.0](https://github.com/syselement/packertron-vms/compare/v0.13.0...v0.14.0) (2026-03-01)


### Features

* enhance provisioning scripts with logging and new package installations ([bc2a5fe](https://github.com/syselement/packertron-vms/commit/bc2a5fe1240dc6a05ead452ed538627896b46e9b))



# [0.13.0](https://github.com/syselement/packertron-vms/compare/v0.12.0...v0.13.0) (2026-03-01)


### Features

* update dash-to-dock settings to hide trash and modify GNOME favorites ([0b959db](https://github.com/syselement/packertron-vms/commit/0b959dbaf40fecb25e56d7414ff05f7d38c23936))



# [0.12.0](https://github.com/syselement/packertron-vms/compare/v0.11.0...v0.12.0) (2026-03-01)


### Features

* update dash-to-dock settings and add reboot prompt after customization ([239009f](https://github.com/syselement/packertron-vms/commit/239009f2befc1f20916006cffb7d69c501ff4a63))



# [0.11.0](https://github.com/syselement/packertron-vms/compare/v0.10.0...v0.11.0) (2026-03-01)


### Features

* update system customization script to install additional tools and enhance logging ([34177b8](https://github.com/syselement/packertron-vms/commit/34177b8765a37bebdc709fb687906c1649984848))



# [0.10.0](https://github.com/syselement/packertron-vms/compare/v0.9.0...v0.10.0) (2026-03-01)


### Features

* enhance JetBrainsMono Nerd Font installation and configure Terminator ([015f33e](https://github.com/syselement/packertron-vms/commit/015f33e30218956a66c4f40f9628369ffc0f944f))



# [0.9.0](https://github.com/syselement/packertron-vms/compare/v0.8.0...v0.9.0) (2026-03-01)


### Features

* add installation of JetBrainsMono Nerd Font and unzip package ([f88728e](https://github.com/syselement/packertron-vms/commit/f88728ecd95e2948ac1196bdd588067d041d2d20))



# [0.8.0](https://github.com/syselement/packertron-vms/compare/v0.7.0...v0.8.0) (2026-03-01)


### Features

* updated 03-customize-system.sh script for Ubuntu Desktop ([7b760e8](https://github.com/syselement/packertron-vms/commit/7b760e8d5f4aff2b0d95bdec08ab60e4c61dafe0))



# [0.7.0](https://github.com/syselement/packertron-vms/compare/v0.6.0...v0.7.0) (2025-12-23)


### Features

* streamline provisioning script for Ubuntu 24.04 with improved error handling and repository configurations ([9a90615](https://github.com/syselement/packertron-vms/commit/9a906159be9d8513cdf52e6f2679d0004655eb0e))



# [0.6.0](https://github.com/syselement/packertron-vms/compare/v0.5.0...v0.6.0) (2025-12-23)


### Features

* update provisioning for Ubuntu 24.04 and Windows Server 2025 with enhanced scripts and error handling ([fafcf70](https://github.com/syselement/packertron-vms/commit/fafcf701d723cd98d1ff053bfa37ac1c46b13473))



# [0.5.0](https://github.com/syselement/packertron-vms/compare/v0.4.2...v0.5.0) (2025-12-22)


### Features

* enhance Windows Server 2025 provisioning with updated scripts and README ([18dd0c6](https://github.com/syselement/packertron-vms/commit/18dd0c685b4c616e75ec7ff4b711aa8363cdab48))



## [0.4.2](https://github.com/syselement/packertron-vms/compare/v0.4.1...v0.4.2) (2025-12-22)


### Bug Fixes

* Refactor provisioning scripts and cleanup: update .gitignore, remove obsolete scripts, and enhance system update and cleanup processes ([b044d77](https://github.com/syselement/packertron-vms/commit/b044d7796a785ed161dabb7485aa83245a24ae03))



## [0.4.1](https://github.com/syselement/packertron-vms/compare/v0.4.0...v0.4.1) (2025-08-16)


### Bug Fixes

* dir names changed ([de8a201](https://github.com/syselement/packertron-vms/commit/de8a201e4d3f51a9e0a6969a885bb031afe3c849))



# [0.4.0](https://github.com/syselement/packertron-vms/compare/v0.3.0...v0.4.0) (2025-08-16)


### Features

* Ubuntu Desktop placeholder files [TO DO] ([0b081a1](https://github.com/syselement/packertron-vms/commit/0b081a19840d988a09d0c4a02eb47f009c6a534b))



# [0.3.0](https://github.com/syselement/packertron-vms/compare/v0.2.0...v0.3.0) (2025-08-16)


### Bug Fixes

* CI quick fix ([1682164](https://github.com/syselement/packertron-vms/commit/1682164425d860d69f77b3e3dab9333bc42002bb))


### Features

* Kali hcl placeholder files ([c85f4a7](https://github.com/syselement/packertron-vms/commit/c85f4a795075c7742f71c5a348e2c8f9441a1d96))



# [0.2.0](https://github.com/syselement/packertron-vms/compare/v0.1.0...v0.2.0) (2025-08-16)


### Bug Fixes

* **readme:** Update README.md ([985cf1a](https://github.com/syselement/packertron-vms/commit/985cf1ae4cccf84559b67a6198930fac65dd98f5))
* version ([49aa470](https://github.com/syselement/packertron-vms/commit/49aa470f85cd5ba44edeba1aa68a31c754801df4))
* win server 2025 ([d8e9832](https://github.com/syselement/packertron-vms/commit/d8e9832c04340d57de2e0d6a583646359b781864))


### Features

* version.yaml new file ([5ce57b9](https://github.com/syselement/packertron-vms/commit/5ce57b96bdbf4bac32683c17dcf2858f4fa88b1b))
* Win fixed VM parameters ([0145556](https://github.com/syselement/packertron-vms/commit/0145556ab77a01174ceb0586e66debfb42e60b7a))



# [0.1.0](https://github.com/syselement/packertron-vms/compare/1a8ada6e141ae642c5903d54def8072449bb885b...v0.1.0) (2025-02-04)


### Features

* **packaging:** add configurations for Windows Server 2025 provisioning and deploy ([1a8ada6](https://github.com/syselement/packertron-vms/commit/1a8ada6e141ae642c5903d54def8072449bb885b))



