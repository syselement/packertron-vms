# Inputs for one cloned VM. Everything has a default except the template to
# clone and the VM's name, so a first deployment is two values plus a tfvars
# file for the node.
#
# Docs:
#   README.md  which values a first deployment actually needs

variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox API endpoint, e.g. https://proxmox.example.lan:8006/"
}

variable "proxmox_insecure" {
  type        = bool
  description = "Skip Proxmox API certificate verification. Leave false unless the node uses a self-signed certificate you have chosen to accept."
  default     = false
}

variable "proxmox_node" {
  type        = string
  description = "Name of the Proxmox node to create the VM on"
}

variable "node_ssh_username" {
  type        = string
  description = "Account used to upload the first-boot snippet over SSH; unused when no provisioning is requested"
  default     = "root"
}

variable "template_vm_id" {
  type        = number
  description = "VMID of the Packer-built template to clone, e.g. 80026 for Ubuntu Server 26.04"
}

variable "vm_name" {
  type        = string
  description = "Name of the new VM, also used as its cloud-init hostname"
}

variable "vm_id" {
  type        = number
  description = "VMID for the new VM; null lets Proxmox allocate one"
  default     = null
}

variable "full_clone" {
  type        = bool
  description = "Copy the template's disks rather than linking them. A linked clone is faster and smaller but keeps the template undeletable."
  default     = true
}

variable "cores" {
  type        = number
  description = "vCPU cores"
  default     = 2
}

variable "memory" {
  type        = number
  description = "Memory in MB"
  default     = 2048
}

variable "disk_size" {
  type        = number
  description = "Disk size in GB. Must be at least the template's own size: Proxmox can grow a cloned disk but never shrink one."
  default     = 32
}

variable "datastore_id" {
  type        = string
  description = "Proxmox storage for the VM disk and the cloud-init drive"
  default     = "local-lvm"
}

variable "ipv4_address" {
  type        = string
  description = "IPv4 address in CIDR form, or \"dhcp\""
  default     = "dhcp"
}

variable "ipv4_gateway" {
  type        = string
  description = "Default gateway; leave empty with DHCP"
  default     = null
}

variable "username" {
  type        = string
  description = "Account cloud-init creates on the clone"
  default     = "syselement"
}

# Null locks the account's password, which is what cloud-init does whenever it
# configures a user without one: the clone is then reachable only by key. Set
# it for console access during debugging, from the environment rather than a
# file:  export TF_VAR_password='...'
variable "password" {
  type        = string
  description = "Console password for the account above; null leaves it locked, key-only"
  sensitive   = true
  default     = null
}

variable "ssh_authorized_keys" {
  type        = list(string)
  description = "Public keys authorised for the account above"
  default     = []
}

variable "tags" {
  type        = list(string)
  description = "Proxmox tags applied to the VM"
  default     = ["opentofu"]
}

# The whole point of the template being thin. Empty means the clone boots and
# does nothing: no repository is fetched and no snippet is uploaded.
variable "provisioning_steps" {
  type        = string
  description = "Comma-separated first-boot steps, e.g. \"02,03\" for the full workstation toolchain. Empty means no provisioning."
  default     = ""

  validation {
    condition     = can(regex("^([0-9]{2}(,[0-9]{2})*)?$", var.provisioning_steps))
    error_message = "provisioning_steps must be empty or a comma-separated list of two-digit step numbers, such as \"02,03\"."
  }
}

variable "provisioning_repo_branch" {
  type        = string
  description = "Branch the first-boot runner provisions from; empty uses the runner's own default"
  default     = ""
}

variable "snippet_datastore_id" {
  type        = string
  description = "Storage holding the first-boot snippet. Must have the \"snippets\" content type enabled."
  default     = "local"
}

# Set this to a snippet already on the node to skip the SSH upload entirely.
variable "vendor_data_file_id" {
  type        = string
  description = "Existing snippet to use as vendor-data, as storage:snippets/name.yaml; empty uploads one when provisioning is requested"
  default     = ""
}
