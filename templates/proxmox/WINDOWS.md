# Windows templates on Proxmox VE

What the three Windows templates - [`win-10`](win-10/README.md), [`win-11`](win-11/README.md) and [`win-srv-2025`](win-srv-2025/README.md) - have in common: the media they need, the build, and how a clone configures itself. Each template's own README has its values and the steps from its ISO to a VM deployed with [`deploy/`](../../deploy/README.md).

Each template builds from an installer ISO and an answer file, generalizes with sysprep, and leaves cloudbase-init to configure each clone from the Proxmox cloud-init drive.

Adapted from [mttaggart/seclab](https://github.com/mttaggart/seclab) (`Packer/win-11-ws/config.pkr.hcl`). What the upstream did through KeePass, a CA certificate and a hand-staged answer-file ISO is gone: credentials come from the environment, and the answer file is rendered from [`autounattend.pkrtpl.xml`](autounattend.pkrtpl.xml) at build time.

Credentials, the API token and its role are the same as for the Linux templates and documented once, in [`ubuntu-24.04-server/README.md`](ubuntu-24.04-server/README.md). This file covers what Windows does differently.

## The three templates

| | [`win-10`](win-10/README.md) | [`win-11`](win-11/README.md) | [`win-srv-2025`](win-srv-2025/README.md) |
| --- | --- | --- | --- |
| `vm_id` | 80310 | 80311 | 80325 |
| Release | Windows 10 Enterprise 22H2, evaluation | Windows 11 Enterprise 25H2, evaluation | Windows Server 2025 Standard, evaluation, Desktop Experience |
| `image_index` | 1 | 1 | 2 |
| virtio-win folder | `w10` | `w11` | `2k25` |
| Proxmox `os` | `win10` | `win11` | `win11` - it covers Server 2022 and 2025 too |
| Account on a clone | `syselement` | `syselement` | `Administrator` |
| Clone password | any | any | complex: three of upper case, lower case, digits, symbols |
| Build time | ~1 hour | ~1 hour | ~1.5 hours |

Everything else - firmware, TPM, disk, the build chain, the scripts - is identical, and the templates are kept that way: diffing any two shows only these values. Most of each build is Windows Update.

**Once, before the first build**, on the workstation and the node: Packer, `xorriso` and the checks from `scripts/install-requirements.sh install`; OpenTofu as in [`deploy/README.md`](../../deploy/README.md). A Proxmox API token for Packer, with the role in [`ubuntu-24.04-server/README.md`](ubuntu-24.04-server/README.md), and the node settings in `templates/proxmox/proxmox.pkrvars.hcl`, copied from its `.example`.

## What differs from the Linux templates

| | Ubuntu and Kali | Windows |
| --- | --- | --- |
| Seed | cloud-config or preseed, served over HTTP | `autounattend.xml` on a CD, via `cd_content` |
| Installer media | SCSI | SATA - setup has an AHCI driver and no virtio one |
| Firmware | OVMF, `pre_enrolled_keys = false` | OVMF, `pre_enrolled_keys = true`, plus a TPM 2.0 |
| Build login | `syselement`, SSH key from the agent | built-in `Administrator`, password |
| Build ends with | `seal-for-clone.sh` | `sysprep /generalize /oobe` |
| Clone configured by | cloud-init, `nocloud` drive | cloudbase-init, `configdrive2` drive |
| Disk / RAM | 30-64G / 2-8G | 64G / 4096 - Windows 11's minimums |

## What has to be on the node first

**The Windows ISO**, staged by hand like every other template here. Each template's `iso_file` defaults to its evaluation ISO on `local` under Microsoft's own filename, and its `iso` and `checksum` pin the same file's URL and SHA-256:

| Template | Release | Filename | SHA-256 |
| --- | --- | --- | --- |
| `win-10` | Windows 10 Enterprise 22H2, evaluation | `19045.2006.220908-0225.22h2_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso` | `ef7312733a9f5d7d51cfa04ac497671995674ca5e1058d5164d6028f0938d668` |
| `win-11` | Windows 11 Enterprise 25H2, evaluation | `26200.6584.250915-1905.25h2_ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso` | `a61adeab895ef5a4db436e0a7011c92a2ff17bb0357f58b13bbc4062e535e7b9` |
| `win-srv-2025` | Windows Server 2025, evaluation | `26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso` | `d0ef4502e350e3c6c53c15b1b3020d38a5ded011bf04998e950720ac8579b23d` |

The Server hash is also the one `vmware/win-srv-2025` has pinned and built from.

**Packer does not check a staged ISO** - the plugin skips `iso_checksum` once `iso_file` is set - so verify each one when you stage it. On the node, once:

```bash
cd /var/lib/vz/template/iso
MS=https://software-static.download.prss.microsoft.com/dbazure

wget "$MS/988969d5-f34g-4e03-ac9d-1f9786c66750/19045.2006.220908-0225.22h2_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso"
wget "$MS/888969d5-f34g-4e03-ac9d-1f9786c66749/26200.6584.250915-1905.25h2_ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso"
wget "$MS/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"

sha256sum -c <<'EOF'
ef7312733a9f5d7d51cfa04ac497671995674ca5e1058d5164d6028f0938d668  19045.2006.220908-0225.22h2_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso
a61adeab895ef5a4db436e0a7011c92a2ff17bb0357f58b13bbc4062e535e7b9  26200.6584.250915-1905.25h2_ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso
d0ef4502e350e3c6c53c15b1b3020d38a5ded011bf04998e950720ac8579b23d  26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso
EOF
```

Under another name, pass `-var 'iso_file=local:iso/<name>.iso'`. To have Packer download the ISO from Microsoft and check it against the pinned SHA-256 instead, pass `-var 'iso_file='` - a 5.5 to 7 GB transfer per build.

For media that is not an evaluation ISO, set `image_index` to the edition you want - `wiminfo sources/install.wim` lists them - and `product_key` if it needs one.

**Nothing else.** virtio-win 0.1.302 is downloaded and checked against a pinned SHA-256 by Packer. Fedora publishes no checksum for the ISO, so that one was computed from the release when it was pinned. To use a copy already on the node instead, set `virtio_iso_file`.

**`xorriso` on the build host.** Packer writes the answer file to a CD image locally before uploading it, and fails at that step without an ISO tool. `scripts/install-requirements.sh` installs it.

## The build

```
Windows setup     virtio drivers in WinPE, disk layout, Administrator, one autologon, dark mode, Explorer view
first logon       00_firstlogon.ps1: virtio-win guest tools (with the QEMU guest agent), RDP, OpenSSH Server
provisioner       09_system_settings.ps1      Edge first run off, diagnostic data lowest, High performance, password never expires
windows-update    rgl/windows-update 0.18.5   install, restart, repeat until no update is left
provisioner       10_wait_for_servicing.ps1   servicing idle, no reboot pending
upload            cloudbase-init .conf files, rendered, and the sysprep Unattend.xml
provisioner       11_cloudbase_init.ps1       install and configure, do not run
provisioner       03_cleanup.ps1, 12_sysprep.ps1
builder           shuts the VM down and converts it to a template
```

The guest tools install at first logon, not in a provisioner, for two reasons: Packer asks the guest agent for the VM's address before it can connect at all, and the NetKVM driver reinstall resets the NIC, which over SSH drops Packer's session mid-script (`exit status 2300218`, Packer's code for a lost connection). OpenSSH Server comes last, so everything else is finished by the time port 22 answers. Windows 10 and 11 download it from Windows Update, which makes the first logon the step that needs the network; Server 2025 ships it.

**cloudbase-init's service is left Manual in the template.** Started on the build VM, it would replace the password the remaining provisioners log in with. Started automatically on a clone, it runs while the clone's first boot is still inside Windows Setup, and Setup reverts the account rename it makes. `C:\Windows\Setup\Scripts\SetupComplete.cmd`, which Windows runs once after Setup finishes, switches it to Automatic and starts it.

## Why sysprep runs inside a provisioner

`proxmox-iso` has no `shutdown_command` - that is a VMware-builder setting, which is why `vmware/win-srv-2025` can use one. The Proxmox builder shuts the VM down itself after the last provisioner. So `12_sysprep.ps1` runs sysprep with `/quit` and checks for `Sysprep_succeeded.tag`, and a failed generalize is reported by name with the tail of `setuperr.log` instead of surfacing as a build that times out.

It turns hibernation off first. Fast Startup hibernates the kernel instead of shutting down, and a clone resuming from that image would skip the specialize pass cloudbase-init runs in.

## How a clone configures itself

Proxmox writes a Windows VM's cloud-init drive as `configdrive2` - the format cloudbase-init reads - because the template's `os` is a Windows type. That setting is load-bearing: with a Linux ostype, Proxmox would also hash the password, and cloudbase-init would set the hash itself as the password.

On a clone's first boot, sysprep's specialize pass runs cloudbase-init once to set the hostname and grow `C:`. Once Setup has finished, `SetupComplete.cmd` starts its service, which manages one account, writes the SSH keys, and sets the password:

- **Windows 10 and 11** rename the built-in `Administrator` to `syselement`, so a clone has one administrator named like the Linux clones rather than a second one beside it.
- **Server 2025** keeps `Administrator`, and does not rename it.
- **With a password on the drive** (`TF_VAR_password`, or `qm set --cipassword`), the account gets that password. **Without one**, a random one - the account is then reachable by SSH key only, and the build password does not survive into a configured clone. That is the same posture as the Linux clones.
- **A password on the drive stays readable.** Proxmox writes it in plain text for a Windows VM, and the drive stays attached, so any local user can read `D:\openstack\latest\meta_data.json`. Once the clone is up, change the password or remove it from the drive: `qm set <vmid> --delete cipassword`, then `qm cloudinit update <vmid>`. For every Windows VM on the node at once, templates left alone, on the node:

  ```bash
  for id in $(qm list | awk 'NR > 1 {print $1}'); do c=$(qm config "$id"); grep -q '^ostype: win' <<<"$c" && ! grep -q '^template: 1' <<<"$c" && grep -q '^cipassword:' <<<"$c" && qm set "$id" --delete cipassword && qm cloudinit update "$id"; done
  ```

  A later `tofu apply` writes `TF_VAR_password` back to the drive, so run it again after one.

The first boot reboots once, for the hostname. Login does not work until it has.

Two settings in `scripts/windows/cloudbase-init/` are deliberate rather than defaults. The plugin list omits both WinRM plugins, which would otherwise open an HTTPS WinRM listener on every clone. And `11_cloudbase_init.ps1` comments out the `Match Group administrators` block in `sshd_config`: cloudbase-init writes keys to the account's own `authorized_keys`, which stock OpenSSH ignores for administrators, so without it the keys would never work.

## Why SSH and not WinRM

Ludus and eaksel/packer-Win2022, the two references this was checked against, both use WinRM with `winrm_use_ssl = true` and `winrm_insecure = true` - TLS with verification switched off. Windows ships OpenSSH Server, `vmware/win-srv-2025` already proves the SSH chain works here, and SSH needs no certificate, no HTTPS listener and no bypass.

## When the build stops

| Symptom | Look at |
| --- | --- |
| Setup stops at "Are you sure you want to quit?" | the Enter presses outlasted boot and reached Setup's focused Cancel button. Click **No** in the console and Setup carries on; for the next build, lower `boot_key_seconds` (default 15) |
| The VM ends at the UEFI shell instead of Setup | the presses stopped before the "Press any key to boot from CD" prompt appeared; raise `boot_key_seconds` |
| Setup installs the wrong edition, or asks for a key | `image_index` does not match the ISO's `install.wim` |
| Setup finds no disk to install to | the virtio CD is not at `F:` - the CD order in the template changed |
| "Waiting for SSH" never ends | `C:\Windows\Temp\packertron-firstlogon.log` on the VM's console; usually the OpenSSH download, the guest tools install (`C:\Windows\Temp\virtio-guest-tools*.log`), or a NIC that never came back after it |
| A provisioner fails with `exit status 2300218` | Packer lost the SSH session mid-script: something in it reset the network |
| `12_sysprep.ps1` fails | the lines it prints from `setuperr.log`; an AppX package installed for one user is the usual cause |
| A Server clone ignores the password, and only the SSH key works | Server's complexity rule refused it; see [`win-srv-2025/README.md`](win-srv-2025/README.md) |

## Check a clone after a template change

Before deploying from a rebuilt or changed template, check one clone by hand:

```bash
qm clone 80311 9311 --name win11-check --full
qm set 9311 --ipconfig0 ip=dhcp --cipassword '<password>' --sshkeys .ssh/syselement-key.pub
qm start 9311
```

- [ ] After one automatic reboot, `hostname` on the console is `win11-check`
- [ ] `ssh syselement@<address>` works with the key - `Administrator@` on Server - and `whoami /groups` lists Administrators
- [ ] `Get-Service cloudbase-init` and `C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\cloudbase-init.log` show a clean run
- [ ] `C:` has grown to the clone's disk size
- [ ] The desktop is dark at the first login, and Explorer opens on This PC with file extensions and hidden files shown
- [ ] `powercfg /getactivescheme` names High performance, and `net user <account>` shows `Password expires  Never`
- [ ] `powershell -c "(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR"` is above the ISO's build - the update loop ran
- [ ] A second clone has a different hostname and a different SID - `whoami /user`

If cloudbase-init does not apply the drive, stop there: `deploy/` configures a Windows clone only through it.
