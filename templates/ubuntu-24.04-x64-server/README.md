# Ubuntu Server 24.04 (VMware Workstation)

Builds a VMware Workstation VM with the `vmware-iso` builder.

The full provisioning chain runs at build time - `00-update-system.sh`, then
the whole `scripts/ubuntu/` bundle is staged, then `02` and `01`. The result is
a fat image: everything is baked in, nothing is deferred to first boot. That is
the opposite of the Proxmox template beside it
([ubuntu-24.04-x64-server-proxmox](../ubuntu-24.04-x64-server-proxmox/README.md)),
which stays thin and provisions per VM.

Adapted from
[ynlamy/packer-ubuntuserver24_04](https://github.com/ynlamy/packer-ubuntuserver24_04)
(GPLv3). The pristine upstream copy is in `tmp/upstream-originals/`.

## Layout

- `ubuntu-24.04-x64-server.pkr.hcl` - builder, variables and build block
- `http/user-data`, `http/meta-data` - the autoinstall seed served to subiquity

## Build

```bash
cd templates/ubuntu-24.04-x64-server
packer init .
packer validate .
packer build .
```

## Credentials

The seed commits a SHA-512 crypt hash whose plaintext is documented next to it,
so every machine built from it starts with the same console password. Change it
on anything reachable by anyone else - see [SECURITY.md](../../SECURITY.md).

## Checks

```bash
../../scripts/check-templates.sh
```
