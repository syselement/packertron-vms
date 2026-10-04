# Provider and language versions for the clone-and-configure layer, and the
# encryption of its state.
#
# Docs:
#   bpg/proxmox       https://registry.terraform.io/providers/bpg/proxmox/latest/docs
#   State encryption  https://opentofu.org/docs/language/state/encryption/
#   README.md         what this layer does, and the one-time state migration
#
# Run:
#   export TF_VAR_state_passphrase='...'
#   tofu init
#   tofu validate

terraform {
  # 1.8: the first release that accepts a variable in the encryption block.
  required_version = ">= 1.8.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.112.0"
    }
  }

  # - State and saved plans hold the clone password and the node layout, so
  #   both are encrypted with a key derived from TF_VAR_state_passphrase.
  # - No unencrypted method is configured, so a plaintext state is refused
  #   rather than read. Migrating one is a one-time step - see README.md.
  encryption {
    key_provider "pbkdf2" "state" {
      passphrase = var.state_passphrase
    }

    method "aes_gcm" "state" {
      keys = key_provider.pbkdf2.state
    }

    state {
      method = method.aes_gcm.state
    }

    plan {
      method = method.aes_gcm.state
    }
  }
}
