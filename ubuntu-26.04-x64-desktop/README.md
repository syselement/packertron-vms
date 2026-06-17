# NOT WORKING - https://bugs.launchpad.net/subiquity/+bug/2150197

# Ubuntu 26.04 Desktop (VMware + Packer)

Repeatable **Ubuntu 26.04 Desktop** build for VMware Workstation with optional Vagrant box export.

---

## Requirements

- Windows host with VMware Workstation
- Packer >= 1.8 (HCL2)
- Disk space + BIOS virtualization
- Optional: Vagrant + vagrant-vmware-desktop plugin

---

## Quick build

```bash
git clone https://github.com/syselement/packertron-vms.git
```

### Prepare for Cloud-init/Unattended installation:

- Create empty `http/meta-data` and customize `http/user-data`

This is how it works:

- The build serves the local `http/` directory through Packer’s temporary HTTP server (using `http_directory`). `${path.root}` points to the directory where the Packer template is run from

- During boot, the installer is given `autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/`
  - Packer serves the local `http/` directory, then Ubuntu autoinstall downloads `user-data` and `meta-data` from Packer’s temporary HTTP server as its NoCloud seed configuration

### Build the template box

```powershell
cd .\packertron-vms\ubuntu-26.04-x64-desktop
packer init .
packer validate ubuntu-26.04-x64-desktop.pkr.hcl
packer build .
```

- Artifacts land in `output/`
  - e.g. `ubuntu-26.04-x64-desktop-template-vmware.box` - size ~5GB

- Build time: ~15 minutes (hardware dependent)

---

## Use in VMware Workstation

1. Extract the .box:

```powershell
mkdir tmp && tar -xf output/ubuntu-26.04-x64-desktop-template-vmware.box -C tmp
```

2. Open `tmp/ubuntu-26.04-x64-desktop-template.vmx` in Workstation (File -> Open) and power it on
    - The `.vmxf`, `.nvram`, `.vmdk`, and `.vmsd` sit alongside it

3. Optional VMX tweaks (before first boot):
    - `displayname = "Ubuntu-Desktop-26"`
    - `hgfs.linkrootshare = "FALSE"`
    - `hgfs.maprootshare = "FALSE"`
    - `isolation.tools.hgfs.disable = "TRUE"`
    - `sound.present = "TRUE"`
    - `sound.startconnected = "TRUE"`

4. Alternative: create a new VM and point the disk to `tmp/disk.vmdk`

---

## Use with Vagrant (VMware provider)

This project defines **two machines** in the Vagrantfile

- Both machines share identical VMware hardware configuration (RAM, CPU, NAT networking, nested virtualization)
- Adjust VMX memory/CPU settings in the Vagrantfile if needed

| Machine       | Purpose                     | Provisioned             |
| ------------- | --------------------------- | ----------------------- |
| `base`        | Clean reference VM from box | ❌ No                    |
| `provisioned` | Workstation-ready desktop   | ✅ Yes (first boot only) |

Start **both** machines

```powershell
vagrant up --provider=vmware_desktop
```

Start only **base**

```powershell
vagrant up base
```

Start only **provisioned**

```powershell
vagrant up provisioned
```

Vagrant/VMware will manage VMX adjustments during `vagrant up`; no manual VMX edits needed when using Vagrant.

- The workstation layer (Docker, OpenTofu, Packer CLI, Ansible, VS Code, hygiene) lives in one idempotent script executed only on the first `vagrant up` - `../scripts/ubuntu/02-provision-system.sh`
- Re-run with `--provision` to re-provision the VM (Vagrant runs provisioners once by default)

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

---

## Customize

- `ubuntu-26.04-x64-desktop.pkr` - contains the Packer variables with some defaults
- `ubuntu-26.04-x64-desktop.auto.pkrvars.hcl` - auto-loaded Packer Build variables
- Override variables at build time with `-var "key=value"`
- `../scripts/` are used
  - during Packer build for preseed/install automation
  - during Vagrant provisioning

---

## Troubleshoot

- SSH issues: check VMware network mode (NAT vs bridged) and VMware services
- Import failures: confirm Workstation version and BIOS virtualization enabled
- Run `packer build -debug` for an interactive troubleshooting VM

---

## Files of note

- `Vagrantfile`
- `ubuntu-26.04-x64-desktop.pkr.hcl`
- `ubuntu-26.04-x64-desktop.auto.pkrvars.hcl`
- `output/`
- `../scripts/`

---

