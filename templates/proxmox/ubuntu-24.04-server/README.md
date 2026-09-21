# Ubuntu Server 24.04 - Proxmox template

Builds an Ubuntu Server 24.04 LTS template on Proxmox VE from the official ISO, driven by the autoinstall seed in `http/`.

> **Status: built and verified on a real node** (Proxmox VE, q35/OVMF, 24.04.4, build time ~5 minutes). Two full clones were checked: SSH host keys, machine-id and the systemd random seed all differ between them; hostname, `/etc/hosts`, netplan and DHCP are correct on each; cloud-init reports `done` from `DataSourceNoCloud [seed=cmdline,/dev/sr0]`. Adjust `proxmox_node`, `storage_pool` and `network_bridge` for your host.

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

- Only `00-update-system.sh` (guest agent) and `01-cleanup-system.sh` (sealing) run during the build.
- A clone runs them at first boot **only if it asks to**, by shipping `/etc/packertron/firstboot.conf` with a `STEPS` line - see [`scripts/ubuntu/README.md`](../../../scripts/ubuntu/README.md). A clone that ships no such file stays as thin as the template.
- Because they run from a fresh checkout, a clone created months from now picks up the current scripts rather than whatever was current when the template was baked.

## Why the guest agent is installed on first boot, not by the installer

The seed puts `qemu-guest-agent` in its `user-data:` section rather than the autoinstall `packages:` list. The first real 26.04.1 build showed why: subiquity installs `packages:` against `/target` while the ISO is its only APT source, and `qemu-guest-agent` is not on the server ISO - the live installer sees it in `universe`, the target does not, and the install fails with APT exit `100`. The 24.04 ISO happens to carry the package, but relying on that is what broke.

It cannot simply move to `00-update-system.sh` either: the agent is how Packer learns the VM's address, so a build with no agent sits on "Waiting for SSH" and never runs a provisioner. `user-data:` breaks that loop - cloud-init applies it on the first boot of the installed system, where the real `ubuntu.sources` with `universe` is in place. It is the same path that applies the `ssh:` section. The unit is static and normally started by a udev rule when the virtio port appears, which was before the package existed, so `runcmd` starts it explicitly.

The cost is one `apt-get update` and one install on the first boot before Packer connects. All three Proxmox Ubuntu templates use this route.

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
| write `99-hide-cidata.rules` | the cloud-init drive stays attached for life - it is the channel for later changes - and on a desktop udisks would otherwise mount it and show a "cidata" CD in the file manager. The udev rule hides it from udisks only; cloud-init reads the device directly |
| remove `/etc/ssh/ssh_host_*` | otherwise every clone answers with the same fingerprint. cloud-init's `cc_ssh` regenerates them on the clone's first boot, before `sshd` starts |
| remove `/var/lib/systemd/random-seed` | systemd credits it to the entropy pool at boot; shipping one means every clone starts from the same seed |

It lives one directory up because every Proxmox template needs the same seal, and it is a script rather than an inline block so `shellcheck` and `shfmt` see it - `scripts/check-templates.sh shell` runs both.

## Why the clone gets its hostname into /etc/hosts

- Ubuntu ships `cloud.cfg` with `preserve_hostname: false` and the `update_etc_hosts` module enabled, but leaves `manage_etc_hosts` unset - and with it unset the module does nothing at all.
- Ubuntu's `nsswitch.conf` `hosts:` line carries no `myhostname` entry either.
- So a clone is renamed while `/etc/hosts` still names the template, the new name resolves nowhere, and every `sudo` prints `unable to resolve host`.

- The seed writes `manage_etc_hosts: localhost` into `99-pve.cfg`, which fixes only the `127.0.1.1` line.
- `true` would rewrite the whole file from a template on every boot and discard anything added by hand.

## Why subiquity's cloud-init files are removed at the end, not during the install

- Subiquity pins cloud-init to the installer's own NoCloud seed and disables its networking, via `99-installer.cfg` and `subiquity-disable-cloudinit-networking.cfg`.
- Left in place, a clone ignores the cloud-init drive Proxmox attaches to it: no per-VM hostname, user, SSH key or network is ever applied, and the whole clone-and-configure model silently does nothing while appearing to succeed.

They are removed by `01-cleanup-system.sh`'s `cloud-init clean`, and `../seal-for-clone.sh` writes `99-pve.cfg` afterwards and fails the build if anything survived.

Removing them from the seed's `late-commands` instead looks equivalent and is not, which cost two failed builds to establish:

- `99-installer.cfg` is what applies the seed's `ssh:` section on first boot, so deleting it at install time leaves the machine with no `authorized_keys` and password authentication still on, and the build hangs on "Waiting for SSH".
- Writing `99-pve.cfg` at install time sets `datasource_list` before the first boot, which drops `None` from it - and `None` is the datasource that carries `99-installer.cfg`, so cloud-init finds no datasource and applies nothing at all.

## Verify before pushing

```bash
../../../scripts/check-templates.sh          # fmt, validate, cloud-init schema
```
