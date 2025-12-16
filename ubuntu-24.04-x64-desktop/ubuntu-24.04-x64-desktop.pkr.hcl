# Description: Packer template to build an Ubuntu 24.04 Desktop VMware VM and package as Vagrant box
# 
# https://developer.hashicorp.com/packer/integrations/hashicorp/vmware/latest/components/builder/iso

# Required plugins to run this template
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

# Variables
variable "iso_url" {
  type        = string
  description = "A URL to the ISO file"
  default     = "https://releases.ubuntu.com/noble/ubuntu-24.04.3-desktop-amd64.iso"
}

variable "iso_checksum" {
  type        = string
  description = "The checksum for the ISO file"
  default     = "file:https://releases.ubuntu.com/noble/SHA256SUMS"
}

variable "vm_name" {
  type    = string
  default = "ubuntu-24.04-x64-desktop-template"
}

variable "vm_cpu_cores" {
  type    = number
  default = 4
}

variable "vm_memory" {
  type    = number
  default = 8192
}

variable "vm_disk_size" {
  type    = number
  default = 61440 # Size in MB
}

variable "ssh_username" {
  type    = string
  default = "syselement"
}

variable "ssh_password" {
  type      = string
  sensitive = true
  default   = "packer"
}

variable "output_dir" {
  type    = string
  default = "output"
}

# Local values
locals {
  http_dir = "${path.root}/http"
}

# Source block
source "vmware-iso" "ubuntu2404_desktop" {
  # ISO configuration
  iso_checksum = var.iso_checksum
  iso_url      = var.iso_url
  output_directory   = "${var.output_dir}/${var.vm_name}"

  # VM Hardware configuration
  cpus               = var.vm_cpu_cores
  disk_adapter_type  = "scsi"
  disk_size          = var.vm_disk_size
  disk_type_id       = "0"
  guest_os_type      = "ubuntu-64"
  memory             = var.vm_memory
  version            = "21" # https://knowledge.broadcom.com/external/article?articleNumber=315655
  vhv_enabled        = true
  vm_name            = var.vm_name
  usb                = true
  sound              = true

  # Communicator configuration
  communicator   = "ssh"
  ssh_username   = var.ssh_username
  ssh_password   = var.ssh_password
  ssh_timeout    = "30m"

  # Shutdown configuration
  shutdown_command = "echo '${var.ssh_password}' | sudo -S shutdown -P now"
  shutdown_timeout = "10m"
  skip_compaction = false

  # VMware + Packer HTTP server to provide user-data/meta-data/scripts
  http_directory = local.http_dir

  # Boot configuration
  # Ubuntu 24.04 Desktop autoinstall via NoCloud-Net and local HTTP server
  boot_wait = "5s"
  boot_command = [
    "e<wait>",
    "<down><down><down><end>",
    " autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---",
    "<f10><wait>"
  ]
}

# Build block
build {
  sources = ["source.vmware-iso.ubuntu2404_desktop"]

  # Provisioning script
  provisioner "shell" {
    execute_command="echo '${var.ssh_password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts = [
      "${path.root}/scripts/update_system.sh",
      "${path.root}/scripts/cleanup_system.sh"
    ]
  }

  # Package as Vagrant box
  post-processor "vagrant" {
    compression_level = 9
    output = "${var.output_dir}/${var.vm_name}-vmware.box"
  }
}