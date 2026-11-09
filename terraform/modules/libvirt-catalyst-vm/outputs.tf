output "fqdn" {
  value = local.fqdn
}

output "home_volume" {
  description = "The home disk's path on the host; it outlives the VM."
  value       = libvirt_volume.home.path
}
