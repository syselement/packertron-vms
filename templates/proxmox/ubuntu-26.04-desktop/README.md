# Ubuntu Desktop 26.04 - Proxmox template

Builds an Ubuntu Desktop 26.04 LTS template on Proxmox VE from the official desktop ISO, driven by the autoinstall seed in `http/`.

> **Status: validates, not yet built.** `packer validate` passes in CI and the ISO URL and checksum source were checked against `releases.ubuntu.com`, but this template has not been run against a real node.

Firmware, credentials, the SSH-agent login, the seal, and the clone-time model are identical to every Proxmox template here and are documented once, in [`../ubuntu-24.04-server/README.md`](../ubuntu-24.04-server/README.md). This file records only what a desktop image does differently.

## What differs from the server templates

| Setting | Server | Desktop |
| --- | --- | --- |
| Install source | `ubuntu-server` | `ubuntu-desktop` |
| ISO | `ubuntu-26.04.1-live-server-amd64.iso` | `ubuntu-26.04.1-desktop-amd64.iso` |
| `cores` / `memory` | 2 / 2048 | 4 / 8192 |
| `disk_size` | 30G | 64G |
| `ssh_timeout` | 30m | 60m |
| Display | Proxmox default | `std`, 32MB |
| `vm_id` | `80026` | `80126` |

The longer timeout is not padding: the desktop ISO installs a full GNOME image and fetches language packs, so it takes considerably longer to reach a login prompt than the server ISO. The 16MB of video memory Proxmox defaults to is enough to boot GNOME and not much more.

## This template is still thin

It installs the desktop base and `qemu-guest-agent` and stops there. It does **not** bake in `02-provision-system.sh` or `03-customize-system.sh`, even though a desktop is the variant those scripts do the most work on.

That is what makes one template serve both cases: a plain desktop VM clones from it untouched, and a workstation asks for the full toolchain at clone time by setting `provisioning_steps` in [`deploy/`](../../../deploy/README.md). Baking the tooling in would remove the first option and freeze the toolchain at the date the template was built.

## Build

```bash
cd templates/proxmox/ubuntu-26.04-desktop
ssh-add -l                                            # the seed's key must be loaded
export PKR_VAR_proxmox_api_token_id="packer@pve!templates"
export PKR_VAR_proxmox_api_token_secret="..."
packer init .
packer validate -var-file=../proxmox.pkrvars.hcl .
packer build    -var-file=../proxmox.pkrvars.hcl .
```

Expect this build to take considerably longer than the server one. The per-build overrides are the same as 24.04's, and `vm_id` must be free on the node.

## Verify before pushing

```bash
../../../scripts/check-templates.sh proxmox
```
