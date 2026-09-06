# Non-secret build settings for the Kali Proxmox template.
#
# Credentials do NOT belong here. Supply them through the environment:
#   export PKR_VAR_proxmox_api_token_id="packer@pve!templates"
#   export PKR_VAR_proxmox_api_token_secret="..."
#   export PKR_VAR_ssh_password="..."
#
# Anything sensitive that must live in a file belongs in a
# *.local.pkrvars.hcl beside this one, which .gitignore excludes.

proxmox_api_host = "proxmox"
proxmox_node     = "proxmox"
storage_pool     = "local-lvm"
iso_storage      = "local"
network_adapter  = "vmbr1"
ssh_username     = "kali"
hostname         = "kali"

# Set to true only for a node with a self-signed certificate you have chosen
# to accept.
insecure_skip_tls_verify = false
