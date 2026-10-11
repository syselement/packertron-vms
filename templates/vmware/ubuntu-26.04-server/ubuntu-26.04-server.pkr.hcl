# Ubuntu Server 26.04 LTS for VMware Workstation, installed from the ISO by
# autoinstall and provisioned at build time with scripts/ubuntu/.
#
# Docs:
#   vmware-iso builder  https://developer.hashicorp.com/packer/integrations/hashicorp/vmware/latest/components/builder/iso
#   Autoinstall         https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html
#   Reference           https://github.com/ynlamy/packer-ubuntuserver24_04
#   README.md           what this build bakes in, and the credential note
#
# Run:
#   packer init .
#   packer validate .
#   packer build .

packer {
  required_version = ">= 1.12.0"
  required_plugins {
    vmware = {
      version = "~> 2.1"
      source  = "github.com/hashicorp/vmware"
    }
  }
}

variable "iso" {
  type        = string
  description = "Ubuntu Server ISO to download, checked against var.checksum"
  default     = "https://releases.ubuntu.com/26.04.1/ubuntu-26.04.1-live-server-amd64.iso"
}

variable "checksum" {
  type        = string
  description = "Where var.iso's checksum comes from: sha256:<hex>, or file:<SHA256SUMS URL>"
  # The codename directory carries SHA256SUMS for whichever point release is
  # current, so this keeps matching when iso is bumped.
  default = "file:https://releases.ubuntu.com/resolute/SHA256SUMS"
}

variable "headless" {
  type        = bool
  description = "Build without opening the VM's console window"
  default     = true
}

variable "name" {
  type        = string
  description = "Name of the VM, and of its disk file"
  default     = "ubuntu-26.04-server"
}

# Must match the identity block in http/user-data; a mismatch makes every
# build wait out the 30m SSH timeout.
variable "username" {
  type        = string
  description = "Account the seed creates, which Packer logs in as"
  default     = "syselement"
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

variable "password" {
  type        = string
  description = "That account's password, the plaintext of the hash in http/user-data"
  sensitive   = true
  default     = "packer"
}

source "vmware-iso" "ubuntu" {
  iso_url      = var.iso
  iso_checksum = var.checksum

  vm_name       = var.name
  vmdk_name     = var.name
  version       = "21"
  guest_os_type = "ubuntu-64"
  # Set the CPU count here rather than through vmx_data: Packer generates
  # numvcpus itself, and overriding it there fights the builder.
  cpus              = 2
  memory            = 2048
  disk_size         = 30720
  disk_adapter_type = "scsi"
  disk_type_id      = "1"
  network           = "nat"
  # Required since packer-plugin-vmware v2.1.6; builds fail validation without it.
  network_adapter_type = "vmxnet3"
  sound                = false
  usb                  = false

  headless = var.headless

  shutdown_command = "echo '${var.password}' | sudo -S systemctl poweroff"

  # Served from memory rather than http/ on disk, so the seed authorizes
  # var.ssh_authorized_key instead of a key committed to the repository.
  http_content = {
    "/user-data" = replace(file("${path.root}/http/user-data"), "@SSH_AUTHORIZED_KEY@", var.ssh_authorized_key)
    "/meta-data" = file("${path.root}/http/meta-data")
  }

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
  sources = ["source.vmware-iso.ubuntu"]

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

  # - 01 must run last: it truncates the machine-id and clears /tmp and
  #   /var/tmp, so anything after it puts per-machine state back into the image.
  # - That sweep is also what removes the staged tree above.
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; echo '${var.password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts = [
      "${path.root}/../../../scripts/ubuntu/01-cleanup-system.sh"
    ]
  }
}
