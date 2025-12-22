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

# -------------------------------------------------

# Variables
variable "box_output" {
  type        = string
  description = "The output path for the box file"
  default     = ""
}

variable "vm_disk_size" {
  type        = string
  description = "The disk size for the VM in MB"
  default     = "61440"
}

# Windows Server 2025 ISO details
# Use Get-FileHash to generate the ISO checksum
# Example: Get-FileHash .\26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso
variable "iso_checksum" {
  type        = string
  description = "The checksum for the ISO file"
  default     = "D0EF4502E350E3C6C53C15B1B3020D38A5DED011BF04998E950720AC8579B23D"
}

variable "iso_url" {
  type        = string
  description = "A URL to the ISO file"
  default     = "https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
}

variable "vm_memory" {
  type        = string
  description = "The memory size for the VM in MB"
  default     = "8192"
}

variable "vm_cpu_cores" {
  type        = string
  description = "The number of vCPUs for the VM"
  default     = "4"
}

variable "ssh_password" {
  type        = string
  description = "The password for SSH access"
  sensitive   = true
  default     = "packer"
}

variable "ssh_username" {
  type        = string
  description = "The username for SSH access"
  default     = "Administrator"
}

variable "vm_name" {
  type        = string
  description = "The name of the virtual machine"
  default     = "Win2025VM"
}

# -------------------------------------------------
# Source blocks are generated from your builders; a source can be referenced in build blocks.
# A build block runs provisioner and post-processors on a source.
# Read the documentation for source blocks here:
# https://www.packer.io/docs/templates/hcl_templates/blocks/source

# Source block
source "vmware-iso" "winsrv2025" {
  boot_command     = ["<spacebar>"]
  boot_wait        = "2s"
  communicator     = "ssh"
  cpus             = var.vm_cpu_cores
  disk_size        = var.vm_disk_size
  disk_type_id     = "0"
  floppy_files     = ["config/autounattend.xml","scripts/packer_shutdown.bat"]
  guest_os_type    = "windows2022srvnext-64"
  headless         = false
  iso_checksum     = var.iso_checksum
  iso_url          = var.iso_url
  memory           = var.vm_memory
  shutdown_command = "A:/packer_shutdown.bat" 
  shutdown_timeout = "30m"
  skip_compaction  = false
  version            = "21" # https://knowledge.broadcom.com/external/article?articleNumber=315655
  vm_name          = var.vm_name
  vmx_data = {
    firmware            = "efi"
    "scsi0.virtualDev"  = "lsisas1068" # Autounattend requires SCSI hard disk controller to be LSI Logic SAS
    "isolation.tools.hgfs.disable" = "TRUE"
  }
  ssh_password     = var.ssh_password
  ssh_port         = 22
  ssh_timeout      = "30m"
  ssh_username     = var.ssh_username
}

# -------------------------------------------------
# A build block invokes sources and runs provisioning steps on them.
# The documentation for build blocks can be found here:
# https://www.packer.io/docs/templates/hcl_templates/blocks/build

# Build block
build {
  sources = ["source.vmware-iso.winsrv2025"]

  provisioner "powershell" {
    only         = ["vmware-iso.winsrv2025"]
    pause_before = "1m0s"
    scripts      = ["scripts/01_vmware_tools.ps1"]
  }

  # Copy unattend.xml to the VM for the final sysprep shutdown step in the packer_shutdown.bat script
  provisioner "file" {
    source = "config/unattend.xml"
    destination = "C:/Windows/Panther/unattend.xml"
  }

  # Startup scripts used in the unattend.xml to run during first boot after complete deployment/sysprep
  provisioner "powershell" {
    inline = ["New-Item -Path 'c:/' -Name 'tmp' -ItemType 'directory'"]
  }

  provisioner "file" {
    source = "scripts/04_startup.cmd"
    destination = "c:/tmp/startup.cmd"
  }

  provisioner "file" {
    source = "scripts/04_startup.ps1"
    destination = "c:/tmp/startup.ps1"
  }

  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  # First round of Windows Updates
  provisioner "powershell" {
    scripts = ["scripts/02_win_updates.ps1"]
  }

  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  # Second round of Windows Updates
  provisioner "powershell" {
    scripts = ["scripts/02_win_updates.ps1"]
  }

  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  # Final cleanup before packaging the box
  provisioner "powershell" {
    pause_before = "1m0s"
    scripts      = ["scripts/03_cleanup.ps1"]
  }

  post-processor "vagrant" {
    compression_level = 9
    output            = "${var.box_output}"
  }

}