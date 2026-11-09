# One persistent, headless Catalyst development VM per contributor (Catalyst's headless profile on Debian stable).
# It follows libvirt-desktop where the job is the same: the IdM host entry with a one-time enrollment password, disks
# by path, a seed that carries this VM's secrets and is wiped once provisioning has finished. It differs where the
# guest does: a Debian cloud image instead of the installer ISO, the Catalyst playbook instead of bootc, and a
# separate home disk that a rebuild of the system disk keeps.

locals {
  fqdn        = "${var.name}.${var.idm.domain}"
  seed_target = "sdz" # the seed CD-ROM; scripts/wait-provisioned.sh watches its tray
  image_file  = "${var.image_cache}/${basename(var.base_image.url)}"
}

# --- Identity --------------------------------------------------------------------------------------------------

resource "random_password" "enroll" {
  length  = 32
  special = false # alphanumeric: an IdM-generated password with shell metacharacters once leaked into a log (#33)
}

resource "freeipa_host" "vm" {
  name         = local.fqdn
  description  = "Catalyst development VM (OpenTofu, terraform/modules/libvirt-catalyst-vm)"
  force        = true # no DNS record yet: the VM registers its own at enrollment
  update_dns   = true # and on destroy its records are removed with the host
  userpassword = random_password.enroll.result

  lifecycle {
    ignore_changes = [userpassword, ipasshpubkeys] # enrollment consumes the password and uploads the host keys
  }
}

# Access comes through host groups only. The contributor's own group is named by their HBAC and sudo rules (created
# with the account), so joining it is what lets them log in here; OpenTofu's IdM account cannot edit rules at all.
resource "freeipa_host_hostgroup_membership" "vm" {
  for_each   = toset(var.idm.hostgroups)
  name       = each.key
  hosts      = [freeipa_host.vm.name]
  identifier = "${var.name}-${each.key}"
}

# --- Storage ---------------------------------------------------------------------------------------------------

# The provider's own download has no checksum, so the image is fetched and checked here first, then uploaded from
# the local file.
resource "terraform_data" "image" {
  triggers_replace = [var.base_image.sha512]

  provisioner "local-exec" {
    command     = "${path.module}/scripts/fetch-image.sh"
    interpreter = ["bash"]
    environment = {
      IMAGE_URL    = var.base_image.url
      IMAGE_SHA512 = var.base_image.sha512
      IMAGE_FILE   = local.image_file
    }
  }
}

resource "libvirt_volume" "base" {
  name   = "${var.name}-base-${basename(var.base_image.url)}"
  pool   = var.pool
  create = { content = { url = local.image_file } }
  target = { format = { type = "qcow2" } }

  depends_on = [terraform_data.image]
}

resource "libvirt_volume" "root" {
  name          = "${var.name}.qcow2"
  pool          = var.pool
  capacity      = var.root_gib
  capacity_unit = "GiB"
  target        = { format = { type = "qcow2" } }
  backing_store = {
    path   = libvirt_volume.base.path
    format = { type = "qcow2" }
  }
}

resource "libvirt_volume" "home" {
  name          = "${var.name}-home.qcow2"
  pool          = var.pool
  capacity      = var.home_gib
  capacity_unit = "GiB"
  target        = { format = { type = "qcow2" } }

  lifecycle {
    prevent_destroy = true # the contributor's work; remove it by hand, deliberately, if ever
  }
}

resource "libvirt_volume" "seed" {
  name          = "${var.name}-seed.iso"
  pool          = var.pool
  capacity      = 64 # room for the Catalyst bundle
  capacity_unit = "MiB"
  target        = { format = { type = "raw" } }

  lifecycle {
    ignore_changes = [target] # libvirt reports the uploaded seed as "iso" (lv-test03)
  }
}

resource "terraform_data" "seed" {
  triggers_replace = [libvirt_volume.seed.id, libvirt_volume.root.id]

  provisioner "local-exec" {
    command     = "${path.module}/scripts/seed.sh"
    interpreter = ["bash"]
    environment = {
      LV_URI           = var.libvirt_uri
      LV_POOL          = var.pool
      LV_SEED_VOLUME   = libvirt_volume.seed.name
      LV_NAME          = var.name
      LV_FQDN          = local.fqdn
      LV_PROVISION     = "${path.module}/scripts/provision.sh"
      CATALYST_BUNDLE  = var.catalyst_bundle
      IDM_DOMAIN       = var.idm.domain
      IDM_REALM        = var.idm.realm
      IDM_SERVER       = var.idm.server
      IDM_OTP          = random_password.enroll.result
      LVADMIN_PASSWORD = var.secrets.lvadmin_password
      ADMIN_SSH_KEYS   = join("\n", var.admin_ssh_keys)
      INVENTORY = yamlencode({ all = {
        hosts = { workstation = { ansible_connection = "local", ansible_python_interpreter = "/usr/bin/python3" } }
        vars = merge({
          devalpine_user                  = "lvadmin"
          devalpine_apply                 = true
          devalpine_profile               = "headless"
          devalpine_hostname              = local.fqdn
          devalpine_activate_services     = true
          devalpine_enable_power_actions  = false
          devalpine_timezone              = var.timezone
          devalpine_ssh_ipv4_sources      = var.ssh_sources
          devalpine_ssh_ipv6_sources      = []
          devalpine_ssh_directory_users   = var.directory_users
          devalpine_extra_ca_certificates = var.extra_ca_pem == "" ? [] : [{ name = "owner-ca", pem = var.extra_ca_pem }]
        })
      } })
    }
  }

  depends_on = [freeipa_host_hostgroup_membership.vm]
}

# --- The VM ----------------------------------------------------------------------------------------------------

resource "libvirt_domain" "vm" {
  name        = var.name
  description = "Catalyst development VM ${local.fqdn}"
  type        = "kvm"
  memory      = var.memory_mib
  memory_unit = "MiB"
  vcpu        = var.vcpus
  autostart   = true
  running     = true

  cpu = { mode = "host-passthrough" }

  os = {
    type            = "hvm"
    type_arch       = "x86_64"
    type_machine    = "q35"
    loader          = var.ovmf_code
    loader_type     = "pflash"
    loader_readonly = "yes"
    loader_secure   = "yes"
    nv_ram = {
      nv_ram   = "/var/lib/libvirt/qemu/nvram/${var.name}_VARS.fd"
      template = var.ovmf_vars
    }
  }

  features = {
    acpi = true
    apic = {}
    smm  = { state = "on" } # required by Secure Boot firmware
  }

  devices = {
    disks = [
      {
        device = "disk"
        source = { file = { file = libvirt_volume.root.path } } # by path: AppArmor on Debian hosts (lv-test03)
        target = { dev = "vda", bus = "virtio" }
        driver = { name = "qemu", type = "qcow2" }
        boot   = { order = 1 }
      },
      {
        device = "disk"
        source = { file = { file = libvirt_volume.home.path } }
        target = { dev = "vdb", bus = "virtio" }
        driver = { name = "qemu", type = "qcow2" }
      },
      {
        device    = "cdrom"
        source    = { file = { file = libvirt_volume.seed.path } }
        target    = { dev = local.seed_target, bus = "sata" }
        driver    = { name = "qemu", type = "raw" }
        read_only = true
      },
    ]
    interfaces = [
      {
        source = { bridge = { bridge = var.bridge } }
        model  = { type = "virtio" }
        mac    = { address = var.mac }
      },
    ]
    # ADR 0010: pages the guest frees go back to the host, so it holds what is used, not what is allocated.
    mem_balloon = {
      model               = "virtio"
      free_page_reporting = "on"
      stats               = { period = 10 }
    }
    graphics = [{ spice = { auto_port = true } }] # console for break-glass only
    videos   = [{ model = { type = "virtio", heads = 1, primary = "yes" } }]
  }

  depends_on = [terraform_data.seed]
}

resource "terraform_data" "provisioned" {
  triggers_replace = [libvirt_domain.vm.id, terraform_data.seed.id]

  provisioner "local-exec" {
    command     = "${path.module}/scripts/wait-provisioned.sh"
    interpreter = ["bash"]
    environment = {
      LV_URI         = var.libvirt_uri
      LV_POOL        = var.pool
      LV_NAME        = var.name
      LV_SEED_TARGET = local.seed_target
      LV_SEED_VOLUME = libvirt_volume.seed.name
      LV_TIMEOUT_MIN = tostring(var.provision_timeout_minutes)
    }
  }
}
