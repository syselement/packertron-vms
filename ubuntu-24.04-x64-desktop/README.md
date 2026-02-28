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
packer validate ubuntu-24.04-x64-desktop.pkr.hcl
packer build .
```

- Artifacts land in `output/`
    - e.g. `ubuntu-24.04-x64-desktop-template-vmware.box`

- Build time: ~15 minutes (hardware dependent)

## Use in VMware Workstation

1. Extract the .box:

```powershell
mkdir tmp && tar -xf output/ubuntu-24.04-x64-desktop-template-vmware.box -C tmp
```

2. Open `tmp/ubuntu-24.04-x64-desktop-template.vmx` in Workstation (File -> Open) and power it on.
    - The `.vmxf`, `.nvram`, `.vmdk`, and `.vmsd` sit alongside it.

3. Optional VMX tweaks (before first boot):
    - `displayname = "Ubuntu-Desktop-24"`
    - `hgfs.linkrootshare = "FALSE"`
    - `hgfs.maprootshare = "FALSE"`
    - `isolation.tools.hgfs.disable = "TRUE"`
    - `sound.present = "TRUE"`
    - `sound.startconnected = "TRUE"`

1. Alternative: create a new VM and point the disk to `tmp/disk.vmdk`.

## Use with Vagrant (VMware provider)

This project defines **two machines** in the Vagrantfile

- Both machines share identical VMware hardware configuration (RAM, CPU, NAT networking, nested virtualization).
- Adjust VMX memory/CPU settings in the Vagrantfile if needed.

| Machine       | Purpose                     | Provisioned             |
| ------------- | --------------------------- | ----------------------- |
| `base`        | Clean reference VM from box | ❌ No                    |
| `provisioned` | Workstation-ready desktop   | ✅ Yes (first boot only) |

**Start both machines**

```powershell
vagrant up --provider=vmware_desktop
```

**Start only base**

```powershell
vagrant up base
```

**Start only provisioned**

```powershell
vagrant up provisioned
```

Vagrant/VMware will manage VMX adjustments during `vagrant up`; no manual VMX edits needed when using Vagrant.

- The workstation layer (Docker, OpenTofu, Packer CLI, Ansible, VS Code, hygiene) lives in one idempotent script executed only on the first `vagrant up` - `scripts/02-provision-system.sh`
- Re-run with `--provision` to re-provision the VM (Vagrant runs provisioners once by default).

```powershell
# Re-Provision VM
vagrant up provisioned --provision
```

### VM lifecycle

Each machine has an independent lifecycle.

```powershell
# Stop VMs
vagrant halt # all VMs
vagrant halt base
vagrant halt provisioned

# Start VMs
vagrant up # all VMs
vagrant up base
vagrant up provisioned

# Destroy one VM
vagrant destroy base -f

# Destroy all VMs
vagrant destroy -f
```

## Customize

- `ubuntu-24.04-x64-desktop.pkr` - contains the Packer variables with some defaults.
- `ubuntu-24.04-x64-desktop.auto.pkrvars.hcl` - auto-loaded Packer Build variables
- `scripts/` are used
   - during Packer build for preseed/install automation
   - during Vagrant provisioning

## Troubleshoot fast

- SSH issues: check VMware network mode (NAT vs bridged) and VMware services.
- Import failures: confirm Workstation version and BIOS virtualization enabled.
- Run `packer build -debug` for an interactive troubleshooting VM.

## Files of note

- `Vagrantfile`
- `ubuntu-24.04-x64-desktop.pkr.hcl`
- `ubuntu-24.04-x64-desktop.auto.pkrvars.hcl`
- `scripts/`
- `output/`

---

