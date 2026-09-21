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



