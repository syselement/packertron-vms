# Scripts

The provisioners the templates run, the node and repository tooling, and the checks.

| Path | What | Docs |
| --- | --- | --- |
| [`ubuntu/`](ubuntu/) | the Ubuntu provisioning chain `00`-`03`, the bare-metal bootstrap, the first-boot runner, the autoinstall seeds, and their Bats suite | [ubuntu/README.md](ubuntu/README.md) |
| [`windows/`](windows/) | the Windows build chain, its cloudbase-init configuration, and `install_utils.ps1` | [below](#windows) |
| [`proxmox/`](proxmox/) | `prepare-node.sh` and `stage-isos.sh`, with their Bats suites | [templates/proxmox/README.md](../templates/proxmox/README.md) |
| [`check-templates.sh`](check-templates.sh) | every check CI runs, locally | [below](#checks) |
| [`check-pins.sh`](check-pins.sh) | the pins Dependabot cannot see, against upstream | [below](#pins) |
| [`install-requirements.sh`](install-requirements.sh), [`.ps1`](install-requirements.ps1) | the host tooling, reported or installed; Linux and Windows | [below](#checks) |
| [`sync-firstboot.sh`](sync-firstboot.sh) | re-embeds `ubuntu/firstboot/` into every seed that carries it | [ubuntu/README.md](ubuntu/README.md#firstboot) |

## Checks

```bash
scripts/install-requirements.sh             # what is missing; changes nothing
scripts/install-requirements.sh install     # install it (apt)
scripts/check-templates.sh                  # every check CI runs
scripts/check-templates.sh docs links       # some of them
git config core.hooksPath .githooks         # optional: the fast ones before each commit
```

| Scope | Checks |
| --- | --- |
| `packer` | `packer fmt` and `validate` on every template; `proxmox` or `vmware` first narrows it |
| `seeds`, `preseeds` | cloud-init schema and debconf syntax for every seed, and that no seed commits a public key |
| `unattend` | the Windows answer files are well-formed XML |
| `powershell` | every PowerShell script parses, with zero PSScriptAnalyzer findings |
| `shell` | ShellCheck and shfmt on the Bash outside `ubuntu/`, the git hooks included |
| `ubuntu` | the `ubuntu/` lint and Bats suite, as `ubuntu-static-checks.yml` runs them |
| `bats` | the other Bats suites, such as `proxmox/tests/` |
| `tofu` | `tofu fmt` and `validate` on `deploy/` |
| `docs`, `markdown`, `links` | one sentence per line, markdownlint, and every relative link and anchor |
| `yaml`, `workflows` | yamllint, and actionlint and zizmor on the workflows |
| `matrix`, `firstboot` | the CI matrix matches the templates on disk; the seeds embed the current first-boot files |
| `secrets` | gitleaks on the git history |

A linter the Ubuntu archive does not package - pwsh, actionlint, zizmor, markdownlint-cli2, gitleaks - is skipped where missing, and `install-requirements.sh` says where to get it. CI installs pinned versions and sets `CHECKS_REQUIRE_TOOLS=1`, which turns a missing tool into a failure.

A machine provisioned by [`ubuntu/03-customize-system.sh`](ubuntu/README.md) already has every tool above.

CI installs the latest Packer and OpenTofu on every run, so keep the local ones current too - `install-requirements.sh install` takes Packer from HashiCorp's APT repository.

## Pins

```bash
GH_TOKEN="$(gh auth token)" scripts/check-pins.sh   # the token lifts GitHub's anonymous rate limit
```

It compares each ISO, virtio-win, cloudbase-init, the Packer plugins, the OpenTofu provider and the CI linters with their latest upstream release. The Watch pins workflow runs it every Monday and keeps one issue open while anything is behind.

## Windows

| Script | Runs in | Does |
| --- | --- | --- |
| `00_firstlogon.ps1` | Proxmox build, first logon | virtio-win guest tools, RDP, OpenSSH Server |
| `01_vmware_tools.ps1` | VMware build | VMware Tools |
| `09_system_settings.ps1` | both builds | Edge first run off, diagnostic data lowest, High performance, password never expires |
| `10_wait_for_servicing.ps1` | both builds | waits for servicing to go idle, reports a pending reboot |
| `11_cloudbase_init.ps1` | Proxmox build | installs and configures cloudbase-init, verified, left Manual |
| `03_cleanup.ps1`, `12_sysprep.ps1` | both builds, last | clears caches, then generalizes; refuses a pending reboot |
| `packer_shutdown.bat` | VMware build | blocks SSH, shuts the generalized image down |
| `04_startup.cmd`, `04_startup.ps1` | VMware box, first boot | per-user settings, opens SSH again |
| `install_utils.ps1` | `deploy/` first boot, VMware Vagrant, bare metal | winget, then its utilities, UniGetUI, PowerShell 7 and the TightVNC server among them, then Chocolatey for tools winget lacks, and a Public Desktop shortcut to WinUtil |
| `setup-windows.ps1`, `baremetal/autounattend.xml` | a real machine, from a USB stick | the templates' settings, a taskbar without search, Task View, news, Meet Now and pins, RDP and OpenSSH Server on request, then `install_utils.ps1` - [below](#bare-metal) |

The order and the reasons are in [templates/proxmox/WINDOWS.md](../templates/proxmox/WINDOWS.md#the-build).

### Bare metal

To install Windows 10 or 11 on a real machine with the same settings and utilities, write the Microsoft ISO to a USB stick, copy three files beside it, and boot from it. Setup runs on its own and installs Windows 10 Pro with Microsoft's generic key, unactivated until you enter a real one. **It wipes disk 0 without asking: disconnect every other disk first.** OOBE still asks for the local account, so the stick holds no password.

**From Windows**, write the ISO with [Rufus](https://rufus.ie) and untick its "Customize Windows installation" options, which write their own `autounattend.xml`. Then copy `windows/baremetal/autounattend.xml`, `windows/setup-windows.ps1` and `windows/install_utils.ps1` to the root of the stick.

**From Ubuntu**, build the stick by hand: one FAT32 partition, which every UEFI firmware boots, with `install.wim` split under FAT32's 4 GB file limit - Setup reads the `.swm` parts as one image.

```bash
sudo apt-get install wimtools                       # wimlib-imagex, which splits install.wim
lsblk                                               # find the stick; DEV below is erased whole
ISO=~/Downloads/Win11_25H2_English_x64.iso
DEV=/dev/sdX
sudo umount "$DEV"?* || true                        # the desktop automounts the stick; "not mounted" is fine
sudo wipefs -a "$DEV"
sudo parted -s "$DEV" mklabel gpt mkpart WINUSB fat32 1MiB 100%
sudo mkfs.vfat -F 32 -n WINUSB "${DEV}1"
mkdir -p /tmp/winiso /tmp/winusb
sudo mount -o loop,ro "$ISO" /tmp/winiso
sudo mount "${DEV}1" /tmp/winusb
sudo rsync -r --info=progress2 --exclude sources/install.wim /tmp/winiso/ /tmp/winusb/
sudo wimlib-imagex split /tmp/winiso/sources/install.wim /tmp/winusb/sources/install.swm 3800   # skip when the ISO has install.esd instead
sudo cp scripts/windows/baremetal/autounattend.xml scripts/windows/setup-windows.ps1 scripts/windows/install_utils.ps1 /tmp/winusb/
sudo umount /tmp/winusb /tmp/winiso                 # waits until the stick is written
```

Boot the machine from the stick in UEFI mode, install, log in, open PowerShell as administrator, and run the script from the stick:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File D:\setup-windows.ps1                       # D: is the stick
powershell -NoProfile -ExecutionPolicy Bypass -File D:\setup-windows.ps1 -EnableRemoteAccess   # also RDP, and SSH on private networks
```

It needs the network, and it installs the TightVNC server along with the rest - set its password, as [SECURITY.md](../SECURITY.md#windows) says. Run Windows Update afterwards.
