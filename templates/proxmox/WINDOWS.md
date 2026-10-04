# Windows templates on Proxmox VE

What the three Windows templates share: the media, the build, and how a clone configures itself. The node, the token, staging and the build command are in [README.md](README.md); each template's README has its values.

Each template installs from its ISO and an answer file rendered from [`autounattend.pkrtpl.xml`](autounattend.pkrtpl.xml), generalizes with sysprep, and leaves cloudbase-init to configure each clone from the Proxmox cloud-init drive. Adapted from [mttaggart/seclab](https://github.com/mttaggart/seclab) (`Packer/win-11-ws/config.pkr.hcl`), without its KeePass, CA certificate and hand-staged answer-file ISO.

| | [`win-10`](win-10/README.md) | [`win-11`](win-11/README.md) | [`win-srv-2025`](win-srv-2025/README.md) |
| --- | --- | --- | --- |
| `vm_id` | 80310 | 80311 | 80325 |
| Release | Windows 10 Enterprise 22H2, evaluation | Windows 11 Enterprise 25H2, evaluation | Windows Server 2025 Standard, evaluation, Desktop Experience |
| `image_index` | 1 | 1 | 2 |
| virtio-win folder / Proxmox `os` | `w10` / `win10` | `w11` / `win11` | `2k25` / `win11`, which covers Server 2022 and 2025 |
| Account on a clone | `syselement` | `syselement` | `Administrator` |
| Clone password | any | any | three of upper case, lower case, digits and symbols |
| Build time | ~1 hour | ~1 hour | ~1.5 hours |

Everything else - firmware, TPM, disk, the build chain, the scripts - is identical: diffing any two templates shows only these values. Most of each build is Windows Update.

| | Ubuntu and Kali | Windows |
| --- | --- | --- |
| Seed | cloud-config or preseed, served over HTTP | `autounattend.xml` on a CD, via `cd_content` |
| Installer media | SCSI | SATA - Setup has an AHCI driver and no virtio one |
| Firmware | OVMF, `pre_enrolled_keys = false` | OVMF, `pre_enrolled_keys = true`, and a TPM 2.0 |
| Build login | the seed's account, SSH key through the agent | the built-in `Administrator`, password |
| Build ends with | `seal-for-clone.sh` | `sysprep /generalize /oobe` |
| Clone configured by | cloud-init, `nocloud` drive | cloudbase-init, `configdrive2` drive |
| `cores` / `memory` / `disk_size` | 2-4 / 2048-8192 / 30-64G | 4 / 4096 / 64G - Windows 11's minimums |

## Media and tools

- **The Windows ISO**, staged on the node under Microsoft's own filename and checked by [`stage-isos.sh`](../../scripts/proxmox/stage-isos.sh) against the SHA-256 each template pins. For media that is not an evaluation ISO, set `image_index` to the edition you want - `wiminfo sources/install.wim` lists them - and `product_key` if it needs one.
- **virtio-win 0.1.302**, which Packer downloads and checks against a pinned SHA-256 - Fedora publishes none, so it was computed when the version was pinned. Set `virtio_iso_file` to use a copy already on the node.
- **`xorriso` on the workstation.** Packer writes the answer file to a CD image locally before uploading it; `scripts/install-requirements.sh install` installs it.

## The build

```text
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

**The guest tools install at first logon, not in a provisioner.** Packer needs the guest agent to learn the VM's address before it can connect, and the NetKVM driver reinstall resets the NIC, which would drop Packer's SSH session mid-script (`exit status 2300218`). OpenSSH Server comes last, so everything else is done by the time port 22 answers; Windows 10 and 11 download it from Windows Update.

**cloudbase-init's service is left Manual in the template.** Started on the build VM, it would replace the password the remaining provisioners log in with; started automatically on a clone, it would run inside Windows Setup, which reverts the account rename. `C:\Windows\Setup\Scripts\SetupComplete.cmd`, which Windows runs once after Setup, starts it.

**sysprep runs inside the last provisioner**, with `/quit`, and checks for `Sysprep_succeeded.tag`: a failed generalize is reported by name with the tail of `setuperr.log`, not as a build that times out. `proxmox-iso` then shuts the VM down itself - and the VMware Server box generalizes the same way. Hibernation goes off first: a clone resuming from a Fast Startup image would skip the specialize pass cloudbase-init runs in.

**SSH, not WinRM.** The references this was checked against use WinRM over TLS with verification switched off; Windows ships OpenSSH Server, which needs no certificate, no HTTPS listener and no bypass.

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

  cloudbase-init sets the password once per drive, so removing it changes the drive and the next boot gives the account a random password: only the SSH key works until you set one inside Windows. To keep console login, leave the drive alone and change the password inside Windows instead (`net user <account> *`). It stays until the drive changes - a different `cipassword`, keys, network or `TF_VAR_password` - and the drive then holds only a password that no longer works.

The first boot reboots once, for the hostname. Login does not work until it has.

Two settings in `scripts/windows/cloudbase-init/` are deliberate rather than defaults. The plugin list omits both WinRM plugins, which would otherwise open an HTTPS WinRM listener on every clone. And `11_cloudbase_init.ps1` comments out the `Match Group administrators` block in `sshd_config`: cloudbase-init writes keys to the account's own `authorized_keys`, which stock OpenSSH ignores for administrators, so without it the keys would never work.

## When the build stops

| Symptom | Look at |
| --- | --- |
| Setup stops at "Are you sure you want to quit?" | the Enter presses reached Setup's focused Cancel button. Click **No** in the console and Setup carries on; next time lower `boot_key_seconds` (default 15) |
| The VM ends at the UEFI shell instead of Setup | the presses stopped before the "Press any key to boot from CD" prompt; raise `boot_key_seconds` |
| Setup installs the wrong edition, or asks for a key | `image_index` does not match the ISO's `install.wim` |
| Setup finds no disk to install to | the virtio CD is not at `F:` - the CD order in the template changed |
| "Waiting for SSH" never ends | `C:\Windows\Temp\packertron-firstlogon.log` on the VM's console; usually the OpenSSH download, the guest tools install (`C:\Windows\Temp\virtio-guest-tools*.log`), or a NIC that never came back after it |
| A provisioner fails with `exit status 2300218` | Packer lost the SSH session mid-script: something in it reset the network |
| `12_sysprep.ps1` fails | the lines it prints from `setuperr.log`; an AppX package installed for one user is the usual cause |
| A Server clone ignores the password, and only the SSH key works | Server's complexity rule refused it; see [`win-srv-2025/README.md`](win-srv-2025/README.md) |

## Evaluation period

The templates install evaluation editions, and a clone's evaluation runs for 180 days. Reset it on the clone instead of rebuilding - the remaining rearm count in `/dlv` says how many resets are left:

```bash
# days left and rearms left
ssh syselement@<address> 'cscript //nologo C:\Windows\System32\slmgr.vbs /dlv'
# restart the evaluation clock; it takes effect after the restart
ssh syselement@<address> 'cscript //nologo C:\Windows\System32\slmgr.vbs /rearm'
ssh syselement@<address> 'shutdown /r /t 5'
```

On Server 2025 the account is `Administrator@`.

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

## Upstream license

The Windows templates adapt code from [mttaggart/seclab](https://github.com/mttaggart/seclab), which is released under the MIT License; its notice is reproduced here as that license requires.

```text
MIT License

Copyright (c) 2021 Michael Taggart

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
