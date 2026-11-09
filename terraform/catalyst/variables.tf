variable "state_passphrase" {
  description = "State encryption passphrase, from state.sops.yaml through ./tofu.sh."
  type        = string
  sensitive   = true
}

variable "libvirt_uri" {
  type = string
}

variable "pool" {
  type    = string
  default = "default"
}

variable "bridge" {
  type    = string
  default = "br0"
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
    hostgroup = "catalyst-dev-vms"
  }
}

variable "idm_ca_certificate" {
  type = string
}

variable "ipa_username" {
  description = "IdM account OpenTofu signs in as (the same provisioning account as node1)."
  type        = string
  default     = "svc-opentofu"
}

variable "ipa_password" {
  type      = string
  sensitive = true
}

variable "base_image" {
  description = "The Debian 13 cloud image Catalyst pins (scripts/vm_lab.py in the Catalyst repository)."
  type = object({
    url    = string
    sha512 = string
  })
  default = {
    url    = "https://cloud.debian.org/images/cloud/trixie/20261026-2643/debian-13-generic-amd64-20261026-2643.qcow2"
    sha512 = "5bd891c6e62d01639f52a5587b72a4607421e445732214be787dba6043cf9797a6ff90bed982aada6a6c7e619f1f956d961c4fad76757171abd607920aac098a" # pragma: allowlist secret (public image checksum)
  }
}

variable "image_cache" {
  type    = string
  default = "~/.cache/locumview/images"
}

variable "admin_ssh_keys" {
  description = "Public keys for each VM's local break-glass account."
  type        = list(string)
}

variable "ssh_sources" {
  description = "IPv4 sources allowed to reach SSH on the VMs: the k3s nodes and the operator's admin machines."
  type        = list(string)
}

variable "extra_ca_file" {
  description = "A private CA certificate the VMs should trust (the Git server's), or empty."
  type        = string
  default     = ""
}

variable "catalyst_bundle" {
  description = "A git bundle of Catalyst's main (./tofu.sh bundle; tofu.sh passes its path)."
  type        = string
}

variable "timezone" {
  type    = string
  default = "America/New_York"
}

# One entry per contributor VM. Kept in the git-ignored catalyst-vms.auto.tfvars: it names people.
variable "catalyst_vms" {
  type = map(object({
    mac             = string
    directory_users = list(string)
    hostgroup       = string # the contributor's own, named by their HBAC and sudo rules
    memory_mib      = optional(number, 6144)
    vcpus           = optional(number, 4)
    root_gib        = optional(number, 40)
    home_gib        = optional(number, 60)
  }))
  default = {}
}
