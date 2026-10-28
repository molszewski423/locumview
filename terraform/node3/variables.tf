variable "state_passphrase" {
  description = "State and plan encryption passphrase (at least 16 characters), from SOPS via ./tofu.sh."
  type        = string
  sensitive   = true
}

# Site values: site.auto.tfvars (git-ignored; see site.auto.tfvars.example).
variable "libvirt_uri" {
  description = "libvirt on node3: qemu:///system when OpenTofu runs on node3 itself (operator-laptop), else qemu+ssh://<user>@<node3>/system."
  type        = string
}

variable "pool" {
  type    = string
  default = "locumview"
}

variable "bridge" {
  type    = string
  default = "br0"
}

variable "installer_iso" {
  description = "Installer ISO path on node3 (volume in the locumview pool)."
  type        = string
}

variable "idm" {
  type = object({
    domain    = string
    realm     = string
    server    = string
    hostgroup = string
  })
  default = {
    domain    = "corp.locumview.com"
    realm     = "CORP.LOCUMVIEW.COM"
    server    = "idm01.corp.locumview.com"
    hostgroup = "locumview-desktops"
  }
}

variable "idm_ca_certificate" {
  description = "Path to the IdM CA certificate (/etc/ipa/ca.crt on any enrolled machine)."
  type        = string
}

variable "ipa_username" {
  description = "IdM account for OpenTofu: role \"LocumView desktop provisioning\" (hosts and host groups only)."
  type        = string
  default     = "svc-opentofu"
}

variable "ipa_password" {
  description = "From idm.sops.yaml via ./tofu.sh."
  type        = string
  sensitive   = true
}

variable "guacamole_kubeconfig" {
  description = "Kubeconfig for the scoped operator account (operator-kubeconfig.sh); empty: no Guacamole connections."
  type        = string
  default     = ""
}

variable "k3s_node_cidrs" {
  type = list(string)
}

variable "dns_ip" {
  type = string
}

# Desktops: desktops.auto.tfvars. Secrets per desktop: desktops/<name>.sops.yaml (./new-desktop-secrets.sh).
variable "desktops" {
  type = map(object({
    user             = string
    memory_mib       = optional(number, 6144)
    vcpus            = optional(number, 4)
    guacamole_groups = optional(list(string), ["locumview-admins"])
    guacamole_name   = optional(string) # label on the login page; default: the desktop's name
  }))
  default = {}
}

variable "rhsm_sops_file" {
  description = "SOPS file with rhsm_org, rhsm_activation_key and rhsm_offline_token (rhsm-secrets.sh); empty: desktops are not registered with Red Hat."
  type        = string
  default     = "rhsm.sops.yaml"
}

variable "timezone" {
  description = "Time zone of the desktops (IANA name)."
  type        = string
  default     = "America/New_York"
}

variable "update_image" {
  description = "Image the desktops track for signed updates (empty: no updates). Site value."
  type        = string
  default     = ""
}

variable "registry_ca_file" {
  description = "Registry CA certificate (PEM) on the operator machine, for update_image (empty: publicly trusted)."
  type        = string
  default     = ""
}

variable "registry_sops_file" {
  description = "SOPS file with registry_pull_user and registry_pull_token (registry-secrets.sh)."
  type        = string
  default     = "registry.sops.yaml"
}
