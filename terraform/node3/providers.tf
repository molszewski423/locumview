provider "libvirt" {
  uri = var.libvirt_uri
}

provider "freeipa" {
  host           = var.idm.server
  username       = var.ipa_username
  password       = var.ipa_password
  ca_certificate = var.idm_ca_certificate
}

provider "sops" {}
