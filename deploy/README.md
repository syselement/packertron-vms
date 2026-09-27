# deploy - Proxmox template to running VM

One OpenTofu module that clones Packer-built templates, configures them through cloud-init, and boots them. Optionally it also tells a clone to provision itself at first boot.

VMs are described in a `vms` map, one entry per machine, and the module creates one VM per entry. A tfvars holding a single entry brings up one machine; a tfvars holding the whole lab brings up all of them from one apply.

This is deliberately the smallest useful layer: a flat map of VMs, no composition, no remote state, no modules of its own. Fleet-wide homelab infrastructure belongs in a separate repository, which can consume this one as a module by git ref. What lives here is the last step of this repository's own pipeline: **ISO to template to VM**.

## What it needs

| Thing | Where it comes from |
| --- | --- |
| API token | `PROXMOX_VE_API_TOKEN` in the environment, never a file |
| Endpoint, node, storage | `deploy.tfvars`, which is gitignored |
| Which templates to clone | `vms.<name>.template_vm_id` - `80024`/`80026` server, `80126` desktop, `80200` Kali |
| First-boot files | read directly from `../scripts/ubuntu/firstboot/` |

The token needs the privileges to clone, configure and start a VM. It does **not** need `Sys.AccessNetwork`.

## Usage

```bash
cd deploy
cp deploy.tfvars.example deploy.tfvars
$EDITOR deploy.tfvars

export PROXMOX_VE_API_TOKEN='automation@pve!deploy=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
tofu init
tofu plan  -var-file=deploy.tfvars
tofu apply -var-file=deploy.tfvars
```

Only `template_vm_id` is required per entry. Everything else falls back to a plain 2 core / 2048 MB / 32 GB server on DHCP, so the smallest useful VM is three lines:

```hcl
vms = {
  "srv-01" = { template_vm_id = 80026 }
}
```

`disk_size` must be at least the template's own size - Proxmox can grow a cloned disk but never shrink one - so the desktop needs `64` and Kali `50`.

To bring up several machines from one map, put them all in one file and give it its own workspace:

```bash
tofu workspace new lab 2>/dev/null || tofu workspace select lab
tofu plan  -var-file=lab.tfvars     # one VM per entry, plus a snippet per provisioned VM
tofu apply -var-file=lab.tfvars

tofu output ipv4_addresses          # keyed by VM name; empty until the guest agent starts
```

**One state per tfvars.** A file listing the whole lab and a file listing one VM are both valid, but they must not share a workspace: applying the single-VM file in the lab's workspace destroys everything the lab file created and the map no longer mentions. Give each its own with `tofu workspace new <name>`.

## Console access

cloud-init locks the account's password whenever it configures a user without one, so by default a clone is reachable **only by SSH key** - `packer`, the template's password, stops working on the console. For a server that is the intended posture. Pass a password through the environment rather than a file when one is wanted:

```bash
export TF_VAR_password='...'
tofu apply -var-file=deploy.tfvars
```

**For a desktop clone this is required, not optional.** GDM and the Proxmox console have no key login, so a desktop created without a password cannot be logged into at all. cloud-init applies the password on the instance's first boot only, so exporting it afterwards and re-applying does not unlock an existing VM - for that, SSH in with the key and run `sudo passwd syselement`.

## Example profiles

| File | Holds |
| --- | --- |
| `deploy.tfvars.example` | the smallest thing that works: node settings and one server |
| `lab.tfvars.example` | the whole lab in one map - static address, linked clone, workstation, Kali |
| `kali.tfvars.example` | the Kali template alone, with the settings it needs that the others do not |

## Provisioning is opt-in, and that is the whole design

`provisioning_steps` is empty by default, and an empty value means the clone boots and does nothing: no repository is fetched, no snippet is uploaded, nothing is installed. That is what keeps one thin template usable for a throwaway server and for a full workstation. It is set per VM, so one entry in the map can ask for the full toolchain while the rest stay bare.

Set it to ask for more:

| Value | Result |
| --- | --- |
| `""` | nothing. The clone is exactly the template |
| `"02"` | baseline and developer tooling |
| `"02,03"` | the full toolchain, GNOME preferences and shell configuration - a desktop clone that matches the bare-metal machine |

**Not on Kali.** Those scripts are Ubuntu's, and `ubuntu-context.sh` refuses to run on anything else - a Kali clone that asks for them gets a `packertron-firstboot.service` that fails and retries every five minutes forever. Kali carries its toolset in the image instead.

The steps are the scripts in [`../scripts/ubuntu/`](../scripts/ubuntu/), run on the clone by the same `packertron-firstboot` service the autoinstall seeds use. They run from a fresh checkout of the repository, so a VM created a year from now gets the current scripts rather than whatever was current when its template was baked.

Provisioning runs in the background and finishes long after `tofu apply` returns. Follow it on the VM:

```bash
sudo tail -f /var/log/packertron-firstboot.log     # fetching the repository
sudo tail -f /var/log/packertron-bootstrap.log     # the steps themselves
```

`03` reboots the machine when it finishes.

## The one awkward requirement: SSH to the node

Proxmox has no API for writing snippets, so the provider uploads the first-boot vendor-data over SSH. That is why `providers.tf` carries an `ssh` block, and it applies **only** when `provisioning_steps` is non-empty - a plain clone never touches it.

Two ways to avoid it, if SSH access to the node is not something you want to grant:

1. Place the snippet on the node once by hand and name it with `vendor_data_file_id`, for example `vendor_data_file_id = "local:snippets/firstboot.yaml"`. Generate its content with `tofu console` and `local.firstboot_vendor_data`, or write the three files by hand.
2. Leave `provisioning_steps` empty and run `90-bootstrap-baremetal.sh` on the VM yourself afterwards.

The storage named by `snippet_datastore_id` must also have the **snippets** content type enabled. `local` does not by default; the provider then warns and the upload fails with `tee: /var/lib/vz/snippets/...: No such file or directory`. Enable it once on the node:

```bash
pvesm set local --content backup,iso,vztmpl,snippets   # --content replaces the list; keep what was there
```

Or under Datacenter -> Storage -> `local` -> Edit -> Content. Destroying a VM removes its snippet through the API, which is why the token's role needs `Datastore.Allocate`.

## Why vendor-data and not user-data

Proxmox generates the cloud-init user-data that carries the hostname, account, SSH keys and network configuration. Supplying our own user-data replaces all of it, and the clone comes up with no account and no address. The first-boot files go in vendor-data instead, which cloud-init merges alongside what Proxmox generated rather than in place of it.

## What this does not do

- No LXC. Packer cannot build a Proxmox LXC template - the plugin has `iso` and `clone` builders and nothing else - so containers are not part of this pipeline.
- No fleet management, inventory, DNS, or multi-VM composition. That is the separate homelab repository's job.
