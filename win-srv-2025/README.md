# Windows Server 2025 (VMware + Packer)

Repeatable Windows Server 2025 build for VMware Workstation with optional Vagrant box export.

## Requirements
- Windows host with VMware Workstation
- Packer >= 1.8 (HCL2)
- Disk space + BIOS virtualization
- Optional: Vagrant + vagrant-vmware-desktop/vagrant-vmware-workstation

## Quick build
```powershell
cd win-srv-2025
packer init .
packer validate .\winserver2025.pkr.hcl
packer build .
```
Artifacts land in `output/` (e.g., `*.box` from the Vagrant post-processor).

## Variables
- Final/default Packer variables: `winserver2025.auto.pkrvars.hcl` (auto-loaded).
- Override at build time with `-var "key=value"`.
- Update `iso_url` and `iso_checksum` to match your ISO.

## Use in VMware Workstation
1) Extract the .box: `mkdir tmp && tar -xf output/<box>.box -C tmp`
2) Open `tmp/Win2025VM.vmx` in Workstation (File -> Open) and power it on. The `.vmxf`, `.nvram`, `.vmdk`, and `.vmsd` sit alongside it.
3) Optional VMX tweaks (before first boot):
   - `displayname = "Win2025VM"`
   - `hgfs.linkrootshare = "FALSE"`
   - `hgfs.maprootshare = "FALSE"`
   - `isolation.tools.hgfs.disable = "TRUE"`
4) Alternative: create a new VM and point the disk to `tmp/disk.vmdk`.

## Use with Vagrant (VMware provider)
```powershell
vagrant up --provider=vmware_desktop
```

## Troubleshoot fast
- Build hangs on updates: wait for `scripts/02_win_updates.ps1` to complete and check the Packer log output.
- ISO issues: verify the checksum and that the URL is reachable.
- Run `packer build -debug` for an interactive troubleshooting VM.

Files of note: `winserver2025.pkr.hcl`, `winserver2025.auto.pkrvars.hcl`, `scripts/`, `output/`, `config/`.
