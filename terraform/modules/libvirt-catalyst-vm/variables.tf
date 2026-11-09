variable "name" {
  description = "Short host name; the FQDN is <name>.<idm.domain>."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.name))
    error_message = "name must be a lower-case host name."
  }
}

variable "mac" {
  description = "Fixed MAC address on the LAN bridge; the host's bridge filter for this VM matches it."
  type        = string
  validation {
    condition     = can(regex("^52:54:00(:[0-9a-f]{2}){3}$", var.mac))
    error_message = "mac must be a libvirt-range address, 52:54:00:xx:xx:xx, in lower case."
  }
}

variable "memory_mib" {
  type    = number
  default = 6144
}

variable "vcpus" {
  type    = number
  default = 4
}

variable "root_gib" {
  description = "System disk, a copy-on-write layer over the base image."
  type        = number
  default     = 40
}

variable "home_gib" {
  description = "Separate home disk, mounted at /home. It survives rebuilds; OpenTofu refuses to destroy it."
  type        = number
  default     = 60
}

variable "pool" {
  type    = string
  default = "default"
}

variable "bridge" {
  type    = string
  default = "br0"
}

variable "libvirt_uri" {
  type = string
}

variable "ovmf_code" {
  type    = string
  default = "/usr/share/OVMF/OVMF_CODE_4M.ms.fd"
}

variable "ovmf_vars" {
  type    = string
  default = "/usr/share/OVMF/OVMF_VARS_4M.ms.fd"
}

variable "base_image" {
  description = "Debian cloud image, pinned by SHA-512 (the same pin as Catalyst's scripts/vm_lab.py)."
  type = object({
    url    = string
    sha512 = string
  })
}

variable "image_cache" {
  description = "Directory on the operator machine where the verified base image is kept."
  type        = string
}

variable "idm" {
  description = "IdM domain, realm and server, and the host groups the VM joins: the shared one and the contributor's own, which their HBAC and sudo rules name."
  type = object({
    domain     = string
    realm      = string
    server     = string
    hostgroups = list(string)
  })
}

variable "directory_users" {
  description = "IdM accounts that may log in over SSH (Catalyst's devalpine_ssh_directory_users)."
  type        = list(string)
}

variable "admin_ssh_keys" {
  description = "Public keys for the local break-glass account lvadmin."
  type        = list(string)
}

variable "ssh_sources" {
  description = "IPv4 sources allowed to reach SSH (the guest's own firewall)."
  type        = list(string)
}

variable "timezone" {
  type    = string
  default = "America/New_York"
}

variable "extra_ca_pem" {
  description = "A private certificate authority the guest should trust (Catalyst's devalpine_extra_ca_certificates), or empty."
  type        = string
  default     = ""
}

variable "catalyst_bundle" {
  description = "Path on the operator machine to a git bundle of Catalyst's main; it travels on the seed."
  type        = string
}

variable "secrets" {
  description = "From SOPS: the break-glass account's password."
  type = object({
    lvadmin_password = string
  })
  sensitive = true
}

variable "provision_timeout_minutes" {
  type    = number
  default = 45
}
