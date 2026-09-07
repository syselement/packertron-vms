# Ubuntu Server 24.04 - Proxmox template

Builds an Ubuntu Server 24.04 LTS template on Proxmox VE from the official ISO,
driven by the autoinstall seed in `http/`.

> **Status: validates, not yet built.** `packer validate` passes in CI, but this
> template has not been run against a real node. Expect to adjust
> `proxmox_node`, `storage_pool` and `network_bridge` for your host.

## Firmware

**q35 + OVMF (UEFI)**, with a 4MB EFI variable disk on the same pool as the
system disk.

q35 rather than the i440fx Proxmox defaults to: i440fx models a 1996 chipset
with no native PCIe, and pairing it with UEFI works but is the odd combination.
Proxmox still exposes `ide2` on q35, which is where the cloud-init drive lands,
so nothing about the clone-time model changes.

`pre_enrolled_keys` is `false`. With it true the firmware ships Microsoft's
Secure Boot keys already enrolled, which only helps if everything that ever
boots the clone is signed for them - and it is the usual cause of a template
that installs cleanly and then refuses to boot once cloned.

OVMF posts more slowly than SeaBIOS. If the installer never starts and the
console sits on the firmware splash, the boot keystrokes were typed too early:
raise `boot_wait`, which is a variable for exactly this reason
(`-var 'boot_wait=20s'`), rather than editing the template.

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

Per-build overrides still work: `-var 'vm_id=9100'`, `-var 'boot_wait=20s'`.

`vm_id` must be free on the node, and the ISO is downloaded to
`iso_storage_pool` on the first run.

## What the build removes before the template is sealed

`scripts/ubuntu/01-cleanup-system.sh` truncates the machine-id and clears
`/var/lib/cloud`, so a clone is a new cloud-init instance. `../seal-for-clone.sh`
then runs last and removes what only matters when an image is cloned:

| Removed | Why |
| --- | --- |
| `/etc/ssh/ssh_host_*` | otherwise every clone answers with the same fingerprint. A one-shot unit regenerates them before `ssh.service` on the clone |
| `/etc/netplan/00-installer-config*.yaml` | subiquity pins it to the *build* VM's MAC, so on a clone it matches nothing and configures nothing - a decoy that hides cloud-init being the only thing wiring up the NIC |
| `/var/lib/systemd/random-seed` | otherwise every clone starts from the same seed |

It also **verifies** that the seed's cloud-init unpinning actually happened,
and fails the build if it did not. The seed does that with `rm -f`, which
cannot report a miss: the networking drop-in ships as
`00-subiquity-disable-cloudinit-networking.cfg`, and an `rm` written for the
bare name matches nothing, exits 0, and leaves `network: {config: disabled}`
in place. The build would succeed and every clone would come up with no
address, no hostname and nothing in the logs to say why.

It lives one directory up because every Proxmox template needs the same seal,
and it is a script rather than an inline block so `shellcheck` and `shfmt` see
it - `scripts/check-templates.sh shell` runs both.

## Why the clone gets its hostname into /etc/hosts

Ubuntu ships `cloud.cfg` with `preserve_hostname: false` and the
`update_etc_hosts` module enabled, but leaves `manage_etc_hosts` unset - and
with it unset the module does nothing at all. Ubuntu's `nsswitch.conf` `hosts:`
line carries no `myhostname` entry either. So a clone is renamed while
`/etc/hosts` still names the template, the new name resolves nowhere, and every
`sudo` prints `unable to resolve host`.

The seed writes `manage_etc_hosts: localhost` into `99-pve.cfg`, which fixes
only the `127.0.1.1` line. `true` would rewrite the whole file from a template
on every boot and discard anything added by hand.

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
