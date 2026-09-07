# Ubuntu 24.04 Desktop template for VMware Workstation, packaged as a Vagrant box.
#
# Docs:
#   vmware-iso builder  https://developer.hashicorp.com/packer/integrations/hashicorp/vmware/latest/components/builder/iso
#   Autoinstall         https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html
#   README.md           build steps and Vagrant usage
#
# Run:
#   packer init .
#   packer validate .
#   packer build .
#   vagrant up

packer {
  required_plugins {
    vmware = {
      source  = "github.com/hashicorp/vmware"
      version = "~> 1"
    }
    vagrant = {
      source  = "github.com/hashicorp/vagrant"
      version = "~> 1"
    }
  }
}

variable "iso_checksum" {
  type        = string
  description = "The checksum for the ISO file"
  default     = "file:https://releases.ubuntu.com/noble/SHA256SUMS"
}

variable "iso_url" {
  type        = string
  description = "A URL to the ISO file"
  default     = "https://releases.ubuntu.com/noble/ubuntu-24.04.4-desktop-amd64.iso"
}

variable "iso_fallback_url" {
  type        = string
  description = "Fallback URL used when iso_url points to a missing local file"
  default     = "https://releases.ubuntu.com/noble/ubuntu-24.04.4-desktop-amd64.iso"
}

variable "output_dir" {
  type    = string
  default = "output"
}

variable "ssh_password" {
  type      = string
  sensitive = true
  default   = "packer"
}

variable "ssh_username" {
  type    = string
  default = "syselement"
}

variable "vm_cpu_cores" {
  type    = number
  default = 4
}

variable "vm_disk_size" {
  type    = number
  default = 61440 # Size in MB
}

variable "vm_memory" {
  type    = number
  default = 8192
}

variable "vm_name" {
  type    = string
  default = "ubuntu-24.04-x64-desktop-template"
}

locals {
  http_dir          = "${path.root}/http"
  effective_iso_url = can(regex("^[A-Za-z]:/", var.iso_url)) ? (fileexists(var.iso_url) ? var.iso_url : var.iso_fallback_url) : var.iso_url
}

source "vmware-iso" "ubuntu2404_desktop" {
  # Autoinstall over NoCloud, seeded from the local HTTP server.
  boot_wait = "5s"
  boot_command = [
    "<esc><wait>",
    "e<wait>",
    "<down><down><down><end>",
    " autoinstall ds=nocloud\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---",
    "<f10><wait>"
  ]

  communicator      = "ssh"
  cpus              = var.vm_cpu_cores
  disk_adapter_type = "scsi"
  disk_size         = var.vm_disk_size
  disk_type_id      = "0"
  guest_os_type     = "ubuntu-64"
  http_directory    = local.http_dir
  iso_checksum      = var.iso_checksum
  iso_url           = local.effective_iso_url
  memory            = var.vm_memory
  # Required since packer-plugin-vmware v2.1.6; builds fail validation without it.
  network_adapter_type = "vmxnet3"
  output_directory     = "${var.output_dir}/${var.vm_name}"
  shutdown_command     = "echo '${var.ssh_password}' | sudo -S shutdown -P now"
  shutdown_timeout     = "10m"
  skip_compaction      = false
  ssh_password         = var.ssh_password
  ssh_timeout          = "30m"
  ssh_username         = var.ssh_username
  usb                  = true
  vhv_enabled          = true # Enable nested virtualization
  version              = "21"
  vm_name              = var.vm_name
}

build {
  sources = ["source.vmware-iso.ubuntu2404_desktop"]
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; echo '${var.ssh_password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts = [
      "${path.root}/../../../scripts/ubuntu/00-update-system.sh",
      "${path.root}/../../../scripts/ubuntu/01-cleanup-system.sh"
    ]
  }

  post-processor "vagrant" {
    compression_level = 9
    output            = "${var.output_dir}/${var.vm_name}-vmware.box"
  }
}
