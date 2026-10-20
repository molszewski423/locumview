output "fqdn" {
  description = "The desktop's host name in the IdM domain."
  value       = local.fqdn
}

output "domain_name" {
  description = "libvirt domain name."
  value       = libvirt_domain.desktop.name
}

output "provisioned" {
  description = "Set once first boot has finished and the seed is wiped."
  value       = terraform_data.provisioned.id
}

output "guacamole_connection" {
  description = "Name of the desktop's Guacamole connection, if one was made."
  value       = var.guacamole == null ? null : terraform_data.guacamole[0].input.name
}
