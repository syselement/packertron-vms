packer {
  required_plugins {
    qemu = {
      version = "~> 1"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "password" {
  type    = string
  default = "ubuntu"
}

source "qemu" "ubuntu" {
  iso_url      = "https://releases.ubuntu.com/22.04.4/ubuntu-22.04.4-live-server-amd64.iso"
  iso_checksum = "file:https://releases.ubuntu.com/22.04.4/SHA256SUMS"

  vm_name             = "ubuntu.qcow2"
  format              = "qcow2"
  output_directory    = "output"
  shutdown_command    = "echo '${var.password}' | sudo -S shutdown -P now"

  # Comment next line on MacOS
  accelerator         = "kvm"
  cpus                = 4
  memory              = 4096
  use_default_display = true
  # To not run Qemu window. For Debuging set the value to `false`
  headless            = true

  http_directory = "http"
  ssh_username   = "ubuntu"
  ssh_password   = var.password
  ssh_timeout    = "20m"

  boot_wait = "3s"
  boot_command = [
    "c<wait>linux /casper/vmlinuz --- autoinstall 'ds=nocloud;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/'<enter><wait>",
    "initrd /casper/initrd<enter><wait><wait>",
    "boot<enter><wait>"
  ]
}

build {
  name    = "ubuntu"
  sources = ["source.qemu.ubuntu-2204"]
}

