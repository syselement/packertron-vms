# What you need to reach each VM, and which of them are provisioning themselves.
#
# Every output is keyed by VM name, the same key used in var.vms.
#
# Docs:
#   README.md  following a first-boot run

output "vm_ids" {
  description = "VMID Proxmox assigned to each clone"
  value       = { for name, vm in proxmox_virtual_environment_vm.this : name => vm.vm_id }
}

output "ipv4_addresses" {
  description = "Addresses reported by the guest agent; empty until it starts"
  value       = { for name, vm in proxmox_virtual_environment_vm.this : name => vm.ipv4_addresses }
}

output "provisioning_steps" {
  description = "First-boot steps each VM was asked to run; empty means none"
  value       = { for name, vm in var.vms : name => vm.provisioning_steps }
}

# Provisioning takes many minutes and finishes after apply returns, so say
# where to watch it rather than implying the VMs are ready.
output "next" {
  description = "What to do once apply returns"
  value = length(local.provisioned) == 0 ? "VMs are up; no first-boot provisioning was requested." : join(" ", [
    "First-boot provisioning is running on: ${join(", ", sort(keys(local.provisioned)))}.",
    "Follow it with: ssh ${var.username}@<address> sudo tail -f /var/log/packertron-firstboot.log",
  ])
}
