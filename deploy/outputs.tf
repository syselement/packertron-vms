# What you need to reach the VM, and whether it is provisioning itself.
#
# Docs:
#   README.md  following a first-boot run

output "vm_id" {
  description = "VMID Proxmox assigned to the clone"
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "ipv4_addresses" {
  description = "Addresses reported by the guest agent; empty until it starts"
  value       = proxmox_virtual_environment_vm.this.ipv4_addresses
}

output "provisioning_steps" {
  description = "First-boot steps this VM was asked to run; empty means none"
  value       = var.provisioning_steps
}

# Provisioning takes many minutes and finishes after apply returns, so say
# where to watch it rather than implying the VM is ready.
output "next" {
  description = "What to do once apply returns"
  value = var.provisioning_steps == "" ? "VM is up; no first-boot provisioning was requested." : join(" ", [
    "First-boot provisioning is running in the background.",
    "Follow it with: ssh ${var.username}@<address> sudo tail -f /var/log/packertron-firstboot.log",
  ])
}
