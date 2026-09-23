# Clone one Packer-built template into a running VM, and optionally ask it to
# provision itself at first boot.
#
# The first-boot files are read straight from scripts/ubuntu/firstboot/ rather
# than copied here, so this layer cannot drift from the autoinstall seeds that
# embed the same files.
#
# Docs:
#   vm resource    https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm
#   file resource  https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_file
#   README.md      the clone-time model and what provisioning costs
#
# Run:
#   tofu plan  -var-file=deploy.tfvars
#   tofu apply -var-file=deploy.tfvars

locals {
  provisioning_enabled = var.provisioning_steps != ""

  # Uploaded only when provisioning is requested and no existing snippet was named.
  upload_snippet = local.provisioning_enabled && var.vendor_data_file_id == ""

  firstboot_conf = join("\n", concat(
    [
      "TARGET_USER=${var.username}",
      "STEPS=${var.provisioning_steps}",
    ],
    var.provisioning_repo_branch == "" ? [] : ["REPO_BRANCH=${var.provisioning_repo_branch}"],
  ))

  # vendor-data, not user-data: Proxmox generates the user-data that carries
  # the hostname, account, keys and network. Supplying our own user-data would
  # replace all of that, and the clone would come up unreachable.
  #
  # yamlencode rather than a template file, because the stub is Bash: every
  # ${...} in it would otherwise be read as an interpolation.
  firstboot_vendor_data = "#cloud-config\n${yamlencode({
    # The stub clones the repository, and Ubuntu Server does not ship git. It
    # arrives here, with the provisioning request, so a clone that asks for
    # nothing stays exactly the template. cloud-init installs packages before
    # it runs runcmd, so git is present by the time the unit starts.
    package_update = true
    packages       = ["git"]
    write_files = [
      {
        path        = "/etc/packertron/firstboot.conf"
        owner       = "root:root"
        permissions = "0644"
        content     = "${local.firstboot_conf}\n"
      },
      {
        path        = "/usr/local/sbin/packertron-firstboot"
        owner       = "root:root"
        permissions = "0750"
        content     = file("${path.module}/../scripts/ubuntu/firstboot/stub.sh")
      },
      {
        path        = "/etc/systemd/system/packertron-firstboot.service"
        owner       = "root:root"
        permissions = "0644"
        content     = file("${path.module}/../scripts/ubuntu/firstboot/packertron-firstboot.service")
      },
    ]
    runcmd = [
      ["systemctl", "daemon-reload"],
      ["systemctl", "enable", "packertron-firstboot.service"],
      ["systemctl", "start", "--no-block", "packertron-firstboot.service"],
    ]
  })}"
}

resource "proxmox_virtual_environment_file" "firstboot" {
  count = local.upload_snippet ? 1 : 0

  content_type = "snippets"
  datastore_id = var.snippet_datastore_id
  node_name    = var.proxmox_node

  source_raw {
    data      = local.firstboot_vendor_data
    file_name = "${var.vm_name}-firstboot.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.vm_name
  node_name = var.proxmox_node
  vm_id     = var.vm_id
  tags      = var.tags

  clone {
    vm_id = var.template_vm_id
    full  = var.full_clone
  }

  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory
  }

  # Matches the template's scsi0. Proxmox can grow a cloned disk but never
  # shrink one, so disk_size below the template's own size fails the apply.
  #
  # discard and ssd are restated because naming a disk here means the provider
  # writes the whole block: left out, they fall back to the provider's own
  # defaults (ignore/false) and the clone quietly loses what every .pkr.hcl in
  # templates/proxmox/ sets on the template. Without discard a thin-provisioned
  # clone never returns freed blocks to the pool, so it only ever grows.
  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_size
    discard      = "on"
    ssd          = true
  }

  agent {
    enabled = true
  }

  initialization {
    datastore_id = var.datastore_id

    ip_config {
      ipv4 {
        address = var.ipv4_address
        gateway = var.ipv4_gateway
      }
    }

    user_account {
      username = var.username
      password = var.password
      keys     = var.ssh_authorized_keys
    }

    vendor_data_file_id = local.upload_snippet ? proxmox_virtual_environment_file.firstboot[0].id : (
      var.vendor_data_file_id == "" ? null : var.vendor_data_file_id
    )
  }
}
