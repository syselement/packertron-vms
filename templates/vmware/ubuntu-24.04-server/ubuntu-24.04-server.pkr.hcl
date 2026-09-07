# Ubuntu Server 24.04 LTS template for VMware Workstation, built from ISO.
# Author : Yoann LAMY <https://github.com/ynlamy/packer-ubuntuserver24_04>
# Licence : GPLv3
#
# Docs:
#   vmware-iso builder  https://developer.hashicorp.com/packer/integrations/hashicorp/vmware/latest/components/builder/iso
#   Autoinstall         https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html
#   README.md           build steps and the credential note
#
# Run:
#   packer init .
#   packer validate .
#   packer build .

packer {
  required_version = ">= 1.12.0"
  required_plugins {
    vmware = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/vmware"
    }
  }
}

variable "iso" {
  type        = string
  description = "A URL to the ISO file"
  default     = "https://releases.ubuntu.com/noble/ubuntu-24.04.4-live-server-amd64.iso"
}

variable "checksum" {
  type        = string
  description = "The checksum for the ISO file"
  # The codename directory carries SHA256SUMS for whichever point release is
  # current, so this keeps matching when iso is bumped. A literal sha256 does
  # not, and packer validate never downloads, so CI cannot catch the drift.
  default = "file:https://releases.ubuntu.com/noble/SHA256SUMS"
}

variable "headless" {
  type        = bool
  description = "When this value is set to true, the machine will start without a console"
  default     = true
}

variable "name" {
  type        = string
  description = "This is the name of the new virtual machine"
  default     = "vm-ubuntuserver24_04"
}

# Must match the identity block in http/user-data; a mismatch makes every
# build wait out the 30m SSH timeout.
variable "username" {
  type        = string
  description = "The username to connect to SSH"
  default     = "syselement"
}

variable "password" {
  type        = string
  description = "A plaintext password to authenticate with SSH"
  sensitive   = true
  default     = "packer"
}

source "vmware-iso" "ubuntuserver24_04" {
  iso_url      = var.iso
  iso_checksum = var.checksum

  vm_name       = var.name
  vmdk_name     = var.name
  version       = "21"
  guest_os_type = "ubuntu-64"
  # Set the CPU count here rather than through vmx_data: Packer generates
  # numvcpus itself, and overriding it there fights the builder.
  cpus                 = 2
  memory               = 2048
  disk_size            = 30720
  disk_adapter_type    = "scsi"
  disk_type_id         = "1"
  network              = "nat"
  network_adapter_type = "vmxnet3"
  sound                = false
  usb                  = false

  headless = var.headless

  shutdown_command = "echo '${var.password}' | sudo -S systemctl poweroff"

  http_directory = "${path.root}/http"

  boot_command = [
    "<esc><wait>",
    "e<wait>",
    "<down><down><down><end>",
    " autoinstall ds=nocloud\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---",
    "<f10><wait>"
  ]
  boot_wait = "10s"

  communicator = "ssh"
  ssh_username = var.username
  ssh_password = var.password
  ssh_timeout  = "30m"

  output_directory = "output"

  format          = "vmx"
  skip_compaction = false
}

build {
  sources = ["source.vmware-iso.ubuntuserver24_04"]

  # 00 has no library dependencies, so the shell provisioner can upload it on
  # its own.
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; echo '${var.password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts = [
      "${path.root}/../../../scripts/ubuntu/00-update-system.sh"
    ]
  }

  # 02 sources scripts/ubuntu/lib/*.sh, which a "scripts" list cannot carry -
  # it uploads each file alone, with no lib/ beside it. Stage the whole tree.
  provisioner "shell" {
    inline = [
      "mkdir -p /var/tmp/packertron-ubuntu"
    ]
  }

  provisioner "file" {
    source      = "${path.root}/../../../scripts/ubuntu/"
    destination = "/var/tmp/packertron-ubuntu/"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; echo '${var.password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    environment_vars = [
      "REBOOT_AT_END=false",
      "TARGET_USER=${var.username}"
    ]
    inline = [
      "bash /var/tmp/packertron-ubuntu/02-provision-system.sh"
    ]
  }

  # 01 must run last: it truncates the machine-id and clears /tmp and
  # /var/tmp, so anything after it puts per-machine state back into the image.
  # That sweep is also what removes the staged tree above.
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; echo '${var.password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts = [
      "${path.root}/../../../scripts/ubuntu/01-cleanup-system.sh"
    ]
  }
}
