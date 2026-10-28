terraform {
  required_version = ">= 1.10"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.9.9"
    }
    freeipa = {
      source  = "rework-space-com/freeipa"
      version = "5.6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.4.1"
    }
  }

  # The state holds each desktop's secrets (from SOPS) and its one-time IdM password, so it is always encrypted
  # (OpenTofu state encryption; the reason this repository uses OpenTofu, ADR 0013). The passphrase is kept in
  # SOPS too and passed as TF_VAR_state_passphrase by ./tofu.sh.
  encryption {
    key_provider "pbkdf2" "state" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "state" {
      keys = key_provider.pbkdf2.state
    }
    state {
      method   = method.aes_gcm.state
      enforced = true
    }
    plan {
      method   = method.aes_gcm.state
      enforced = true
    }
  }
}
