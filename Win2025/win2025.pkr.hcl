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

variable "box_output" {}
variable "boot_wait" {}
variable "disk_size" {}
variable "iso_checksum" {}
variable "iso_url" {}
variable "memsize" {}
variable "numvcpus" {}
variable "vm_name" {}
variable "ssh_password" {}
variable "ssh_username" {}

# Source blocks are generated from your builders; a source can be referenced in build blocks.
# A build block runs provisioner and post-processors on a source.
# Read the documentation for source blocks here:
# https://www.packer.io/docs/templates/hcl_templates/blocks/source

# Source block
source "vmware-iso" "winsrv2025" {
  boot_command     = ["<spacebar>"]
  boot_wait        = "${var.boot_wait}"
  communicator     = "ssh"
  disk_size        = "${var.disk_size}"
  disk_type_id     = "0"
  floppy_files     = ["config/autounattend.xml","scripts/packer_shutdown.bat"]
  guest_os_type    = "windows2022srvnext-64"
  headless         = false
  iso_checksum     = "${var.iso_checksum}"
  iso_url          = "${var.iso_url}"
  shutdown_command = "A:/packer_shutdown.bat" 
  shutdown_timeout = "30m"
  skip_compaction  = false
  vm_name          = "${var.vm_name}"
  vmx_data = {
    firmware            = "efi"
    memsize             = "${var.memsize}"
    numvcpus            = "${var.numvcpus}"
    "scsi0.virtualDev"  = "lsisas1068"
    "virtualHW.version" = "21"
  }
  ssh_password     = "${var.ssh_password}"
  ssh_port         = 22
  ssh_timeout      = "30m"
  ssh_username     = "${var.ssh_username}"
 
}

# A build block invokes sources and runs provisioning steps on them.
# The documentation for build blocks can be found here:
# https://www.packer.io/docs/templates/hcl_templates/blocks/build

# Build block
build {
  sources = ["source.vmware-iso.winsrv2025"]

  provisioner "powershell" {
    only         = ["vmware-iso.winsrv2025"]
    pause_before = "1m0s"
    scripts      = ["scripts/vmware_tools.ps1"]
  }

  provisioner "file" {
    source = "config/unattend.xml"
    destination = "C:/Windows/Panther/unattend.xml"
  }

  provisioner "powershell" {
    inline = ["New-Item -Path 'c:/' -Name 'tmp' -ItemType 'directory'"]
  }

  provisioner "file" {
    source = "scripts/startup.cmd"
    destination = "c:/tmp/startup.cmd"
  }

  provisioner "file" {
    source = "scripts/complete_config.ps1"
    destination = "c:/tmp/startup.ps1"
  }

  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  provisioner "powershell" {
    scripts = ["scripts/win_updates.ps1"]
  }

  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  provisioner "powershell" {
    scripts = ["scripts/win_updates.ps1"]
 }

  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  provisioner "powershell" {
    pause_before = "1m0s"
    scripts      = ["scripts/cleanup.ps1"]
  }

  post-processor "vagrant" {
    compression_level = 6
    output            = "${var.box_output}"
  }

}