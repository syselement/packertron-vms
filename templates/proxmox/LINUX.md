# Linux templates on Proxmox VE

What the Ubuntu and Kali templates share: the build, the seed and its key, and how the image is sealed for cloning. The node, the token, staging and the build command are in [README.md](README.md); each template's README has its values, and [Kali's](kali/README.md) what debian-installer does differently.

| Template | Installer and seed | Clone configured by |
| --- | --- | --- |
| [`ubuntu-24.04-server`](ubuntu-24.04-server/README.md), [`ubuntu-26.04-server`](ubuntu-26.04-server/README.md), [`ubuntu-26.04-desktop`](ubuntu-26.04-desktop/README.md) | subiquity, `http/user-data` (autoinstall) | cloud-init, `nocloud` drive |
| [`kali`](kali/README.md) | debian-installer, `http/kali.preseed` | cloud-init, `nocloud` drive |

---

## The build

```text
installer      installs from the seed Packer serves over HTTP; account, key, sudo, SSH
first boot     the guest agent, so Packer can learn the VM's address
provisioner    scripts/ubuntu/00-update-system.sh    updates, the guest agent for this hypervisor
provisioner    scripts/ubuntu/01-cleanup-system.sh   machine-id, /var/lib/cloud, cloud-init clean
provisioner    seal-for-clone.sh                     what a clone must not inherit; must run last
builder        shuts the VM down and converts it to a template
```

`02-provision-system.sh` and `03-customize-system.sh` never run in the build: a clone asks for them at first boot, from a fresh checkout, so a VM created a year from now gets the current scripts - see [`deploy/`](../../deploy/README.md#first-boot-provisioning).

**Firmware is q35 and OVMF**, with a 4MB EFI variable disk on the system disk's pool. `pre_enrolled_keys` is `false`: with Microsoft's Secure Boot keys enrolled, anything unsigned refuses to boot once cloned. OVMF posts more slowly than SeaBIOS, so if the installer never starts, raise `boot_wait`.

**The display is `qxl`**, so the Proxmox console offers SPICE as well as noVNC.

---

## The seed and the SSH key

Every seed authorizes one public key, and no key is committed: the seed carries an `@SSH_AUTHORIZED_KEY@` placeholder, and the template serves it with `http_content`, replaced by `ssh_authorized_key` from `../proxmox.pkrvars.hcl`. A build with no key fails validation, and `scripts/check-templates.sh seeds` fails if a real key is ever committed to a seed.

The seed turns SSH password authentication off, so the build logs in with that key - **through the agent**, because Packer's communicator cannot unlock a passphrase-protected key file:

```bash
ssh-add -l                  # must list the key ssh_authorized_key names
ssh-add ~/.ssh/id_ed25519   # if it does not
```

Without it the build reaches the installed system, fails every authentication, and sits out the whole `ssh_timeout`. For an unattended runner, use a dedicated passphrase-less build key with `ssh_private_key_file` instead of the agent.

`ssh_password` is never used to log in. It is piped to `sudo -S`, which the seed's `NOPASSWD` sudoers rule means sudo never reads. The seed's password hash is the published one for `packer` - see [SECURITY.md](../../SECURITY.md).

---

## The guest agent arrives on the first boot

The Ubuntu seeds install `qemu-guest-agent` from their `user-data:` section, on the first boot of the installed system, not from autoinstall's `packages:`:

- subiquity installs `packages:` while the ISO is its only APT source, and the server ISO does not carry the agent - the install fails with APT exit `100`;
- `00-update-system.sh` is too late: Packer needs the agent to learn the address before it can run any provisioner.

The unit is static and normally started by a udev rule that fired before the package existed, so `runcmd` starts it. Kali installs it from the network mirror, through `pkgsel/include`.

---

## Sealing for clones

[`seal-for-clone.sh`](seal-for-clone.sh) runs last, after `01-cleanup-system.sh` has truncated the machine-id and run `cloud-init clean`. It does only what `01` cannot: `01` is shared with the VMware templates, where cloud-init stays pinned and nothing would regenerate what the seal removes.

| Step | Why |
| --- | --- |
| write `99-pve.cfg` | `datasource_list` narrows a clone to the drive Proxmox attaches; `manage_etc_hosts: localhost` keeps `/etc/hosts` in step with the hostname - Ubuntu leaves it unset and has no `myhostname` in `nsswitch.conf`, so a renamed clone would answer to nothing and every `sudo` would print `unable to resolve host` |
| remove `/etc/cloud/cloud-init.disabled` | Kali's preseed switches cloud-init off for its build; a clone must read its drive. A no-op on Ubuntu |
| verify cloud-init is unpinned | a leftover subiquity drop-in gives clones no hostname, user, key or address, and nothing in any log to say why, so the build fails instead |
| drop the `/media/cdrom0` fstab line | debian-installer's entry resolves to the cloud-init drive on a Kali clone. A no-op on Ubuntu |
| write `99-hide-cidata.rules` | the cloud-init drive stays attached for life; on a desktop, udisks would show it as a CD |
| remove `/etc/ssh/ssh_host_*` | every clone would answer with the same fingerprint; cloud-init regenerates them before `sshd` starts |
| remove `/var/lib/systemd/random-seed` | every clone would start from the same entropy seed |

**Why subiquity's cloud-init files go at the end, not in the seed.** Subiquity pins cloud-init to its own seed and disables its networking. Left in place, a clone ignores the drive Proxmox attaches and applies no hostname, user, key or network. Deleting them in the seed's `late-commands` looks equivalent and is not: `99-installer.cfg` is what applies the seed's `ssh:` section on the first boot, and writing `99-pve.cfg` before that boot drops the `None` datasource that carries it - either way the build hangs on "Waiting for SSH". `01`'s `cloud-init clean` removes them after the first boot, and the seal checks.

---

## When the build stops

| Symptom | Look at |
| --- | --- |
| "Waiting for SSH", and the VM's console shows a login prompt | `ssh-add -l`: the agent does not hold the key `ssh_authorized_key` names |
| The installer stops at a question | the seed lacks that answer; it is on the console |
| A clone has no hostname, user or address | cloud-init stayed pinned; the seal should have failed the build - check that it ran |

---
