# Inputs for the VMs this module clones. Node settings and the login identity
# are shared by all of them; everything that differs per machine lives in the
# vms map, keyed by the VM's name.
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
  description = "Name of the Proxmox node to create the VMs on"
}

variable "node_ssh_username" {
  type        = string
  description = "Account used to upload the first-boot snippet over SSH; unused when no provisioning is requested"
  default     = "root"
}

variable "datastore_id" {
  type        = string
  description = "Proxmox storage for the VM disks and the cloud-init drives"
  default     = "local-lvm"
}

# The map key is the VM's name, and also the hostname cloud-init sets. Only
# template_vm_id is required; every other field has the default a plain server
# would want, so a one-line entry is a valid VM. username overrides the shared
# account for one VM: a Windows Server clone keeps "Administrator".
variable "vms" {
  type = map(object({
    template_vm_id      = number
    vm_id               = optional(number)
    username            = optional(string)
    cores               = optional(number, 2)
    memory              = optional(number, 2048)
    disk_size           = optional(number, 32)
    full_clone          = optional(bool, true)
    ipv4_address        = optional(string, "dhcp")
    ipv4_gateway        = optional(string)
    tags                = optional(list(string), ["opentofu"])
    provisioning_steps  = optional(string, "")
    vendor_data_file_id = optional(string, "")
  }))
  description = "VMs to create, keyed by name. disk_size must be at least the template's own size: Proxmox can grow a cloned disk but never shrink one."

  validation {
    condition = alltrue([
      for name, vm in var.vms :
      can(regex("^([0-9]{2}(,[0-9]{2})*)?$", vm.provisioning_steps))
    ])
    error_message = "provisioning_steps must be empty or a comma-separated list of two-digit step numbers, such as \"02,03\"."
  }
}

variable "username" {
  type        = string
  description = "Account cloud-init creates on every clone"
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

variable "provisioning_repo_branch" {
  type        = string
  description = "Branch the first-boot runner provisions from; empty uses the runner's own default"
  default     = ""
}

variable "snippet_datastore_id" {
  type        = string
  description = "Storage holding the first-boot snippets. Must have the \"snippets\" content type enabled."
  default     = "local"
}
