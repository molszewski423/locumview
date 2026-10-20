data "sops_file" "desktop" {
  for_each    = var.desktops
  source_file = "${path.module}/desktops/${each.key}.sops.yaml"
}

module "desktop" {
  source   = "../modules/libvirt-desktop"
  for_each = var.desktops

  name         = each.key
  desktop_user = each.value.user
  memory_mib   = each.value.memory_mib
  vcpus        = each.value.vcpus

  pool          = var.pool
  bridge        = var.bridge
  installer_iso = var.installer_iso
  libvirt_uri   = var.libvirt_uri

  idm            = var.idm
  k3s_node_cidrs = var.k3s_node_cidrs
  dns_ip         = var.dns_ip

  secrets = {
    lvadmin_password         = data.sops_file.desktop[each.key].data["lvadmin_password"]
    grub_password            = data.sops_file.desktop[each.key].data["grub_password"]
    luks_recovery_passphrase = data.sops_file.desktop[each.key].data["luks_recovery_passphrase"]
    rdp_user                 = data.sops_file.desktop[each.key].data["rdp_user"]
    rdp_password             = data.sops_file.desktop[each.key].data["rdp_password"]
    demo_rdp_user            = try(data.sops_file.desktop[each.key].data["demo_rdp_user"], "")
    demo_rdp_password        = try(data.sops_file.desktop[each.key].data["demo_rdp_password"], "")
  }
}

output "desktops" {
  value = { for k, m in module.desktop : k => m.fqdn }
}
