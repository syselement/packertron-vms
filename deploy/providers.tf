# Proxmox API and node access.
#
# The API token is read from PROXMOX_VE_API_TOKEN and is deliberately absent
# here: a token in a .tfvars file is a token in a backup, an editor swap file
# and eventually a commit. Only the non-secret endpoint lives in tfvars.
#
# Docs:
#   Authentication  https://registry.terraform.io/providers/bpg/proxmox/latest/docs#authentication
#   SECURITY.md     the credential model this repository uses
#
# Run:
#   export PROXMOX_VE_API_TOKEN='tofu@pve!deploy=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = var.proxmox_insecure

  # Only used to upload the first-boot snippet, and only when
  # var.provisioning_steps asks for one. Proxmox has no API for writing
  # snippets, so the provider writes them over SSH; nothing else here needs it.
  # See README.md for how to avoid this entirely.
  ssh {
    agent    = true
    username = var.node_ssh_username
  }
}
