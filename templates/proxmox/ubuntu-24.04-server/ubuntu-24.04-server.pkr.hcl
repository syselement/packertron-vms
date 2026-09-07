# Ubuntu Server 24.04 LTS template for Proxmox VE: ISO + autoinstall, sealed
# for cloning.
#
# Docs:
#   proxmox-iso builder  https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox/latest/components/builder/iso
#   Autoinstall          https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html
#   README.md            settings/credentials split, clone-time model
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

variable "iso" {
  type        = string
  description = "A URL to the ISO file; Packer downloads it to iso_storage_pool"
  default     = "https://releases.ubuntu.com/noble/ubuntu-24.04.4-live-server-amd64.iso"
}

variable "checksum" {
  type        = string
  description = "The checksum for the ISO file"
  default     = "file:https://releases.ubuntu.com/noble/SHA256SUMS"
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
  default     = 80024
}

# Raise this first if the installer never starts: OVMF posts more slowly than
# SeaBIOS, and the keystrokes then land in the firmware splash, not GRUB.
variable "boot_wait" {
  type        = string
  description = "Delay before the boot command is typed"
  default     = "10s"
}

# Empty lets Packer choose. Pin it on a host with docker0/virbr0/VPN
# interfaces: Packer can serve the seed on an address the VM cannot reach, and
# the build then stalls at the installer with nothing reported wrong.
variable "http_bind_address" {
  type        = string
  description = "Local address to serve http/ from; empty means let Packer choose"
  default     = ""
}

variable "template_name" {
  type        = string
  description = "Name of the resulting template"
  default     = "ubuntu-24.04-server-template"
}

# Must match the identity block in http/user-data; a mismatch makes every
# build wait out the SSH timeout.
variable "ssh_username" {
  type        = string
  description = "The username to connect to SSH"
  default     = "syselement"
}

# Not used to log in: the seed sets `allow-pw: false`. Only piped into
# `sudo -S`, which the seed's NOPASSWD sudoers means sudo never reads.
variable "ssh_password" {
  type        = string
  description = "Password fed to sudo -S by the provisioners; not used for SSH login"
  sensitive   = true
  default     = "packer"
}

source "proxmox-iso" "ubuntu-24-04-server" {
  proxmox_url              = var.proxmox_api_url
  node                     = var.proxmox_node
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = var.insecure_skip_tls_verify

  boot_iso {
    type             = "scsi"
    iso_url          = var.iso
    iso_checksum     = var.checksum
    iso_storage_pool = var.iso_storage_pool
    unmount          = true
  }

  vm_id           = var.vm_id
  vm_name         = var.template_name
  cores           = 2
  memory          = 2048
  cpu_type        = "host"
  os              = "l26"
  scsi_controller = "virtio-scsi-single"
  qemu_agent      = true

  # q35 rather than the i440fx default. Proxmox still exposes ide2 on q35, so
  # the cloud-init drive below is unaffected.
  machine = "q35"
  bios    = "ovmf"

  template_name        = var.template_name
  template_description = "Ubuntu Server 24.04 LTS, built by Packer. q35/OVMF. Thin: 02 and 03 run at first boot."

  # OVMF will not start without a variable store. pre_enrolled_keys false: with
  # Microsoft's Secure Boot keys enrolled, anything unsigned fails to boot once
  # cloned.
  efi_config {
    efi_storage_pool  = var.storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = false
  }

  disks {
    type         = "scsi"
    disk_size    = "30G"
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

  # The clone-time configuration channel: hostname, user, keys and network are
  # set here per VM.
  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  http_directory    = "${path.root}/http"
  http_bind_address = var.http_bind_address
  boot_command = [
    "<esc><wait>",
    "e<wait>",
    "<down><down><down><end>",
    " autoinstall ds=nocloud\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---",
    "<f10><wait>"
  ]
  boot_wait = var.boot_wait

  # The seed disables password auth and authorises one ed25519 key, and Packer
  # cannot unlock a passphrase-protected key file - so authentication goes
  # through the agent. `ssh-add -l` must list that key before building.
  ssh_username   = var.ssh_username
  ssh_agent_auth = true
  ssh_timeout    = "30m"
}

build {
  sources = ["source.proxmox-iso.ubuntu-24-04-server"]

  # The `chmod +x` prefix is Packer's own default, which overriding
  # execute_command drops; without it every script fails with "permission
  # denied" before running a line.
  #
  # 00 installs the guest agent. No library dependencies, so it uploads alone.
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; echo '${var.ssh_password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts = [
      "${path.root}/../../../scripts/ubuntu/00-update-system.sh"
    ]
  }

  # 01 truncates the machine-id and clears cloud-init state, so a clone is
  # treated as a fresh instance.
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; echo '${var.ssh_password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts = [
      "${path.root}/../../../scripts/ubuntu/01-cleanup-system.sh"
    ]
  }

  # Clone-only sealing; must run last, after the final reboot.
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; echo '${var.ssh_password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts = [
      "${path.root}/../seal-for-clone.sh"
    ]
  }
}
