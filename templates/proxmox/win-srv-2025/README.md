# Windows Server 2025 - Proxmox template

Windows Server 2025 Standard with the Desktop Experience. Shared Windows behaviour is in [WINDOWS.md](../WINDOWS.md); staging and building in [README.md](../README.md).

> **Status: built and cloned on a real node** (patched to 26100.33438, ~1.5 hours).

| | |
| --- | --- |
| `vm_id` / `template_name` | 80325 / `win-srv-2025-template` |
| Release | Windows Server 2025 Standard, evaluation, Desktop Experience |
| `iso_file` | `local:iso/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso` |
| SHA-256 | `d0ef4502e350e3c6c53c15b1b3020d38a5ded011bf04998e950720ac8579b23d` |
| `image_index` | 2, Standard Evaluation (Desktop Experience) |
| virtio-win folder / Proxmox `os` | `2k25` / `win11`, which covers Server 2022 and 2025 |
| Account on a clone | `Administrator`, kept - set `username = "Administrator"` in its `deploy/` entry |

The ISO, its checksum and `image_index` are the ones [`vmware/win-srv-2025`](../../vmware/win-srv-2025/README.md) builds from. OpenSSH Server ships with Server 2025, so the first logon only switches it on.

**The clone's password must meet Server's complexity rule**: three of upper case, lower case, digits and symbols. cloudbase-init sets the password through the normal account API, so a simple one such as `packer` is refused and `Administrator` keeps a random one - the SSH key still works, which makes it easy to miss. The build can use `packer` only because Setup's answer file is exempt. Use a complex one in `TF_VAR_password`, or on an existing clone:

```bash
qm set <vmid> --cipassword 'Lab-Passw0rd!'   # on the node; applied at the next reboot
```

The new password gives the cloud-init drive a new identity, so cloudbase-init applies it as a new instance.

---
