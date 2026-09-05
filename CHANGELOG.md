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



