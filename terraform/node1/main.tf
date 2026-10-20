data "sops_file" "rhsm" {
  count       = var.rhsm_sops_file == "" ? 0 : 1
  source_file = "${path.module}/${var.rhsm_sops_file}"
}

data "sops_file" "registry" {
  count       = var.update_image == "" ? 0 : 1
  source_file = "${path.module}/${var.registry_sops_file}"
}

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
  timezone      = var.timezone
  bridge        = var.bridge
  installer_iso = var.installer_iso
  libvirt_uri   = var.libvirt_uri

  idm            = var.idm
  k3s_node_cidrs = var.k3s_node_cidrs
  dns_ip         = var.dns_ip

  rhsm = var.rhsm_sops_file == "" ? null : {
    org       = nonsensitive(data.sops_file.rhsm[0].data["rhsm_org"]) # an organization ID, not a secret
    sops_file = "${path.module}/${var.rhsm_sops_file}"
  }
  rhsm_activation_key = var.rhsm_sops_file == "" ? "" : data.sops_file.rhsm[0].data["rhsm_activation_key"]

  updates = var.update_image == "" ? null : {
    image     = var.update_image
    ca_b64    = var.registry_ca_file == "" ? "" : filebase64(var.registry_ca_file)
    pull_user = nonsensitive(data.sops_file.registry[0].data["registry_pull_user"]) # a user name, not a secret
  }
  registry_pull_token = var.update_image == "" ? "" : data.sops_file.registry[0].data["registry_pull_token"]

  guacamole = var.guacamole_kubeconfig == "" ? null : {
    kubeconfig = var.guacamole_kubeconfig
    groups     = each.value.guacamole_groups
  }

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
