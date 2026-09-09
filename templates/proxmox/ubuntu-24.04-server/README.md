# Ubuntu Server 24.04 - Proxmox template

Builds an Ubuntu Server 24.04 LTS template on Proxmox VE from the official ISO, driven by the autoinstall seed in `http/`.

> **Status: validates, not yet built.** `packer validate` passes in CI, but this
> template has not been run against a real node. Expect to adjust
> `proxmox_node`, `storage_pool` and `network_bridge` for your host.

## Where the install media comes from

By default Packer downloads `var.iso`, verifies it against the distribution's signed `SHA256SUMS`, and uploads it. The plugin stores it under a SHA1 of the URL rather than its real name, and ignores `iso_target_path`; `iso_download_pve` would fix the name but needs the API token's role to carry `Sys.AccessNetwork`, which is a wider privilege than building a template should require.

To keep the name readable, stage the ISO on the node once:

```bash
# on the node
cd /var/lib/vz/template/iso
wget https://releases.ubuntu.com/noble/ubuntu-24.04.4-live-server-amd64.iso
sha256sum -c <(curl -sL https://releases.ubuntu.com/noble/SHA256SUMS | grep live-server-amd64)
```

Then pass `-var 'iso_file=...'`, as in [Build](#build) below. `iso_file` and `iso_url` are mutually exclusive, and an empty string counts as unset, so setting one switches the build off the other entirely.

## Firmware

**q35 + OVMF (UEFI)**, with a 4MB EFI variable disk on the same pool as the system disk.

- q35 rather than the i440fx Proxmox defaults to: i440fx models a 1996 chipset with no native PCIe, and pairing it with UEFI works but is the odd combination.
- Proxmox still exposes `ide2` on q35, which is where the cloud-init drive lands, so nothing about the clone-time model changes.

- `pre_enrolled_keys` is `false`.
- With it true the firmware ships Microsoft's Secure Boot keys already enrolled, which only helps if everything that ever boots the clone is signed for them - and it is the usual cause of a template that installs cleanly and then refuses to boot once cloned.

- OVMF posts more slowly than SeaBIOS.
- If the installer never starts and the console sits on the firmware splash, the boot keystrokes were typed too early: raise `boot_wait`, which is a variable for exactly this reason (`-var 'boot_wait=20s'`), rather than editing the template.

## The template is thin, on purpose

It installs the base OS, `qemu-guest-agent`, and leaves cloud-init able to run again. It does **not** bake in the tooling from `02-provision-system.sh` or `03-customize-system.sh`.

- Those run per VM at first boot instead, so a clone created months from now picks up the current scripts rather than whatever was current when the template was baked.
- Only `00-update-system.sh` (guest agent) and `01-cleanup-system.sh` (sealing) run during the build.

## Settings and credentials

Two places, split by whether the value is a secret:

| What | Where | Committed |
| --- | --- | --- |
| API token, SSH password | environment, `PKR_VAR_*` | never |
| Node name, storage pools, bridge | `../proxmox.pkrvars.hcl` | no, only `.example` |
| ISO URL, checksum, sizing, `vm_id` | this template's `.pkr.hcl` defaults | yes |

The node settings are shared by every template under `templates/proxmox/`, so they are written once:

```bash
cd templates/proxmox
cp proxmox.pkrvars.hcl.example proxmox.pkrvars.hcl   # gitignored
$EDITOR proxmox.pkrvars.hcl
```

Create a Proxmox API **token** scoped to template creation - not a root password - and export it. The role needs `VM.GuestAgent.Audit` alongside the allocate and config privileges: Packer asks the guest agent for the VM's address, and without that privilege the lookup returns nothing, so the build waits out `ssh_timeout` having never contacted the VM. On PVE 8 it replaced the older `VM.Monitor`, which no longer exists.

```bash
export PKR_VAR_proxmox_api_token_id="packer@pve!templates"
export PKR_VAR_proxmox_api_token_secret="..."
```

### The build logs in over the SSH agent

- `http/user-data` sets `allow-pw: false`, so subiquity writes `PasswordAuthentication no` and the installed system rejects passwords.
- The build authenticates with the one ed25519 key the seed authorises, through the agent - Packer's communicator cannot unlock a passphrase-protected key file, and `ssh_private_key_file` fails validation outright on one.

So before building, the key must be loaded:

```bash
ssh-add -l          # must list the key whose public half is in http/user-data
ssh-add ~/.ssh/id_ed25519
```

If it is not, the build reaches the installed system, fails every authentication attempt, and sits out the full 30-minute `ssh_timeout` before failing with nothing useful in the log.

For an unattended runner, generate a dedicated passphrase-less build key, authorise it in the seed, and use `ssh_private_key_file` instead of the agent.

Keep `insecure_skip_tls_verify` at its default of `false` unless the node presents a self-signed certificate you have deliberately chosen to accept.

## Build

Packer downloads the ISO and uploads it to the node:

```bash
cd templates/proxmox/ubuntu-24.04-server
packer init .
packer validate -var-file=../proxmox.pkrvars.hcl .
packer build    -var-file=../proxmox.pkrvars.hcl .
```

Or build from an ISO already on the node, which transfers nothing and keeps the name you gave it - see [Where the install media comes from](#where-the-install-media-comes-from) for how to stage it:

```bash
packer build -var-file=../proxmox.pkrvars.hcl -var 'iso_file=local:iso/ubuntu-24.04.4-live-server-amd64.iso' .
```

Per-build overrides, which are the knobs a first build usually needs:

| Override | When |
| --- | --- |
| `-var 'boot_wait=20s'` | installer never starts; OVMF was still posting when the keys were typed |
| `-var 'http_bind_address=<your LAN IP>'` | installer starts but cannot fetch the seed; Packer picked a `docker0`/`virbr0` address the VM cannot reach |
| `-var 'vm_id=80025'` | the VMID is already taken on the node |
| `-var 'iso_file=local:iso/<name>.iso'` | use an ISO already on the node instead of downloading one |
| `-var 'ssh_host=<VM IP>'` | stuck on "Waiting for SSH" with no connection reaching the VM; the token's role lacks `VM.GuestAgent.Audit`, so the guest-agent address lookup returns nothing |

`vm_id` must be free on the node. Without `iso_file`, the ISO is downloaded to `iso_storage_pool` on the first run.

## What the build does before the template is sealed

`scripts/ubuntu/01-cleanup-system.sh` does most of it: it truncates the machine-id, clears `/var/lib/cloud`, and runs `cloud-init clean`, which also takes subiquity's own drop-ins with it. A clone is then a new cloud-init instance.

`../seal-for-clone.sh` runs last and is deliberately small - only what `01` cannot do, because `01` is shared with the VMware templates where cloud-init stays pinned:

| Step | Why |
| --- | --- |
| write `99-pve.cfg` | `datasource_list` narrows a clone to the drive Proxmox attaches, and `manage_etc_hosts` keeps `/etc/hosts` in step with the hostname. It cannot be written at install time: that would drop `None` from `datasource_list`, and `None` is the datasource carrying the seed's `ssh:` section |
| verify cloud-init is unpinned | `01` already removed subiquity's drop-ins; this only checks it happened. A leftover that pins the datasource or disables networking gives clones no hostname, user, key or address, and nothing in any log to explain it |
| remove `/etc/ssh/ssh_host_*` | otherwise every clone answers with the same fingerprint. A one-shot unit regenerates them before `ssh.service` on the clone |
| remove `/var/lib/systemd/random-seed` | systemd credits it to the entropy pool at boot; shipping one means every clone starts from the same seed |

It lives one directory up because every Proxmox template needs the same seal, and it is a script rather than an inline block so `shellcheck` and `shfmt` see it - `scripts/check-templates.sh shell` runs both.

## Why the clone gets its hostname into /etc/hosts

- Ubuntu ships `cloud.cfg` with `preserve_hostname: false` and the `update_etc_hosts` module enabled, but leaves `manage_etc_hosts` unset - and with it unset the module does nothing at all.
- Ubuntu's `nsswitch.conf` `hosts:` line carries no `myhostname` entry either.
- So a clone is renamed while `/etc/hosts` still names the template, the new name resolves nowhere, and every `sudo` prints `unable to resolve host`.

- The seed writes `manage_etc_hosts: localhost` into `99-pve.cfg`, which fixes only the `127.0.1.1` line.
- `true` would rewrite the whole file from a template on every boot and discard anything added by hand.

## Why the seed deletes two cloud-init files

- Subiquity pins cloud-init to the installer's own NoCloud seed and disables its networking, via `99-installer.cfg` and `subiquity-disable-cloudinit-networking.cfg`.
- Left in place, a clone ignores the cloud-init drive Proxmox attaches to it: no per-VM hostname, user, SSH key or network is ever applied, and the whole clone-and-configure model silently does nothing while appearing to succeed.

The seed removes both and writes `99-pve.cfg` with `datasource_list: [ NoCloud, ConfigDrive ]`.

## Verify before pushing

```bash
../../../scripts/check-templates.sh          # fmt, validate, cloud-init schema
```
