# Contributor VMs on node1 (Catalyst headless profile). A separate root from terraform/node1, with its own encrypted
# state, so these VMs never share a plan with the LocumView desktops.

data "sops_file" "vm" {
  for_each    = var.catalyst_vms
  source_file = "${path.module}/vms/${each.key}.sops.yaml"
}

module "vm" {
  source   = "../modules/libvirt-catalyst-vm"
  for_each = var.catalyst_vms

  name       = each.key
  mac        = each.value.mac
  memory_mib = each.value.memory_mib
  vcpus      = each.value.vcpus
  root_gib   = each.value.root_gib
  home_gib   = each.value.home_gib

  pool        = var.pool
  bridge      = var.bridge
  libvirt_uri = var.libvirt_uri
  base_image  = var.base_image
  image_cache = pathexpand(var.image_cache)
  timezone    = var.timezone

  idm = {
    domain     = var.idm.domain
    realm      = var.idm.realm
    server     = var.idm.server
    hostgroups = [var.idm.hostgroup, each.value.hostgroup]
  }

  directory_users = each.value.directory_users
  admin_ssh_keys  = var.admin_ssh_keys
  ssh_sources     = var.ssh_sources
  extra_ca_pem    = var.extra_ca_file == "" ? "" : file(var.extra_ca_file)
  catalyst_bundle = pathexpand(var.catalyst_bundle)

  secrets = {
    lvadmin_password = data.sops_file.vm[each.key].data["lvadmin_password"]
  }
}

output "vms" {
  value = { for k, m in module.vm : k => { fqdn = m.fqdn, home_volume = m.home_volume } }
}
