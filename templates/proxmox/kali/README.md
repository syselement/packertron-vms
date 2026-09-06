# Kali Linux (Proxmox)

**Status: stub. Validates, does not build.**

`http/kali.preseed` does not exist, so the `boot_command` in
`kali.pkr.hcl` has nothing to fetch. Writing that seed is the work that
turns this directory into a buildable template; until then it is kept
green by CI so that the HCL cannot rot.

Adapted from [mttaggart/seclab](https://github.com/mttaggart/seclab)
(`Packer/kali/config.pkr.hcl`). The pristine upstream copy is kept in
`tmp/upstream-originals/kali/` for comparison.

## Layout

- `kali.pkr.hcl` - builder, variables and build block

Node settings come from the shared `../proxmox.pkrvars.hcl`, the same file
every Proxmox template here uses. Kali had its own copy of them until the
hypervisor split; the variable names now match
[ubuntu-24.04-server](../ubuntu-24.04-server/README.md), so one file feeds
both.

## Credentials

From the environment, never from a file here:

```bash
export PKR_VAR_proxmox_api_token_id="packer@pve!templates"
export PKR_VAR_proxmox_api_token_secret="..."
export PKR_VAR_ssh_password="..."
```

The upstream template read these from a KeePass database two directories
up, which is not part of this repository - that is why it could not even
be validated before. See [SECURITY.md](../../../SECURITY.md).

## Checks

```bash
../../../scripts/check-templates.sh proxmox
```
