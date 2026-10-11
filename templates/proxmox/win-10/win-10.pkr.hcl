# Windows 10 template for Proxmox VE: ISO + answer file, generalized with
# sysprep and configured per clone by cloudbase-init.
# Adapted from https://github.com/mttaggart/seclab (Packer/win-11-ws/config.pkr.hcl).
#
# Docs:
#   proxmox-iso builder  https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox/latest/components/builder/iso
#   Answer files         https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/
#   README.md            the ISO it expects, and from template to deployed VM
#   ../WINDOWS.md        the build chain and the clone-time model, shared
#
# Run:
#   export PKR_VAR_proxmox_api_token_id="user@pve!token"
#   export PKR_VAR_proxmox_api_token_secret="..."
#   packer init .
#   packer validate -var-file=../proxmox.pkrvars.hcl .
#   packer build    -var-file=../proxmox.pkrvars.hcl .

packer {
  required_version = ">= 1.12.0"
  required_plugins {
    proxmox = {
      version = ">= 1.2.1, < 2.0.0"
      source  = "github.com/hashicorp/proxmox"
    }
    # Pinned exactly: third-party, and it runs as SYSTEM on the build VM.
    windows-update = {
      version = "0.18.5"
      source  = "github.com/rgl/windows-update"
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

# The evaluation ISO, staged on the node under its upstream name - README.md
# says where to get it. Packer does not check a staged ISO. Set this to "" to
# have it download var.iso and check it against var.checksum instead.
variable "iso_file" {
  type        = string
  description = "ISO already on the node, as storage:iso/name.iso; \"\" downloads var.iso"
  default     = "local:iso/19045.2006.220908-0225.22h2_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso"
}

variable "iso" {
  type        = string
  description = "A URL to the ISO; used only when iso_file is empty"
  default     = "https://software-static.download.prss.microsoft.com/dbazure/988969d5-f34g-4e03-ac9d-1f9786c66750/19045.2006.220908-0225.22h2_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso"
}

variable "checksum" {
  type        = string
  description = "Checksum for var.iso, e.g. sha256:<hash>; unused for a staged iso_file"
  default     = "sha256:ef7312733a9f5d7d51cfa04ac497671995674ca5e1058d5164d6028f0938d668"
}

# The edition to install, by its index in install.wim - `wiminfo
# sources/install.wim` lists them. Evaluation media carries one edition at
# index 1.
variable "image_index" {
  type        = number
  description = "Index of the edition to install in the ISO's install.wim"
  default     = 1
}

variable "product_key" {
  type        = string
  description = "Product key for non-evaluation media; empty omits it"
  sensitive   = true
  default     = ""
}

# Pinned: folder layouts change between virtio-win releases, and the answer
# file names folders. Fedora publishes no checksum for the ISO itself, so this
# one was computed from the release when it was pinned. virtio_iso_file uses a
# copy already on the node instead.
variable "virtio_iso" {
  type        = string
  description = "virtio-win ISO URL"
  default     = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.302-1/virtio-win-0.1.302.iso"
}

variable "virtio_checksum" {
  type        = string
  description = "Checksum of the virtio-win ISO"
  default     = "sha256:303f7ae40dad495d6ae474fdc571df58958a4dbc5c37a522d80f9a203867949d"
}

variable "virtio_iso_file" {
  type        = string
  description = "virtio-win ISO already on the node, as storage:iso/name.iso; empty downloads var.virtio_iso"
  default     = ""
}

variable "iso_storage_pool" {
  type        = string
  description = "Proxmox storage that holds ISO images"
  default     = "local"
}

variable "storage_pool" {
  type        = string
  description = "Proxmox storage for the VM disk, EFI vars, TPM state and the cloud-init drive"
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
  default     = 80310
}

variable "template_name" {
  type        = string
  description = "Name of the resulting template"
  default     = "win-10-template"
}

# Seconds of Enter presses at boot. The ISO boots only on a keypress, at a
# "Press any key to boot from CD or DVD" prompt that appears a few seconds after
# power-on and waits about five. Presses still arriving once Windows Setup is on
# screen land on its focused Cancel button and leave an "Are you sure you want to
# quit?" dialog open, which stalls the install for good. Raise this if the VM
# ends at the UEFI shell; lower it if that dialog appears.
variable "boot_key_seconds" {
  type        = number
  description = "Seconds of Enter presses sent at boot to catch the ISO's keypress prompt"
  default     = 15
}

# Normally empty: the builder asks the qemu guest agent for the VM's address.
# That query needs VM.GuestAgent.Audit on the token's role; without it the
# lookup returns nothing and the build sits on "Waiting for SSH" forever.
# Setting this skips the lookup.
variable "ssh_host" {
  type        = string
  description = "Address to reach the build VM on; empty asks the guest agent"
  default     = ""
}

# Unlike the Linux templates this one logs in with it: Windows has no seed that
# could hand the VM a key before the first SSH connection. It never reaches a
# clone - cloudbase-init replaces it on the first boot.
variable "ssh_password" {
  type        = string
  description = "Build-time password for the built-in Administrator"
  sensitive   = true
  default     = "packer"
}

# Shared with the Linux templates through ../proxmox.pkrvars.hcl and unused
# here: the Windows build logs in with ssh_password, and a clone takes its
# keys from the cloud-init drive. Declared so the shared file sets no
# undeclared variable.
variable "ssh_authorized_key" {
  type        = string
  description = "Unused by the Windows templates; see the Linux ones"
  default     = ""
}

locals {
  # Escaped once here, since the answer file drops it into XML text.
  xml_password = replace(replace(replace(var.ssh_password, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")

  # The account cloudbase-init manages on a clone, and whether it renames the
  # built-in Administrator to it. scripts/windows/cloudbase-init/ has the rest.
  cloudbase_init = {
    username          = "syselement"
    rename_admin_user = true
  }
}

source "proxmox-iso" "win-10" {
  proxmox_url              = var.proxmox_api_url
  node                     = var.proxmox_node
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = var.insecure_skip_tls_verify

  # The three CDs go on sata0, sata1, sata2 in this order, and the answer file
  # finds the virtio drivers at F: because of it. SATA rather than the SCSI the
  # Linux templates boot from: Windows setup has an inbox AHCI driver and no
  # virtio one, so it could not read its own ISO off a virtio-scsi CD.
  boot_iso {
    type             = "sata"
    index            = 0
    iso_file         = var.iso_file
    iso_url          = var.iso_file == "" ? var.iso : ""
    iso_checksum     = var.checksum
    iso_storage_pool = var.iso_storage_pool
    unmount          = true
  }

  additional_iso_files {
    type             = "sata"
    index            = 1
    cd_label         = "UNATTEND"
    iso_storage_pool = var.iso_storage_pool
    unmount          = true
    cd_content = {
      "autounattend.xml" = templatefile("${path.root}/../autounattend.pkrtpl.xml", {
        password    = local.xml_password
        virtio_os   = "w10"
        image_index = var.image_index
        product_key = var.product_key
      })
      "00_firstlogon.ps1" = file("${path.root}/../../../scripts/windows/00_firstlogon.ps1")
    }
  }

  additional_iso_files {
    type             = "sata"
    index            = 2
    iso_file         = var.virtio_iso_file
    iso_url          = var.virtio_iso_file == "" ? var.virtio_iso : ""
    iso_checksum     = var.virtio_checksum
    iso_storage_pool = var.iso_storage_pool
    unmount          = true
  }

  vm_id           = var.vm_id
  vm_name         = var.template_name
  cores           = 4
  memory          = 4096
  cpu_type        = "host"
  scsi_controller = "virtio-scsi-single"
  qemu_agent      = true

  # Not cosmetic: a Windows ostype is what makes Proxmox write the clone's
  # cloud-init drive as configdrive2, the format cloudbase-init reads, and pass
  # its password in plain text rather than hashed. Proxmox's win10 covers
  # Windows 10; win11 covers Windows 11 and Server 2022 and 2025.
  os = "win10"

  machine = "q35"
  bios    = "ovmf"

  template_name        = var.template_name
  template_description = "Windows 10, built by Packer on ${timestamp()}. q35/OVMF/TPM 2.0. Sysprepped: clones configure themselves through cloudbase-init."

  # Secure Boot and a TPM 2.0: required by Windows 11, and kept on 10 and Server
  # 2025 so the three Windows templates stay identical here. pre_enrolled_keys
  # is true, unlike the Linux templates: Windows is signed by the keys it enrols.
  efi_config {
    efi_storage_pool  = var.storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = true
  }

  tpm_config {
    tpm_storage_pool = var.storage_pool
    tpm_version      = "v2.0"
  }

  # scsi0 is what deploy/main.tf's disk block expects. 64G is Windows 11's
  # minimum, and more than 10 or Server 2025 need.
  disks {
    type         = "scsi"
    disk_size    = "64G"
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

  # SPICE (qxl), so the Proxmox console offers SPICE as well as noVNC. The
  # virtio-win guest tools install its display driver and agent.
  vga {
    type   = "qxl"
    memory = 32
  }

  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  # -1s means no initial wait: the presses start with the VM. Why they must also
  # stop early is under var.boot_key_seconds.
  boot_wait    = "-1s"
  boot_command = [for i in range(var.boot_key_seconds) : "<return><wait>"]

  communicator = "ssh"
  ssh_host     = var.ssh_host
  ssh_username = "Administrator"
  ssh_password = var.ssh_password
  # Setup, the first logon and - except on Server, which ships it - an OpenSSH
  # Server download from Windows Update all happen before port 22 answers.
  ssh_timeout = "60m"

  # A Proxmox task timeout, not an SSH one: the final imgcopy that converts
  # the VM into a template exceeds the 1m default on a busy or slow pool.
  task_timeout = "20m"
}

build {
  sources = ["source.proxmox-iso.win-10"]

  # Machine-wide settings: Edge, diagnostic data, power plan, password expiry.
  provisioner "powershell" {
    scripts = ["${path.root}/../../../scripts/windows/09_system_settings.ps1"]
  }

  # Installs, restarts and searches again until nothing is left, restarting
  # again while a reboot is still pending - a cumulative update's second stage
  # is one. A download that fails is retried, then fails the build.
  provisioner "windows-update" {
    filters = [
      "exclude:$_.Title -like '*Preview*'",
      # The plugin's own templates exclude the Defender platform update: it can
      # stay applicable after installing and repeat the loop forever. Defender
      # updates its platform itself.
      "exclude:$_.Title -like '*KB5007651*'",
      "include:$true",
    ]
    restart_timeout = "30m"
  }

  # A last check before sysprep; 12_sysprep.ps1 also refuses a pending reboot.
  provisioner "powershell" {
    scripts = ["${path.root}/../../../scripts/windows/10_wait_for_servicing.ps1"]
  }

  provisioner "file" {
    content     = templatefile("${path.root}/../../../scripts/windows/cloudbase-init/cloudbase-init.pkrtpl.conf", local.cloudbase_init)
    destination = "C:/Windows/Temp/cloudbase-init.conf"
  }

  provisioner "file" {
    content     = templatefile("${path.root}/../../../scripts/windows/cloudbase-init/cloudbase-init-unattend.pkrtpl.conf", { username = local.cloudbase_init.username })
    destination = "C:/Windows/Temp/cloudbase-init-unattend.conf"
  }

  provisioner "file" {
    source      = "${path.root}/../../../scripts/windows/cloudbase-init/Unattend.xml"
    destination = "C:/Windows/Panther/unattend.xml"
  }

  provisioner "powershell" {
    scripts = ["${path.root}/../../../scripts/windows/11_cloudbase_init.ps1"]
  }

  # Must run last.
  provisioner "powershell" {
    scripts = [
      "${path.root}/../../../scripts/windows/03_cleanup.ps1",
      "${path.root}/../../../scripts/windows/12_sysprep.ps1"
    ]
  }
}
