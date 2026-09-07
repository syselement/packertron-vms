// Ubuntu Server 24.04 LTS template for Proxmox VE, built from the ISO with
// autoinstall and sealed for cloning.
//
// The template is deliberately thin: base OS, qemu-guest-agent, cloud-init
// left able to run again. Tooling is NOT baked in. 02-provision-system.sh and
// 03-customize-system.sh run per VM at first boot, so a clone created months
// from now still picks up the current scripts rather than whatever was current
// when this template was built.
//
// Node settings - url, node name, storage pools, bridge - come from the
// shared ../proxmox.pkrvars.hcl, which is gitignored and copied from the
// .example beside it. Credentials come from the environment, never from any
// file in this repository:
//
//   export PKR_VAR_proxmox_api_token_id="packer@pve!templates"
//   export PKR_VAR_proxmox_api_token_secret="..."
//   export PKR_VAR_ssh_password="..."
//
// Build with:
//   packer init .
//   packer build -var-file=../proxmox.pkrvars.hcl .

packer {
  required_version = ">= 1.12.0"
  required_plugins {
    proxmox = {
      version = ">= 1.2.1"
      source  = "github.com/hashicorp/proxmox"
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

variable "iso" {
  type        = string
  description = "A URL to the ISO file; Packer downloads it to iso_storage_pool"
  default     = "https://releases.ubuntu.com/noble/ubuntu-24.04.4-live-server-amd64.iso"
}

variable "checksum" {
  type        = string
  description = "The checksum for the ISO file"
  default     = "file:https://releases.ubuntu.com/noble/SHA256SUMS"
}

variable "iso_storage_pool" {
  type        = string
  description = "Proxmox storage that holds ISO images"
  default     = "local"
}

variable "storage_pool" {
  type        = string
  description = "Proxmox storage for the VM disk and the cloud-init drive"
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
  default     = 80024
}

// How long to wait after power-on before typing the boot command. OVMF posts
// more slowly than SeaBIOS, so if the installer never starts, this is the
// first thing to raise: the keystrokes went into the firmware splash instead
// of the GRUB menu. Tunable from the command line - `-var 'boot_wait=20s'` -
// so finding the right value does not mean editing this file.
variable "boot_wait" {
  type        = string
  description = "Delay before the boot command is typed"
  default     = "10s"
}

// Which local address Packer serves the autoinstall seed from. Empty lets
// Packer choose, which is right on a machine with one route to the node.
//
// It guesses badly on a workstation carrying docker0, virbr0 and VPN
// interfaces: it can land on 172.17.0.1, the installer cannot reach it, and
// the build stalls at the installer with no error - Packer is serving happily,
// on an address the VM has never heard of. Set it to the address on the same
// network as the node: -var 'http_bind_address=192.168.5.101'.
variable "http_bind_address" {
  type        = string
  description = "Local address to serve http/ from; empty means let Packer choose"
  default     = ""
}

variable "template_name" {
  type        = string
  description = "Name of the resulting template"
  default     = "ubuntu-24.04-server-template"
}

// Must match the identity block in http/user-data, which is what the
// autoinstall actually creates. Mismatched values make every build wait out
// the SSH timeout.
variable "ssh_username" {
  type        = string
  description = "The username to connect to SSH"
  default     = "syselement"
}

// NOT used to log in. http/user-data sets `allow-pw: false`, so subiquity
// writes PasswordAuthentication no and sshd rejects passwords outright - a
// build that tried one would sit out the whole ssh_timeout and then fail with
// nothing useful in the log. This value is only piped into `sudo -S` by the
// provisioners below, and even there the seed's NOPASSWD sudoers means sudo
// never reads it.
variable "ssh_password" {
  type        = string
  description = "Password fed to sudo -S by the provisioners; not used for SSH login"
  sensitive   = true
  default     = "packer"
}

source "proxmox-iso" "ubuntu-24-04-server" {
  // Documentation : https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox/latest/components/builder/iso

  // Connection
  proxmox_url              = var.proxmox_api_url
  node                     = var.proxmox_node
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = var.insecure_skip_tls_verify

  // Boot media
  boot_iso {
    type             = "scsi"
    iso_url          = var.iso
    iso_checksum     = var.checksum
    iso_storage_pool = var.iso_storage_pool
    unmount          = true
  }

  // Hardware
  vm_id           = var.vm_id
  vm_name         = var.template_name
  cores           = 1
  memory          = 2048
  cpu_type        = "host"
  os              = "l26"
  scsi_controller = "virtio-scsi-single"
  qemu_agent      = true

  // q35 with OVMF, rather than the i440fx Proxmox defaults to. i440fx models a
  // 1996 chipset with no native PCIe; pairing it with UEFI works but is the
  // odd combination. q35 is the modern pairing and what a clone of this
  // template should look like going forward.
  //
  // Proxmox still exposes ide2 on q35, which is where the cloud-init drive
  // lands, so cloud_init below is unaffected.
  machine = "q35"
  bios    = "ovmf"

  // The artifact this build leaves behind on the node.
  template_name        = var.template_name
  template_description = "Ubuntu Server 24.04 LTS, built by Packer. q35/OVMF. Thin: 02 and 03 run at first boot."

  // OVMF needs somewhere to keep its variable store, and Proxmox will not
  // start an ovmf VM without one. It goes on the same pool as the disk rather
  // than getting its own variable: it is 4MB, and a node that can hold the
  // disk can hold this.
  //
  // pre_enrolled_keys stays false, matching the VMs already on this node. With
  // it true the firmware ships Microsoft's Secure Boot keys enrolled, which
  // only helps if everything that ever boots here is signed for them - and it
  // is the usual cause of a template that installs cleanly and then refuses to
  // boot as a clone.
  efi_config {
    efi_storage_pool  = var.storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = false
  }

  disks {
    type         = "scsi"
    disk_size    = "30G"
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

  // A cloud-init drive is what makes the template useful: OpenTofu sets the
  // per-VM hostname, user, keys and network on it at clone time, and the
  // first-boot provisioning is delivered the same way.
  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  // Autoinstall seed, served by Packer's own HTTP server
  http_directory    = "${path.root}/http"
  http_bind_address = var.http_bind_address
  boot_command = [
    "<esc><wait>",
    "e<wait>",
    "<down><down><down><end>",
    " autoinstall ds=nocloud\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---",
    "<f10><wait>"
  ]
  boot_wait = var.boot_wait

  // Communicator
  // Authentication goes through the SSH agent, not a password and not a key
  // file. The seed authorises one ed25519 public key and disables password
  // auth, and Packer's communicator has no way to unlock a passphrase
  // protected key - ssh_private_key_file fails validation outright on one.
  // The agent already holds the unlocked key, so it is the only option that
  // needs no passphrase-less copy of a personal key lying on disk.
  //
  // Before building: `ssh-add -l` must list the key whose public half is in
  // http/user-data. For an unattended runner, generate a dedicated
  // passphrase-less build key, authorise it in the seed, and swap this for
  // ssh_private_key_file instead.
  ssh_username   = var.ssh_username
  ssh_agent_auth = true
  ssh_timeout    = "30m"
}

build {
  sources = ["source.proxmox-iso.ubuntu-24-04-server"]

  // Every execute_command here keeps Packer's own `chmod +x {{ .Path }};`
  // prefix. Packer uploads a provisioner script without the execute bit and
  // relies on the default execute_command to add it, so overriding that
  // command - as these do, to pipe a password into sudo - has to put it back
  // or the script fails with "permission denied" before it runs a line.
  //
  // 00 installs the guest agent for the detected hypervisor; on Proxmox that
  // is qemu-guest-agent. It has no library dependencies, so the shell
  // provisioner can upload it on its own.
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; echo '${var.ssh_password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts = [
      "${path.root}/../../../scripts/ubuntu/00-update-system.sh"
    ]
  }

  // 01 seals what every template needs sealed: it truncates the machine-id and
  // clears cloud-init state, which is what lets every clone be treated as a
  // fresh instance and read the cloud-init drive Proxmox attaches to it.
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; echo '${var.ssh_password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts = [
      "${path.root}/../../../scripts/ubuntu/01-cleanup-system.sh"
    ]
  }

  // Sealing that only a clone needs, and the last thing to touch the image.
  // The reasoning lives in the script; it is a file rather than an inline
  // block so that shellcheck and shfmt can see it, like every other script
  // here. It sits one level up because every Proxmox template needs the same
  // seal.
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; echo '${var.ssh_password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts = [
      "${path.root}/../seal-for-clone.sh"
    ]
  }
}
