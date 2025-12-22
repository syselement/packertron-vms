# Ubuntu 24.04 Desktop (VMware + Packer)

Repeatable Ubuntu 24.04 desktop build for VMware Workstation with optional Vagrant box export.

## Requirements
- Windows host with VMware Workstation
- Packer >= 1.8 (HCL2)
- Disk space + BIOS virtualization
- Optional: Vagrant + vagrant-vmware-desktop/vagrant-vmware-workstation

## Quick build
```powershell
cd ubuntu-24.04-x64-desktop
packer init .
packer validate ./ubuntu-24.04-x64-desktop.pkr.hcl
packer build .
```
Artifacts land in `output/` (e.g., `ubuntu-24.04-x64-desktop-template-vmware.box`).

## Use in VMware Workstation
1) Extract the .box: `mkdir tmp && tar -xf output/<box>.box -C tmp`
2) Open `tmp/ubuntu-24.04-x64-desktop-template.vmx` in Workstation (File -> Open) and power it on. The `.vmxf`, `.nvram`, `.vmdk`, and `.vmsd` sit alongside it.
3) Optional VMX tweaks (before first boot):
   - `displayname = "Ubuntu-Desktop-24"`
   - `hgfs.linkrootshare = "FALSE"`
   - `hgfs.maprootshare = "FALSE"`
   - `isolation.tools.hgfs.disable = "TRUE"`
   - `sound.present = "TRUE"`
   - `sound.startconnected = "TRUE"`
4) Alternative: create a new VM and point the disk to `tmp/disk.vmdk`.

## Use with Vagrant (VMware provider)
```powershell
vagrant up --provider=vmware_desktop
```
Vagrant/VMware will manage VMX adjustments during `vagrant up`; no manual VMX edits needed when using Vagrant.

## Customize
- Final/default Packer variables: `ubuntu-24.04-x64-desktop.auto.pkrvars.hcl` (auto-loaded). Override via `-var "key=value"`.
- `scripts/` are used during the Packer build for preseed/install automation and for final Ubuntu Desktop provisioning after VMware import.

## Troubleshoot fast
- SSH issues: check VMware network mode (NAT vs bridged) and VMware services.
- Import failures: confirm Workstation version and BIOS virtualization.
- Run `packer build -debug` for an interactive troubleshooting VM.

Files of note: `ubuntu-24.04-x64-desktop.pkr.hcl`, `ubuntu-24.04-x64-desktop.auto.pkrvars.hcl`, `output/`.
