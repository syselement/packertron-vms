# VMware Workstation templates

Packer builds each template in VMware Workstation; the desktops and Windows Server are packaged as Vagrant boxes, the servers as plain VMs. Unlike the thin [Proxmox templates](../proxmox/README.md), these images carry their provisioning: the servers run `02` at build time, and each box's Vagrantfile provisions the machines it defines.

| Template | Result | Provisioning | Notes |
| --- | --- | --- | --- |
| [`ubuntu-24.04-server`](ubuntu-24.04-server/README.md) | VM in `output/` | `00`, `02`, `01` at build time | |
| [`ubuntu-26.04-server`](ubuntu-26.04-server/README.md) | VM in `output/` | `00`, `02`, `01` at build time | |
| [`ubuntu-24.04-desktop`](ubuntu-24.04-desktop/README.md) | Vagrant box | `00`, `01` at build time; `02`, `03` on the `provisioned` machine | |
| [`ubuntu-26.04-desktop`](ubuntu-26.04-desktop/README.md) | Vagrant box | as 24.04 | **unverified** - see its README |
| [`win-srv-2025`](win-srv-2025/README.md) | Vagrant box | the [Proxmox Windows chain](../proxmox/WINDOWS.md#the-build), then `install_utils.ps1` through Vagrant | |

## Requirements

- **VMware Workstation Pro 17 or later**, from [Broadcom's download portal](https://support.broadcom.com/group/ecx/productdownloads?subfamily=VMware%20Workstation%20Pro&freeDownloads=true) - it needs an account, so no script installs it.
- **Packer 1.12 or later, and Vagrant**, with the [Vagrant VMware Utility](https://developer.hashicorp.com/vagrant/install/vmware) and the `vagrant-vmware-desktop` plugin, installed as the user who runs Vagrant.
- **On Windows**, [`scripts/install-requirements.ps1`](../../scripts/install-requirements.ps1) reports and installs the rest, through winget or Chocolatey.

```bash
powershell -ExecutionPolicy Bypass -File scripts/install-requirements.ps1            # report what is missing
powershell -ExecutionPolicy Bypass -File scripts/install-requirements.ps1 -Install   # install it
vagrant plugin install vagrant-vmware-desktop
```

If the VMware Utility installer cannot find Workstation 26H1 ([hashicorp/vagrant-vmware-desktop#177](https://github.com/hashicorp/vagrant-vmware-desktop/issues/177)), create the registry keys it looks for, from an elevated PowerShell, then rerun its MSI:

```powershell
$src = "HKLM:\SOFTWARE\VMware, Inc.\VMware Workstation"
$dst = "HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMware Workstation"
New-Item -Path $dst -Force | Out-Null
Set-ItemProperty -Path (Split-Path $dst) -Name "Core" -Value "VMware Workstation"
$props = Get-ItemProperty -Path $src
foreach ($name in "InstallPath", "InstallPath64", "ProductCode", "ProductVersion", "Version") { if ($props.$name) { Set-ItemProperty -Path $dst -Name $name -Value $props.$name } }
if (-not $props.InstallPath64) { Set-ItemProperty -Path $dst -Name "InstallPath64" -Value $props.InstallPath }
Get-Service vagrant-vmware-utility   # should be Running
```

## Build

The Linux seeds authorize your public key, which comes from the environment - nothing is committed in its place:

```bash
export PKR_VAR_ssh_authorized_key="$(cat ~/.ssh/id_ed25519.pub)"   # PowerShell: $env:PKR_VAR_ssh_authorized_key = Get-Content ~/.ssh/id_ed25519.pub
cd templates/vmware/<template>
packer init .
packer build .                                                       # -debug for an interactive troubleshooting VM
```

Each template takes its ISO from a URL, or from a local path in its `.auto.pkrvars.hcl` (`C:/ISO/...`) when that file exists, and checks it against the pinned checksum either way. The seeds' console password is the published one for `packer` - see [SECURITY.md](../../SECURITY.md).

## Use a box

With Vagrant, from the template's directory - Vagrant manages the VMX and runs each machine's provisioners once:

```bash
vagrant up                 # every machine the Vagrantfile defines; vagrant up <machine> for one
vagrant up --provision     # provision an existing machine again
vagrant halt
vagrant destroy -f
```

Without Vagrant, extract the box and open its `.vmx` in Workstation (File > Open):

```bash
mkdir tmp && tar -xf output/<box>.box -C tmp
```

## When the build stops

| Symptom | Look at |
| --- | --- |
| Packer cannot find VMware | Workstation installed and its services running |
| "Waiting for SSH" never ends | the VM's network mode (NAT) and the VMware NAT service; for Linux, that the seed got `PKR_VAR_ssh_authorized_key` |
| ISO checksum mismatch | the local ISO in `.auto.pkrvars.hcl` is another release than the checksum names |
| Vagrant cannot drive VMware | `vagrant plugin repair`, and the `vagrant-vmware-utility` service |

## Verify

```bash
scripts/check-templates.sh vmware   # fmt, validate and the seeds of these templates
```
