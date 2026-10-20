terraform {
  required_version = ">= 1.10"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.9"
    }
    freeipa = {
      source  = "rework-space-com/freeipa"
      version = "~> 5.6"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}
