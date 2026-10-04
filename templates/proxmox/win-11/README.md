# Windows 11 - Proxmox template

Windows 11 Enterprise. Shared Windows behaviour is in [WINDOWS.md](../WINDOWS.md); staging and building in [README.md](../README.md).

> **Status: built and cloned on a real node** (25H2, ~1 hour, most of it Windows Update). The clone came up with its hostname, account, password and SSH key from the cloud-init drive, `C:` grown to the disk, dark mode, and fully patched.

| | |
| --- | --- |
| `vm_id` / `template_name` | 80311 / `win-11-template` |
| Release | Windows 11 Enterprise 25H2, evaluation |
| `iso_file` | `local:iso/26200.6584.250915-1905.25h2_ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso` |
| SHA-256 | `a61adeab895ef5a4db436e0a7011c92a2ff17bb0357f58b13bbc4062e535e7b9` |
| `image_index` | 1, Enterprise Evaluation |
| virtio-win folder / Proxmox `os` | `w11` / `win11` |
| Account on a clone | `Administrator`, renamed to `syselement` |

Windows 11 needs Secure Boot, a TPM 2.0, 4 GB of memory and a 64 GB disk, and the template has exactly that. It would also encrypt `C:` on its own, which sysprep refuses; the answer file switches that off.
