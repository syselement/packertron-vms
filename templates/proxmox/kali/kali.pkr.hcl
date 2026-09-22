# Kali Linux template for Proxmox VE: ISO + debian-installer preseed, sealed
# for cloning.
# Adapted from https://github.com/mttaggart/seclab (Packer/kali/config.pkr.hcl).
#
# Docs:
#   proxmox-iso builder  https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox/latest/components/builder/iso
#   Preseed              https://www.debian.org/releases/stable/amd64/apb.en.html
#   README.md            what differs from the Ubuntu templates, and why
#
# Run:
#   ssh-add -l                                            # the seed's key must be loaded
#   export PKR_VAR_proxmox_api_token_id="user@pve!token"
#   export PKR_VAR_proxmox_api_token_secret="..."
#   packer init .
#   packer validate -var-file=../proxmox.pkrvars.hcl .
#   packer build    -var-file=../proxmox.pkrvars.hcl .

packer {
  required_version = ">= 1.12.0"
  required_plugins {
    proxmox = {
      version = ">= 1.2.1"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_api_url" {
  type        = string
  description = "Full Proxmox API endpoint, e.g. https://proxmox.example:8006/api2/json"
  default     = "https://proxmox:8006/api2/json"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "Proxmox API token id, as user@realm!tokenname"
  sensitive   = true
  default     = ""
}

variable "proxmox_api_token_secret" {
  type        = string
  description = "Proxmox API token secret"
  sensitive   = true
  default     = ""
}

variable "proxmox_node" {
  type        = string
  description = "Name of the Proxmox node to build on"
  default     = "proxmox"
}

variable "insecure_skip_tls_verify" {
  type        = bool
  description = "Skip Proxmox API certificate verification. Leave false unless the node uses a self-signed certificate you have chosen to accept."
  default     = false
}

# Kali is a rolling release: the point release only names the installer
# snapshot, and the preseed full-upgrades to current during the install.
variable "iso" {
  type        = string
  description = "A URL to the ISO file; Packer downloads it to iso_storage_pool"
  default     = "https://cdimage.kali.org/kali-2026.2/kali-linux-2026.2-installer-amd64.iso"
}

variable "checksum" {
  type        = string
  description = "The checksum for the ISO file"
  default     = "file:https://cdimage.kali.org/kali-2026.2/SHA256SUMS"
}

# Setting this uses an ISO already on the node: nothing is downloaded or
# uploaded, and it keeps whatever name you gave it. Leaving it empty downloads
# var.iso instead.
variable "iso_file" {
  type        = string
  description = "ISO already on the node, as storage:iso/name.iso; empty downloads var.iso"
  default     = ""
}

variable "iso_storage_pool" {
  type        = string
  description = "Proxmox storage that holds ISO images"
  default     = "local"
}

variable "storage_pool" {
  type        = string
  description = "Proxmox storage for the VM disk and the cloud-init drive"
  default     = "local-lvm"
}

variable "network_bridge" {
  type        = string
  description = "Proxmox bridge to attach the VM to"
  default     = "vmbr0"
}

variable "vm_id" {
  type        = number
  description = "VMID for the build. Proxmox requires it to be free on the node."
  default     = 80200
}

# Raise this first if the installer never starts: OVMF posts more slowly than
# SeaBIOS, and the keystrokes then land in the firmware splash, not GRUB.
variable "boot_wait" {
  type        = string
  description = "Delay before the boot command is typed"
  default     = "10s"
}

# - Empty lets Packer choose.
# - Pin it on a host with docker0/virbr0/VPN interfaces: Packer can serve the
#   seed on an address the VM cannot reach, and the build then stalls at the
#   installer with nothing reported wrong.
variable "http_bind_address" {
  type        = string
  description = "Local address to serve http/ from; empty means let Packer choose"
  default     = ""
}

variable "template_name" {
  type        = string
  description = "Name of the resulting template"
  default     = "kali-template"
}

# Normally empty: the builder asks the qemu guest agent for the VM's address.
# That query needs VM.GuestAgent.Audit on the token's role; without it the
# lookup returns nothing and the build sits on "Waiting for SSH" forever.
# Setting this skips the lookup.
variable "ssh_host" {
  type        = string
  description = "Address to reach the build VM on; empty asks the guest agent"
  default     = ""
}

# Must match the account http/kali.preseed creates; a mismatch makes every
# build wait out the SSH timeout.
variable "ssh_username" {
  type        = string
  description = "The username to connect to SSH"
  default     = "syselement"
}

# Not used to log in: the preseed turns password authentication off. Only
# piped into `sudo -S`, which the preseed's NOPASSWD sudoers means sudo never
# reads.
variable "ssh_password" {
  type        = string
  description = "Password fed to sudo -S by the provisioners; not used for SSH login"
  sensitive   = true
  default     = "packer"
}

source "proxmox-iso" "kali" {
  proxmox_url              = var.proxmox_api_url
  node                     = var.proxmox_node
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = var.insecure_skip_tls_verify

  # Exactly one of iso_file and iso_url may be set, and an empty string counts
  # as unset, so var.iso_file is the switch between them.
  boot_iso {
    type             = "scsi"
    iso_file         = var.iso_file
    iso_url          = var.iso_file == "" ? var.iso : ""
    iso_checksum     = var.checksum
    iso_storage_pool = var.iso_storage_pool
    unmount          = true
  }

  vm_id           = var.vm_id
  vm_name         = var.template_name
  cores           = 4
  memory          = 4096
  cpu_type        = "host"
  os              = "l26"
  scsi_controller = "virtio-scsi-single"
  qemu_agent      = true

  # q35 rather than the i440fx default. Proxmox still exposes ide2 on q35, so
  # the cloud-init drive below is unaffected.
  machine = "q35"
  bios    = "ovmf"

  template_name        = var.template_name
  template_description = "Kali Linux, built by Packer on ${timestamp()}. q35/OVMF. Thin: a clone provisions only if it asks."

  # OVMF will not start without a variable store. pre_enrolled_keys false: with
  # Microsoft's Secure Boot keys enrolled, anything unsigned fails to boot once cloned.
  efi_config {
    efi_storage_pool  = var.storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = false
  }

  # kali-linux-default with a desktop is a large install; 30G leaves little
  # room for what a pentest box accumulates.
  disks {
    type         = "scsi"
    disk_size    = "50G"
    storage_pool = var.storage_pool
    format       = "raw"
    discard      = true
    ssd          = true
  }

  network_adapters {
    model    = "virtio"
    bridge   = var.network_bridge
    firewall = false
  }

  # Xfce needs a real framebuffer; the 16MB default is enough to boot and not
  # much else.
  vga {
    type   = "std"
    memory = 32
  }

  # The clone-time configuration channel: hostname, user, keys and network are
  # set here per VM. During the build the preseed keeps cloud-init switched
  # off, and seal-for-clone.sh switches it back on.
  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  http_directory    = "${path.root}/http"
  http_bind_address = var.http_bind_address

  # Under OVMF the ISO boots GRUB, not isolinux, so the BIOS-era "<esc> then
  # type a kernel line" sequence never reaches a prompt. `c` opens GRUB's own
  # console, where the installer is started by hand with the preseed URL on
  # the kernel line. auto=true defers the locale and keyboard questions until
  # the seed has been fetched; priority=critical suppresses the rest.
  boot_command = [
    "<wait>c<wait>",
    "linux /install.amd/vmlinuz auto=true priority=critical",
    " preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/kali.preseed",
    " hostname=kali domain=local interface=auto<enter><wait>",
    "initrd /install.amd/initrd.gz<enter><wait>",
    "boot<enter>"
  ]
  boot_wait = var.boot_wait

  ssh_host       = var.ssh_host
  ssh_username   = var.ssh_username
  ssh_agent_auth = true
  # A full-upgrade of a rolling release plus the default toolset: expect the
  # install itself to take a while before SSH is reachable.
  ssh_timeout = "60m"
}

build {
  sources = ["source.proxmox-iso.kali"]

  # The same 00 -> 01 -> seal chain the Ubuntu templates run. Both scripts are
  # distro-agnostic on this path: apt, cloud-init, journalctl, and a guest-agent
  # branch that keys off the detected hypervisor rather than the distribution.
  #
  # The `chmod +x` prefix is Packer's own default, which overriding
  # execute_command drops; without it every script fails with "permission
  # denied" before running a line.

  # 00 carries the rolling-release upgrade the preseed deliberately skips, and
  # re-installing the guest agent it already has is a no-op.
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; echo '${var.ssh_password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts = [
      "${path.root}/../../../scripts/ubuntu/00-update-system.sh"
    ]
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; echo '${var.ssh_password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts = [
      "${path.root}/../../../scripts/ubuntu/01-cleanup-system.sh"
    ]
  }

  # Clone-only sealing; must run last.
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; echo '${var.ssh_password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts = [
      "${path.root}/../seal-for-clone.sh"
    ]
  }
}
