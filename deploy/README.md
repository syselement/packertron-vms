# deploy - Proxmox template to running VM

One OpenTofu module that clones Packer-built templates, configures them through cloud-init, boots them, and optionally tells each one to provision itself at first boot. VMs are entries in a `vms` map: one entry brings up one machine, a whole-lab map brings up all of them from one apply.

It is deliberately the smallest useful layer - a flat map, no composition, no remote state. Fleet-wide homelab infrastructure belongs in its own repository, which can consume this one as a module by git ref.

## Requirements

| What | Where it comes from |
| --- | --- |
| API token | `PROXMOX_VE_API_TOKEN`, from the environment - see [Dedicated role](../templates/proxmox/README.md#dedicated-role) |
| State passphrase | `TF_VAR_state_passphrase`, from the environment, 16 characters or more |
| Endpoint, node, storage, keys | a `*.tfvars` of your own, gitignored - start from an `.example` |
| Templates | built by [`templates/proxmox/`](../templates/proxmox/README.md) - IDs below |
| First-boot provisioning only | root SSH to the node, and a storage with the `snippets` content type |

## Usage

```bash
cd deploy
cp deploy.tfvars.example srv-01.tfvars          # *.tfvars is gitignored
export PROXMOX_VE_API_TOKEN='automation@pve!deploy=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
export TF_VAR_state_passphrase='...'            # encrypts the state and saved plans
tofu init
tofu workspace new srv-01                       # one state per tfvars
tofu apply -var-file=srv-01.tfvars
tofu output ipv4_addresses                      # empty until the guest agent starts
```

**One state per tfvars.** Applying a single-VM file in the workspace of a whole-lab file destroys every VM the lab file created and the single one does not mention. Give each tfvars its own workspace.

| Example | Holds |
| --- | --- |
| `deploy.tfvars.example` | the smallest thing that works: node settings and one server |
| `lab.tfvars.example` | the whole lab: static address, linked clone, VLAN, workstation, Kali, Windows 10, 11 and Server 2025 |
| `kali.tfvars.example` | Kali alone, with the settings it needs |

## The `vms` map

The key is the VM's name and hostname - Windows truncates a hostname past 15 characters. Only `template_vm_id` is required; the rest falls back to a 2 core, 2048 MB, 32 GB clone on DHCP.

| Field | Default | Notes |
| --- | --- | --- |
| `template_vm_id` | - | the template to clone |
| `os` | `"ubuntu"` | `ubuntu`, `kali` or `windows`; decides what `provisioning_steps` accepts |
| `cores`, `memory`, `disk_size` | 2, 2048, 32 | `disk_size` must be at least the template's: Proxmox grows a cloned disk but never shrinks one |
| `full_clone` | `true` | a linked clone is faster and smaller, but keeps the template undeletable |
| `bridge`, `vlan_id` | unset | set either for another network; unset, the clone keeps the template's NIC (virtio on `vmbr0`) |
| `ipv4_address`, `ipv4_gateway` | `"dhcp"` | a static address needs both, as `192.168.1.201/24` and `192.168.1.1` |
| `username` | `var.username` | Server 2025 keeps `Administrator` |
| `vm_id` | next free | |
| `tags` | `["opentofu"]` | |
| `provisioning_steps` | `""` | see [First-boot provisioning](#first-boot-provisioning) |
| `vendor_data_file_id` | `""` | an existing snippet instead of the uploaded one - Ubuntu only |

| Template | `template_vm_id` | `os` | Minimum `disk_size` |
| --- | --- | --- | --- |
| Ubuntu Server 24.04 / 26.04 | 80024 / 80026 | `ubuntu` | 32 |
| Ubuntu Desktop 26.04 | 80126 | `ubuntu` | 64 |
| Kali | 80200 | `kali` | 50 |
| Windows 10 / 11 / Server 2025 | 80310 / 80311 / 80325 | `windows` | 64 |

## Console access

cloud-init locks the account's password when it gets none, so by default a clone is reachable only by SSH key - the right posture for a server. Pass a password through the environment when one is needed:

```bash
export TF_VAR_password='...'
```

- **Desktops and Kali need one.** GDM, Xfce and the Proxmox console have no key login, so a desktop created without one cannot be logged into. cloud-init applies it on the first boot only; for a clone already created without one, SSH in with the key and run `sudo passwd <user>`.
- **Windows needs one for the console.** Server 2025 refuses a password without three of upper case, lower case, digits and symbols, and keeps a random one. Proxmox writes a Windows password to the cloud-init drive in plain text - see [`WINDOWS.md`](../templates/proxmox/WINDOWS.md#how-a-clone-configures-itself).

## First-boot provisioning

`provisioning_steps` is empty by default: the clone boots as exactly the template, and nothing is fetched or uploaded. Setting it is per VM, so one entry can ask for the full toolchain while the rest stay bare.

| `os` | `provisioning_steps` | The clone runs | Follow it |
| --- | --- | --- | --- |
| `ubuntu` | `"02"` | baseline and developer tooling | `sudo tail -f /var/log/packertron-bootstrap.log` |
| `ubuntu` | `"02,03"` | the full toolchain, GNOME and shell configuration; reboots when done | same |
| `windows` | `"utils"` | [`install_utils.ps1`](../scripts/windows/install_utils.ps1): Chocolatey, its utilities, UniGetUI | `C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\cloudbase-init.log` |
| `kali` | - | nothing: Kali carries its toolset in the image | |

Any other combination fails at plan time.

- **Ubuntu** clones get a cloud-config as **vendor-data**, which cloud-init merges with the user-data Proxmox generates (hostname, account, keys, network); user-data would replace it, and the clone would come up with no account. It installs `git` and the [`packertron-firstboot`](../scripts/ubuntu/README.md#firstboot) service, which runs the steps from a fresh checkout, so a VM created a year from now gets the current scripts. `sudo tail -f /var/log/packertron-firstboot.log` shows the checkout itself.
- **Windows** clones get **user-data**, the only kind cloudbase-init reads: a cloud-config part with the hostname, then the script, run once as LocalSystem. The password and keys still come from the `meta_data.json` Proxmox generates. The script is embedded at apply time from this checkout, not fetched on the clone.

Changing `provisioning_steps` on an existing VM rewrites its cloud-init drive. On Windows, cloudbase-init then treats the clone as a new instance and sets the password again: to the one on the drive, or a random one when there is none.

**The snippet goes over SSH.** Proxmox has no API for writing snippets, so the provider uploads them as root over SSH (`providers.tf`), and only when an entry asks for provisioning. The storage named by `snippet_datastore_id` must carry the `snippets` content type, which `local` does not by default:

```bash
pvesm set local --content backup,iso,vztmpl,snippets   # on the node; --content replaces the list, so keep what was there
```

To avoid SSH, place an Ubuntu snippet on the node by hand and name it with `vendor_data_file_id` (generate it with `tofu console` and `local.firstboot_vendor_data`), or leave `provisioning_steps` empty and run [`90-bootstrap-baremetal.sh`](../scripts/ubuntu/README.md) on the VM yourself.

## State encryption

The state and saved plans hold the clone password and the node layout, so the module encrypts both with a key derived from `TF_VAR_state_passphrase` (OpenTofu 1.8 or later). A plaintext state is refused rather than read.

A state written before encryption is migrated once per workspace, by one apply with an unencrypted fallback:

```bash
export TF_ENCRYPTION='method "unencrypted" "migration" {}
state {
  method = method.aes_gcm.state
  fallback {
    method = method.unencrypted.migration
  }
}
plan {
  method = method.aes_gcm.state
  fallback {
    method = method.unencrypted.migration
  }
}'
tofu workspace select lab && tofu apply -var-file=lab.tfvars    # repeat per workspace
unset TF_ENCRYPTION
for f in terraform.tfstate* terraform.tfstate.d/*/terraform.tfstate*; do jq -e 'has("encrypted_data")' "$f" >/dev/null || echo "plaintext: $f"; done
```

The last line lists any state still in plaintext. A `.backup` written before the migration stays plaintext until the next change overwrites it - delete it once the workspace's apply has succeeded. Losing the passphrase loses the state, not the VMs: they can be imported again.

## What this does not do

- No LXC: Packer cannot build a Proxmox container template, so containers are not part of this pipeline.
- No fleet management, inventory or DNS - that is the separate homelab repository's job.
