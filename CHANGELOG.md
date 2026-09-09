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



