# Provider and language versions for the clone-and-configure layer.
#
# Docs:
#   bpg/proxmox  https://registry.terraform.io/providers/bpg/proxmox/latest/docs
#   README.md    what this layer does, and what it deliberately does not
#
# Run:
#   tofu init
#   tofu validate

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.112.0"
    }
  }
}
