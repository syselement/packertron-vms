// Description : Creating a virtual machine template under Ubuntu Server 26.04 LTS from ISO file with Packer using VMware Workstation
// Adapted from the 24.04 template in ../ubuntu-24.04-x64-server, which came from
// Yoann LAMY <https://github.com/ynlamy/packer-ubuntuserver24_04> (GPLv3).

// Packer : https://www.packer.io/

packer {
  required_version = ">= 1.7.0"
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
  default     = "https://releases.ubuntu.com/26.04.1/ubuntu-26.04.1-live-server-amd64.iso"
}

variable "checksum" {
  type        = string
  description = "The checksum for the ISO file"
  // The codename directory carries the SHA256SUMS for every point release in
  // the series, so this keeps working when iso is bumped to 26.04.2.
  default = "file:https://releases.ubuntu.com/resolute/SHA256SUMS"
}

variable "headless" {
  type        = bool
  description = "When this value is set to true, the machine will start without a console"
  default     = true
}

variable "name" {
  type        = string
  description = "This is the name of the new virtual machine"
  default     = "vm-ubuntuserver26_04"
}

// These must match the identity block in http/user-data, which is what the
// autoinstall actually creates. Mismatched values make every build wait out
// the 30m SSH timeout.
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

source "vmware-iso" "ubuntuserver26_04" {
  // Documentation : https://developer.hashicorp.com/packer/integrations/hashicorp/vmware/latest/components/builder/iso

  // ISO configuration
  iso_url      = var.iso
  iso_checksum = var.checksum

  // Hardware configuration
  vm_name       = var.name
  vmdk_name     = var.name
  version       = "21"
  guest_os_type = "ubuntu-64"
  // Set the CPU count here rather than through vmx_data: Packer generates
  // numvcpus itself, and overriding it there fights the builder.
  cpus              = 2
  memory            = 2048
  disk_size         = 30720
  disk_adapter_type = "scsi"
  disk_type_id      = "1"
  network           = "nat"
  // Required since packer-plugin-vmware v2.1.6; builds fail validation without it.
  network_adapter_type = "vmxnet3"
  sound                = false
  usb                  = false

  // Run configuration
  headless = var.headless

  // Shutdown configuration
  shutdown_command = "echo '${var.password}' | sudo -S systemctl poweroff"

  // Http directory configuration
  http_directory = "${path.root}/http"

  // Boot configuration
  boot_command = ["e<wait><down><down><down><end> autoinstall 'ds=nocloud;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/'<F10>"]
  boot_wait    = "10s"

  // Communicator configuration
  communicator = "ssh"
  ssh_username = var.username
  ssh_password = var.password
  ssh_timeout  = "30m"

  // Output configuration
  output_directory = "template"

  // Export configuration
  format          = "vmx"
  skip_compaction = false
}

build {
  sources = ["source.vmware-iso.ubuntuserver26_04"]

  // 00 has no library dependencies, so the shell provisioner can upload it on
  // its own.
  provisioner "shell" {
    execute_command = "echo '${var.password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts = [
      "${path.root}/../../scripts/ubuntu/00-update-system.sh"
    ]
  }

  // 02 sources scripts/ubuntu/lib/*.sh, which a "scripts" list cannot carry:
  // that uploads each file on its own, with no lib/ directory beside it. Stage
  // the whole tree first, the same way the Vagrantfiles do, and run it there.
  provisioner "shell" {
    inline = [
      "mkdir -p /var/tmp/packertron-ubuntu"
    ]
  }

  provisioner "file" {
    source      = "${path.root}/../../scripts/ubuntu/"
    destination = "/var/tmp/packertron-ubuntu/"
  }

  provisioner "shell" {
    execute_command = "echo '${var.password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    environment_vars = [
      "REBOOT_AT_END=false",
      "TARGET_USER=${var.username}"
    ]
    inline = [
      "bash /var/tmp/packertron-ubuntu/02-provision-system.sh"
    ]
  }

  // 01 seals the template, so it runs last: it truncates the machine-id and
  // clears /tmp and /var/tmp, and anything running after it would put
  // per-machine state straight back into the image. That /var/tmp sweep is
  // also what removes the staged tree above.
  provisioner "shell" {
    execute_command = "echo '${var.password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts = [
      "${path.root}/../../scripts/ubuntu/01-cleanup-system.sh"
    ]
  }
}
