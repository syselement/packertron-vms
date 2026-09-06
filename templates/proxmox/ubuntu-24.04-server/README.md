# Ubuntu Server 24.04 - Proxmox template

Builds an Ubuntu Server 24.04 LTS template on Proxmox VE from the official ISO,
driven by the autoinstall seed in `http/`.

> **Status: validates, not yet built.** `packer validate` passes in CI, but this
> template has not been run against a real node. Expect to adjust
> `proxmox_node`, `storage_pool` and `network_bridge` for your host.

## The template is thin, on purpose

It installs the base OS, `qemu-guest-agent`, and leaves cloud-init able to run
again. It does **not** bake in the tooling from `02-provision-system.sh` or
`03-customize-system.sh`.

Those run per VM at first boot instead, so a clone created months from now picks
up the current scripts rather than whatever was current when the template was
baked. Only `00-update-system.sh` (guest agent) and `01-cleanup-system.sh`
(sealing) run during the build.

## Settings and credentials

Two places, split by whether the value is a secret:

| What | Where | Committed |
| --- | --- | --- |
| API token, SSH password | environment, `PKR_VAR_*` | never |
| Node name, storage pools, bridge | `../proxmox.pkrvars.hcl` | no, only `.example` |
| ISO URL, checksum, sizing, `vm_id` | this template's `.pkr.hcl` defaults | yes |

The node settings are shared by every template under `templates/proxmox/`, so
they are written once:

```bash
cd templates/proxmox
cp proxmox.pkrvars.hcl.example proxmox.pkrvars.hcl   # gitignored
$EDITOR proxmox.pkrvars.hcl
```

Create a Proxmox API **token** scoped to template creation - not a root
password - and export it:

```bash
export PKR_VAR_proxmox_api_token_id="packer@pve!templates"
export PKR_VAR_proxmox_api_token_secret="..."
export PKR_VAR_ssh_password="..."
```

Keep `insecure_skip_tls_verify` at its default of `false` unless the node
presents a self-signed certificate you have deliberately chosen to accept.

## Build

```bash
cd templates/proxmox/ubuntu-24.04-server
packer init .
packer validate -var-file=../proxmox.pkrvars.hcl .
packer build    -var-file=../proxmox.pkrvars.hcl .
```

Per-build overrides still work: `-var 'vm_id=9100'`.

`vm_id` must be free on the node, and the ISO is downloaded to
`iso_storage_pool` on the first run.

## What the build removes before the template is sealed

`scripts/ubuntu/01-cleanup-system.sh` truncates the machine-id and clears
`/var/lib/cloud`, so a clone is a new cloud-init instance. `../seal-for-clone.sh`
then runs last and removes what only matters when an image is cloned:

| Removed | Why |
| --- | --- |
| `/etc/ssh/ssh_host_*` | otherwise every clone answers with the same fingerprint. A one-shot unit regenerates them before `ssh.service` on the clone |
| `/etc/netplan/00-installer-config*.yaml` | subiquity wrote it naming the *build* VM's interface; cloud-init writes `50-cloud-init.yaml` on the clone |
| `/var/lib/systemd/random-seed` | otherwise every clone starts from the same seed |

It lives one directory up because every Proxmox template needs the same seal,
and it is a script rather than an inline block so `shellcheck` and `shfmt` see
it - `scripts/check-templates.sh shell` runs both.

## Why the seed deletes two cloud-init files

Subiquity pins cloud-init to the installer's own NoCloud seed and disables its
networking, via `99-installer.cfg` and
`subiquity-disable-cloudinit-networking.cfg`. Left in place, a clone ignores the
cloud-init drive Proxmox attaches to it: no per-VM hostname, user, SSH key or
network is ever applied, and the whole clone-and-configure model silently does
nothing while appearing to succeed.

The seed removes both and writes `99-pve.cfg` with
`datasource_list: [ NoCloud, ConfigDrive ]`.

## Verify before pushing

```bash
../../../scripts/check-templates.sh          # fmt, validate, cloud-init schema
```
