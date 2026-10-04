# Templates

One directory per template, grouped by hypervisor: `<hypervisor>/<os>`. That pair is the template's name everywhere - on disk, in the CI matrix and in `scripts/check-templates.sh` output.

| Hypervisor | Templates | Images are | Docs |
| --- | --- | --- | --- |
| Proxmox VE - the primary target | Ubuntu Server 24.04 and 26.04, Ubuntu Desktop 26.04, Kali, Windows 10, 11 and Server 2025 | thin templates, cloned by [`deploy/`](../deploy/README.md) | [proxmox/README.md](proxmox/README.md) |
| VMware Workstation | Ubuntu Server and Desktop 24.04 and 26.04, Windows Server 2025 | VMs and Vagrant boxes, provisioned when built or by Vagrant | [vmware/README.md](vmware/README.md) |

## Inside a template directory

| Path | Holds |
| --- | --- |
| `<os>.pkr.hcl` | the builder, its variables and the build block |
| `<os>.auto.pkrvars.hcl` | non-secret defaults Packer loads by itself (VMware) |
| `http/` | the seed the installer fetches: autoinstall `user-data` or a debian-installer preseed |
| `config/` | Windows answer files (VMware); the Proxmox Windows templates share [`proxmox/autounattend.pkrtpl.xml`](proxmox/autounattend.pkrtpl.xml) |
| `Vagrantfile` | the machines a box becomes (VMware) |
| `README.md` | this template's values, status and differences |

Templates reach the shared provisioners through `${path.root}/../../../scripts/`.

## Where a value goes

| Value | Where | Committed |
| --- | --- | --- |
| API token, build passwords | the environment: `PKR_VAR_*` | never |
| Node, storage pools, bridge, SSH public key | `proxmox/proxmox.pkrvars.hcl` | no - only the `.example` |
| SSH public key for a VMware build | the environment: `PKR_VAR_ssh_authorized_key` | never |
| ISO URL, checksum, sizing, `vm_id` | the template's `.pkr.hcl` defaults | yes |

Build output, `packer_cache/` and `.vagrant/` are generated and gitignored. See [SECURITY.md](../SECURITY.md) for the credential model.

## Verify

```bash
scripts/check-templates.sh packer seeds   # every template: fmt, validate, and its seed
```
