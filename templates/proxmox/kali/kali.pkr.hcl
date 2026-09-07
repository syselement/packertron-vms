// Kali Linux template for Proxmox.
// Adapted from https://github.com/mttaggart/seclab (Packer/kali/config.pkr.hcl).
//
// STATUS: stub. Validates, but does not build - http/kali.preseed does not
// exist, so the boot_command below has nothing to fetch.
//
// Docs:
//   proxmox-iso builder  https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox/latest/components/builder/iso
//   README.md            status and credentials
//
// Run:
//   packer init .
//   packer validate -var-file=../proxmox.pkrvars.hcl .

packer {
  required_plugins {
    proxmox = {
      version = ">= 1.2.1"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "hostname" {
  type    = string
  default = "kali"
}

variable "proxmox_api_url" {
  type        = string
  description = "Proxmox API endpoint, including scheme, port and /api2/json"
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
  type    = string
  default = "proxmox"
}

variable "storage_pool" {
  type    = string
  default = "local-lvm"
}

variable "iso_storage_pool" {
  type    = string
  default = "local"
}

variable "network_bridge" {
  type    = string
  default = "vmbr1"
}

variable "ssh_username" {
  type    = string
  default = "kali"
}

variable "ssh_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "insecure_skip_tls_verify" {
  type        = bool
  description = "Skip Proxmox API certificate verification. Leave false unless the node uses a self-signed certificate you have chosen to accept."
  default     = false
}

source "proxmox-iso" "seclab-kali" {
  proxmox_url = var.proxmox_api_url
  node        = var.proxmox_node
  username    = var.proxmox_api_token_id
  token       = var.proxmox_api_token_secret

  boot_iso {
    type         = "ide"
    iso_file     = "${var.iso_storage_pool}:iso/kali.iso"
    iso_checksum = "sha256:0b0f5560c21bcc1ee2b1fef2d8e21dca99cc6efa938a47108bbba63bec499779"
    unmount      = true
  }

  ssh_username           = var.ssh_username
  ssh_password           = var.ssh_password
  ssh_handshake_attempts = 100
  ssh_timeout            = "4h"

  http_directory           = "${path.root}/http"
  cores                    = 4
  memory                   = 8192
  vm_name                  = "seclab-kali"
  qemu_agent               = true
  template_description     = "Kali"
  insecure_skip_tls_verify = var.insecure_skip_tls_verify
  machine                  = "pc-q35-9.0"
  cpu_type                 = "x86-64-v2-AES"

  network_adapters {
    bridge = var.network_bridge
  }

  disks {
    type         = "virtio"
    disk_size    = "50G"
    storage_pool = var.storage_pool
    format       = "raw"
  }

  boot_wait = "10s"
  boot_command = [
    "<esc><wait>",
    "/install.amd/vmlinuz noapic ",
    "preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/kali.preseed ",
    "hostname=${var.hostname} ",
    "auto=true ",
    "interface=auto ",
    "domain=vm ",
    "initrd=/install.amd/initrd.gz -- <enter>"
  ]
}

// Deliberately no provisioners: this template stays script-free.
build {
  sources = ["source.proxmox-iso.seclab-kali"]
}
