# Ubuntu Server 26.04 - Proxmox template

Builds an Ubuntu Server 26.04 LTS template on Proxmox VE from the official ISO, driven by the autoinstall seed in `http/`.

> **Status: validates, not yet built.** `packer validate` passes in CI and the ISO URL and checksum source were checked against `releases.ubuntu.com`, but this template has not been run against a real node. The 24.04 template beside it has, and the two differ only in the release they install.

This is the 24.04 template with the release changed. Everything about firmware, credentials, the SSH-agent login, the seal, and the clone-time model is identical and documented once, in [`../ubuntu-24.04-server/README.md`](../ubuntu-24.04-server/README.md). Read that first; this file only records what differs.

## What differs from 24.04

| Setting | 24.04 | 26.04 |
| --- | --- | --- |
| ISO | `ubuntu-24.04.4-live-server-amd64.iso` | `ubuntu-26.04.1-live-server-amd64.iso` |
| Release directory | `noble` | `resolute` |
| `vm_id` | `80024` | `80026` |
| `template_name` | `ubuntu-24.04-server-template` | `ubuntu-26.04-server-template` |

Both take their checksum from the distribution's signed `SHA256SUMS` in the codename directory, so the value keeps matching when the point release is bumped.

## Build

```bash
cd templates/proxmox/ubuntu-26.04-server
ssh-add -l                                            # the seed's key must be loaded
export PKR_VAR_proxmox_api_token_id="packer@pve!templates"
export PKR_VAR_proxmox_api_token_secret="..."
packer init .
packer validate -var-file=../proxmox.pkrvars.hcl .
packer build    -var-file=../proxmox.pkrvars.hcl .
```

Or from an ISO already staged on the node, which transfers nothing and keeps the name you gave it:

```bash
packer build -var-file=../proxmox.pkrvars.hcl -var 'iso_file=local:iso/ubuntu-26.04.1-live-server-amd64.iso' .
```

The per-build overrides are the same as 24.04's, and `vm_id` must be free on the node.

## Verify before pushing

```bash
../../../scripts/check-templates.sh proxmox
```
