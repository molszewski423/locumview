# One LocumView desktop on libvirt, installed from the installer ISO and provisioned on first boot (changelog #53).
# The VM matches the reference desktop: q35, UEFI with Secure Boot (Microsoft keys), SMM, a TPM 2.0 for the disk
# key, virtio disk and network on the LAN bridge. Everything per desktop reaches it on a seed disk; see
# image/desktop/README.md ("Installing and provisioning") for what first boot does with it.

locals {
  fqdn        = "${var.name}.${var.idm.domain}"
  seed_target = "sdz" # the seed CD-ROM; scripts/wait-provisioned.sh watches its tray
}

# --- Identity: the IdM host entry, with a one-time enrollment password ---------------------------------------

resource "random_password" "enroll" {
  length  = 32
  special = false # alphanumeric: an IdM-generated password with shell metacharacters once leaked into a log (#33)
}

resource "freeipa_host" "desktop" {
  name         = local.fqdn
  description  = "LocumView desktop (OpenTofu, terraform/modules/libvirt-desktop)"
  force        = true # no DNS record yet: the desktop registers its own at enrollment (--enable-dns-updates)
  update_dns   = true # and on destroy its records are removed with the host
  userpassword = random_password.enroll.result

  lifecycle {
    # Enrollment consumes the one-time password and uploads the host's SSH keys; neither is drift to undo.
    ignore_changes = [userpassword, ipasshpubkeys]
  }
}

resource "freeipa_host_hostgroup_membership" "desktop" {
  name       = var.idm.hostgroup
  hosts      = [freeipa_host.desktop.name]
  identifier = "${var.name}-desktops"
}

# --- Storage ---------------------------------------------------------------------------------------------------

resource "libvirt_volume" "disk" {
  name          = "${var.name}.qcow2"
  pool          = var.pool
  capacity      = var.disk_gib
  capacity_unit = "GiB"
  target = {
    format = { type = "qcow2" }
  }
}

# The seed volume is created empty and filled by the seed step below. libvirt_cloudinit_disk is not used: it only
# carries cloud-init's own files, and the secrets must not go through cloud-init (it keeps copies in /var/lib/cloud).
resource "libvirt_volume" "seed" {
  name          = "${var.name}-seed.iso"
  pool          = var.pool
  capacity      = 4
  capacity_unit = "MiB"
  target = {
    format = { type = "raw" }
  }

  lifecycle {
    # Once the seed is uploaded, libvirt detects its content and reports the format as "iso"; volumes cannot be
    # updated in place, so that difference must not be treated as a change (lv-test03).
    ignore_changes = [target]
  }
}

resource "terraform_data" "seed" {
  triggers_replace = [libvirt_volume.seed.id]

  provisioner "local-exec" {
    command     = "${path.module}/scripts/seed.sh"
    interpreter = ["bash"]
    environment = {
      LV_URI                   = var.libvirt_uri
      LV_POOL                  = var.pool
      LV_SEED_VOLUME           = libvirt_volume.seed.name
      LV_NAME                  = var.name
      LV_FQDN                  = local.fqdn
      IDM_DOMAIN               = var.idm.domain
      IDM_REALM                = var.idm.realm
      IDM_SERVER               = var.idm.server
      IDM_OTP                  = random_password.enroll.result
      LVADMIN_PASSWORD         = var.secrets.lvadmin_password
      GRUB_PASSWORD            = var.secrets.grub_password
      LUKS_RECOVERY_PASSPHRASE = var.secrets.luks_recovery_passphrase
      K3S_NODE_CIDRS           = join(" ", var.k3s_node_cidrs)
      DNS_IP                   = var.dns_ip
      DESKTOP_USER             = var.desktop_user
      DESKTOP_RDP_USER         = var.secrets.rdp_user
      DESKTOP_RDP_PASSWORD     = var.secrets.rdp_password
      DEMO_RDP_USER            = var.secrets.demo_rdp_user
      DEMO_RDP_PASSWORD        = var.secrets.demo_rdp_password
      RHSM_ORG                 = var.rhsm == null ? "" : var.rhsm.org
      TIMEZONE                 = var.timezone
      UPDATE_IMAGE             = var.updates == null ? "" : var.updates.image
      REGISTRY_CA_B64          = var.updates == null ? "" : var.updates.ca_b64
      REGISTRY_PULL_USER       = var.updates == null ? "" : var.updates.pull_user
      REGISTRY_PULL_TOKEN      = var.updates == null ? "" : var.registry_pull_token
      RHSM_ACTIVATION_KEY      = var.rhsm == null ? "" : var.rhsm_activation_key
    }
  }

  depends_on = [freeipa_host_hostgroup_membership.desktop, terraform_data.rhsm]
}

# Red Hat registrations by this desktop's name: none left from an earlier desktop of the same name before it is
# created, and none left behind after it is destroyed (the developer subscription counts registered systems).
# Destroy order: the VM goes first (it depends on the seed, which depends on this), then the registration.
resource "terraform_data" "rhsm" {
  count = var.rhsm == null ? 0 : 1

  input = {
    name      = local.fqdn
    sops_file = abspath(var.rhsm.sops_file)
    script    = abspath("${path.module}/scripts/rhsm-systems.sh")
  }

  provisioner "local-exec" {
    command     = "${self.input.script} remove ${self.input.name}"
    interpreter = ["bash", "-c"]
    environment = { RHSM_SOPS_FILE = self.input.sops_file }
  }

  provisioner "local-exec" {
    when        = destroy
    command     = "${self.input.script} remove ${self.input.name}"
    interpreter = ["bash", "-c"]
    environment = { RHSM_SOPS_FILE = self.input.sops_file }
  }
}

# --- The VM ----------------------------------------------------------------------------------------------------

resource "libvirt_domain" "desktop" {
  name        = var.name
  description = "LocumView desktop ${local.fqdn}"
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
        # Boots first: empty until the installer has run, so the firmware falls through to the installer ISO;
        # afterwards the desktop boots from here and the ISO is never used again.
        device = "disk"
        # By path, not pool/volume: on hosts that confine guests with AppArmor (Debian), virt-aa-helper adds only
        # file paths to the guest's profile, and a pool volume ends as "Permission denied" at start (lv-test03).
        source = { file = { file = libvirt_volume.disk.path } }
        target = { dev = "vda", bus = "virtio" }
        driver = { name = "qemu", type = "qcow2" }
        boot   = { order = 1 }
      },
      {
        device    = "cdrom"
        source    = { file = { file = var.installer_iso } }
        target    = { dev = "sdy", bus = "sata" }
        driver    = { name = "qemu", type = "raw" }
        read_only = true
        boot      = { order = 2 }
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
      },
    ]
    tpms = [
      {
        model   = "tpm-crb"
        backend = { emulator = { version = "2.0" } }
      },
    ]
    graphics = [{ spice = { auto_port = true } }]
    videos   = [{ model = { type = "virtio", heads = 1, primary = "yes" } }]
  }

  depends_on = [terraform_data.seed]
}

# Installation plus first boot take a while; provisioning ejects the seed only when every step has succeeded.
# Then the seed volume is wiped (it held this desktop's secrets) and stays, empty, as the domain's CD-ROM.
resource "terraform_data" "provisioned" {
  triggers_replace = [libvirt_domain.desktop.id, terraform_data.seed.id]

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

# --- Guacamole connection ----------------------------------------------------------------------------------------
# By host name: the desktop registers itself in IdM DNS at enrollment, and the cluster resolves that zone.
resource "terraform_data" "guacamole" {
  count = var.guacamole == null ? 0 : 1

  # Read by the destroy-time provisioner, which can only use self. Nothing secret here.
  input = {
    name       = var.name
    kubeconfig = var.guacamole.kubeconfig
    scripts    = abspath("${path.module}/../../../k8s/locumview/guacamole")
  }
  triggers_replace = [terraform_data.provisioned.id, var.guacamole.groups]

  provisioner "local-exec" {
    command     = "${self.input.scripts}/upsert-desktop-connection.sh ${var.name} - ${join(" ", var.guacamole.groups)}"
    interpreter = ["bash", "-c"]
    environment = {
      KUBECONFIG        = var.guacamole.kubeconfig
      GUAC_HOSTNAME     = local.fqdn
      GUAC_PORT         = "3390"
      GUAC_RDP_USER     = var.secrets.rdp_user
      GUAC_RDP_PASSWORD = var.secrets.rdp_password
    }
  }

  provisioner "local-exec" {
    when        = destroy
    command     = "${self.input.scripts}/delete-desktop-connection.sh ${self.input.name}"
    interpreter = ["bash", "-c"]
    environment = {
      KUBECONFIG = self.input.kubeconfig
    }
  }
}
