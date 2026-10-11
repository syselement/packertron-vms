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
# would want, so a one-line entry is a valid VM.
# - username overrides the shared account for one VM: a Windows Server clone
#   keeps "Administrator".
# - os is the template's system. It decides what provisioning_steps may ask
#   for, so a request the clone cannot run fails at plan time instead of on
#   its first boot.
# - bridge and vlan_id are for a clone that needs another network than the
#   template's NIC; left unset, the clone keeps that NIC exactly.
variable "vms" {
  type = map(object({
    template_vm_id      = number
    os                  = optional(string, "ubuntu")
    vm_id               = optional(number)
    username            = optional(string)
    cores               = optional(number, 2)
    memory              = optional(number, 2048)
    disk_size           = optional(number, 32)
    full_clone          = optional(bool, true)
    bridge              = optional(string)
    vlan_id             = optional(number)
    ipv4_address        = optional(string, "dhcp")
    ipv4_gateway        = optional(string)
    tags                = optional(list(string), ["opentofu"])
    provisioning_steps  = optional(string, "")
    vendor_data_file_id = optional(string, "")
  }))
  description = "VMs to create, keyed by name. disk_size must be at least the template's own size: Proxmox can grow a cloned disk but never shrink one."

  validation {
    condition = alltrue([
      for name, vm in var.vms : contains(["ubuntu", "kali", "windows"], vm.os)
    ])
    error_message = "os must be \"ubuntu\", \"kali\" or \"windows\"."
  }

  validation {
    condition = alltrue([
      for name, vm in var.vms : (
        vm.provisioning_steps == "" ? true : (
          vm.os == "ubuntu" ? can(regex("^[0-9]{2}(,[0-9]{2})*$", vm.provisioning_steps)) : (
            vm.os == "windows" ? vm.provisioning_steps == "utils" : false
          )
        )
      )
    ])
    error_message = "provisioning_steps must be empty, or two-digit Ubuntu steps such as \"02,03\" when os is \"ubuntu\", or \"utils\" when os is \"windows\". A Kali clone cannot provision."
  }

  validation {
    condition = alltrue([
      for name, vm in var.vms : vm.vlan_id == null ? true : (vm.vlan_id >= 1 && vm.vlan_id <= 4094)
    ])
    error_message = "vlan_id must be between 1 and 4094."
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
