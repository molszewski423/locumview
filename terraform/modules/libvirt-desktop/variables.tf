variable "name" {
  description = "Short name: the libvirt domain name and the first label of the host name."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.name))
    error_message = "Lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "desktop_user" {
  description = "IdM user whose always-on headless session this desktop serves over RDP (port 3390)."
  type        = string
}

variable "memory_mib" {
  type    = number
  default = 6144
}

variable "vcpus" {
  type    = number
  default = 4
}

variable "disk_gib" {
  description = "Desktop disk. The kickstart needs at least about 47 GiB for its fixed logical volumes."
  type        = number
  default     = 50
}

variable "pool" {
  description = "libvirt storage pool for the desktop disk and the seed volume."
  type        = string
}

variable "bridge" {
  description = "Host bridge to the LAN, so guacd on the k3s nodes reaches the desktop."
  type        = string
}

variable "installer_iso" {
  description = "Path, on the hypervisor, of the installer ISO (image/desktop/install/build-installer-iso.sh)."
  type        = string
}

variable "ovmf_code" {
  description = "Secure Boot capable OVMF code file on the hypervisor."
  type        = string
  default     = "/usr/share/OVMF/OVMF_CODE_4M.ms.fd"
}

variable "ovmf_vars" {
  description = "OVMF variables template with the Microsoft keys enrolled (Secure Boot on)."
  type        = string
  default     = "/usr/share/OVMF/OVMF_VARS_4M.ms.fd"
}

variable "libvirt_uri" {
  description = "The libvirt connection, also used by virsh in the seed and wait steps (they run where tofu runs)."
  type        = string
}

variable "idm" {
  description = "IdM domain, realm, server and the host group desktops join (HBAC and sudo rules hang off it)."
  type = object({
    domain    = string
    realm     = string
    server    = string
    hostgroup = string
  })
}

variable "k3s_node_cidrs" {
  description = "Sources allowed to reach RDP, SSH and Cockpit: the k3s nodes, where guacd runs, as /32 CIDRs."
  type        = list(string)
}

variable "dns_ip" {
  description = "DNS server the demo user's egress fence allows."
  type        = string
}

variable "secrets" {
  description = "Per-desktop secrets, from SOPS. demo_* empty means no demo user."
  type = object({
    lvadmin_password         = string
    grub_password            = string
    luks_recovery_passphrase = string
    rdp_user                 = string
    rdp_password             = string
    demo_rdp_user            = optional(string, "")
    demo_rdp_password        = optional(string, "")
  })
  sensitive = true
}

variable "provision_timeout_minutes" {
  description = "How long to wait for the installation plus first-boot provisioning to eject the seed."
  type        = number
  default     = 60
}

variable "guacamole" {
  description = <<-EOT
    The desktop's Guacamole connection (null: none). Written with k8s/locumview/guacamole/upsert-desktop-connection.sh
    through kubectl, using this kubeconfig (the scoped operator account is enough); READ for these Guacamole user
    groups. Removed on destroy; session history stays.
  EOT
  type = object({
    kubeconfig = string
    groups     = list(string)
  })
  default = null
}

variable "rhsm" {
  description = <<-EOT
    Red Hat subscription for the desktop (null: not registered; Firefox then comes from Flathub). org goes on the
    seed with rhsm_activation_key; sops_file holds rhsm_offline_token for the subscription API, which removes any
    registration with this desktop's name before it is created and after it is destroyed.
  EOT
  type = object({
    org       = string
    sops_file = string
  })
  default = null
}

variable "rhsm_activation_key" {
  description = "Activation key for var.rhsm.org (from SOPS)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "timezone" {
  description = "The desktop's time zone, an IANA name (set at first boot)."
  type        = string
  default     = "America/New_York"
}

variable "updates" {
  description = <<-EOT
    Image updates (null: none). The desktop switches to track image (for example
    git.lan/mike/locumview-desktop:latest) and accepts only images from that repository signed with the key baked
    into the image. ca_b64: the registry's CA certificate, base64 (empty if publicly trusted); pull_user with
    registry_pull_token: read-only registry credentials.
  EOT
  type = object({
    image     = string
    ca_b64    = optional(string, "")
    pull_user = optional(string, "")
  })
  default = null
}

variable "registry_pull_token" {
  description = "Read-only registry token for var.updates (from SOPS)."
  type        = string
  default     = ""
  sensitive   = true
}
