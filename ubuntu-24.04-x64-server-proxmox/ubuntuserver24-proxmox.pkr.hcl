// Ubuntu Server 24.04 LTS template for Proxmox VE, built from the ISO with
// autoinstall and sealed for cloning.
//
// The template is deliberately thin: base OS, qemu-guest-agent, cloud-init
// left able to run again. Tooling is NOT baked in. 02-provision-system.sh and
// 03-customize-system.sh run per VM at first boot, so a clone created months
// from now still picks up the current scripts rather than whatever was current
// when this template was built.
//
// Credentials come from the environment, never from a file in this repository:
//
//   export PKR_VAR_proxmox_api_url="https://proxmox.example:8006/api2/json"
//   export PKR_VAR_proxmox_api_token_id="packer@pve!templates"
//   export PKR_VAR_proxmox_api_token_secret="..."
//
// Build with:
//   packer init . && packer build .

packer {
  required_version = ">= 1.7.0"
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
  default     = 9024
}

variable "template_name" {
  type        = string
  description = "Name of the resulting template"
  default     = "ubuntu-24.04-x64-server-template"
}

// Must match the identity block in http/user-data, which is what the
// autoinstall actually creates. Mismatched values make every build wait out
// the SSH timeout.
variable "ssh_username" {
  type        = string
  description = "The username to connect to SSH"
  default     = "syselement"
}

variable "ssh_password" {
  type        = string
  description = "A plaintext password to authenticate with SSH"
  sensitive   = true
  default     = "packer"
}

source "proxmox-iso" "ubuntuserver24" {
  // Documentation : https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox/latest/components/builder/iso

  // Connection
  proxmox_url              = var.proxmox_api_url
  node                     = var.proxmox_node
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = var.insecure_skip_tls_verify

  // Boot media
  boot_iso {
    type             = "scsi"
    iso_url          = var.iso
    iso_checksum     = var.checksum
    iso_storage_pool = var.iso_storage_pool
    unmount          = true
  }

  // Hardware
  vm_id                = var.vm_id
  vm_name              = var.template_name
  cores                = 2
  memory               = 2048
  cpu_type             = "host"
  os                   = "l26"
  scsi_controller      = "virtio-scsi-single"
  qemu_agent           = true
  template_name        = var.template_name
  template_description = "Ubuntu Server 24.04 LTS, built by Packer. Thin: 02 and 03 run at first boot."

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

  // A cloud-init drive is what makes the template useful: OpenTofu sets the
  // per-VM hostname, user, keys and network on it at clone time, and the
  // first-boot provisioning is delivered the same way.
  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  // Autoinstall seed, served by Packer's own HTTP server
  http_directory = "${path.root}/http"
  boot_command   = ["e<wait><down><down><down><end> autoinstall 'ds=nocloud;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/'<F10>"]
  boot_wait      = "10s"

  // Communicator
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "30m"
}

build {
  sources = ["source.proxmox-iso.ubuntuserver24"]

  // 00 installs the guest agent for the detected hypervisor; on Proxmox that
  // is qemu-guest-agent. It has no library dependencies, so the shell
  // provisioner can upload it on its own.
  provisioner "shell" {
    execute_command = "echo '${var.ssh_password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts = [
      "${path.root}/../scripts/ubuntu/00-update-system.sh"
    ]
  }

  // 01 seals the template and runs last. It truncates the machine-id and
  // clears cloud-init state, which is what lets every clone be treated as a
  // fresh instance and read the cloud-init drive Proxmox attaches to it.
  provisioner "shell" {
    execute_command = "echo '${var.ssh_password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts = [
      "${path.root}/../scripts/ubuntu/01-cleanup-system.sh"
    ]
  }
}
