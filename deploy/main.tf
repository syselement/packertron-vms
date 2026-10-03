# Clone Packer-built templates into running VMs, and optionally ask each one to
# provision itself at first boot.
#
# One resource per entry in var.vms, so a tfvars holding one entry brings up one
# VM and a tfvars holding the whole lab brings up all of them from one apply.
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
#   tofu plan  -var-file=lab.tfvars
#   tofu apply -var-file=lab.tfvars

locals {
  # Only a VM that asked for provisioning and did not name a snippet of its own
  # needs one uploaded. Everything else clones and boots untouched.
  provisioned = {
    for name, vm in var.vms : name => vm
    if vm.provisioning_steps != "" && vm.vendor_data_file_id == ""
  }

  firstboot_conf = {
    for name, vm in local.provisioned : name => join("\n", concat(
      [
        "TARGET_USER=${coalesce(vm.username, var.username)}",
        "STEPS=${vm.provisioning_steps}",
      ],
      var.provisioning_repo_branch == "" ? [] : ["REPO_BRANCH=${var.provisioning_repo_branch}"],
    ))
  }

  # vendor-data, not user-data: Proxmox generates the user-data that carries
  # the hostname, account, keys and network. Supplying our own user-data would
  # replace all of that, and the clone would come up unreachable.
  #
  # yamlencode rather than a template file, because the stub is Bash: every
  # ${...} in it would otherwise be read as an interpolation.
  firstboot_vendor_data = {
    for name in keys(local.provisioned) : name => "#cloud-config\n${yamlencode({
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
          content     = "${local.firstboot_conf[name]}\n"
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
}

resource "proxmox_virtual_environment_file" "firstboot" {
  for_each = local.provisioned

  content_type = "snippets"
  datastore_id = var.snippet_datastore_id
  node_name    = var.proxmox_node

  source_raw {
    data      = local.firstboot_vendor_data[each.key]
    file_name = "${each.key}-firstboot.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  for_each = var.vms

  name      = each.key
  node_name = var.proxmox_node
  vm_id     = each.value.vm_id
  tags      = each.value.tags

  clone {
    vm_id = each.value.template_vm_id
    full  = each.value.full_clone
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
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
    size         = each.value.disk_size
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
        address = each.value.ipv4_address
        gateway = each.value.ipv4_gateway
      }
    }

    user_account {
      username = coalesce(each.value.username, var.username)
      password = var.password
      keys     = var.ssh_authorized_keys
    }

    # The uploaded snippet when this VM asked for provisioning, an existing one
    # when it named it, and nothing at all otherwise.
    vendor_data_file_id = (
      contains(keys(local.provisioned), each.key)
      ? proxmox_virtual_environment_file.firstboot[each.key].id
      : (each.value.vendor_data_file_id == "" ? null : each.value.vendor_data_file_id)
    )
  }
}
