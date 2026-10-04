# Windows 10 - Proxmox template

Windows 10 Enterprise. Shared Windows behaviour is in [WINDOWS.md](../WINDOWS.md); staging and building in [README.md](../README.md).

> **Status: built and cloned on a real node** (22H2, patched to the October 2025 update, ~1 hour).

| | |
| --- | --- |
| `vm_id` / `template_name` | 80310 / `win-10-template` |
| Release | Windows 10 Enterprise 22H2, evaluation |
| `iso_file` | `local:iso/19045.2006.220908-0225.22h2_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso` |
| SHA-256 | `ef7312733a9f5d7d51cfa04ac497671995674ca5e1058d5164d6028f0938d668` |
| `image_index` | 1, Enterprise Evaluation |
| virtio-win folder / Proxmox `os` | `w10` / `win10` |
| Account on a clone | `Administrator`, renamed to `syselement` |

Windows 10 needs neither Secure Boot nor a TPM, but the template keeps both so the three Windows templates stay identical everywhere else. Other Windows 10 media works with `-var 'iso_file=local:iso/<name>.iso'`, `image_index` set to the edition you want, and `product_key` if it needs one.
