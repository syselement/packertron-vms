# Ubuntu 26.04 Desktop template for VMware Workstation, packaged as a Vagrant box.
# STATUS: unverified. The 26.04 build stopped on subiquity bug 2150197
# (https://bugs.launchpad.net/subiquity/+bug/2150197); the Proxmox desktop
# template builds from 26.04.1, and this one is to be retested with it.
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
  required_version = ">= 1.12.0"
  required_plugins {
    vmware = {
      source  = "github.com/hashicorp/vmware"
      version = "~> 2.1"
    }
    vagrant = {
      source  = "github.com/hashicorp/vagrant"
      version = "~> 1.1"
    }
  }
}

variable "iso_checksum" {
  type        = string
  description = "Checksum of iso_url: sha256:<hex>, file:<SHA256SUMS URL>, or the bare hex"
  default     = "file:https://releases.ubuntu.com/resolute/SHA256SUMS"
}

variable "iso_url" {
  type        = string
  description = "ISO to install from: a URL, or a path on the build host"
  default     = "https://releases.ubuntu.com/26.04.1/ubuntu-26.04.1-desktop-amd64.iso"
}

variable "iso_fallback_url" {
  type        = string
  description = "Fallback URL used when iso_url points to a missing local file"
  default     = "https://releases.ubuntu.com/26.04.1/ubuntu-26.04.1-desktop-amd64.iso"
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

# The public key the seed authorizes for that account. Nothing is committed
# in its place: export PKR_VAR_ssh_authorized_key, or pass
# -var ssh_authorized_key=.... Its comment may hold no quote, dollar sign
# or backslash, which the seed would have to escape.
variable "ssh_authorized_key" {
  type        = string
  description = "Public key the seed authorizes, as one authorized_keys line"

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\\.com|sk-ecdsa-sha2-nistp256@openssh\\.com) [A-Za-z0-9+/]+={0,3}( [^'\"\\\\$`]*)?$", var.ssh_authorized_key))
    error_message = "Set ssh_authorized_key to one public key line, such as the content of ~/.ssh/id_ed25519.pub, with no quote, dollar sign or backslash in its comment."
  }
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
  default = "ubuntu-26.04-x64-desktop-template"
}

locals {
  http_dir          = "${path.root}/http"
  effective_iso_url = can(regex("^[A-Za-z]:/", var.iso_url)) ? (fileexists(var.iso_url) ? var.iso_url : var.iso_fallback_url) : var.iso_url
}

source "vmware-iso" "ubuntu2604_desktop" {
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
  # Served from memory rather than http/ on disk, so the seed authorizes
  # var.ssh_authorized_key instead of a key committed to the repository.
  http_content = {
    "/user-data" = replace(file("${local.http_dir}/user-data"), "@SSH_AUTHORIZED_KEY@", var.ssh_authorized_key)
    "/meta-data" = file("${local.http_dir}/meta-data")
  }
  iso_checksum = var.iso_checksum
  iso_url      = local.effective_iso_url
  memory       = var.vm_memory
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
  sources = ["source.vmware-iso.ubuntu2604_desktop"]
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
