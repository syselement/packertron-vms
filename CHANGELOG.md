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



