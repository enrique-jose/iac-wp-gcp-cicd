output "valkey_host" {
  description = "Private IP of the Valkey primary endpoint"
  value       = try(google_memorystore_instance.main.endpoints[0].connections[0].psc_auto_connection[0].ip_address, "")
}

output "valkey_port" {
  description = "Port of the Valkey primary endpoint"
  value       = try(google_memorystore_instance.main.endpoints[0].connections[0].psc_auto_connection[0].port, 6379)
}

output "valkey_instance_id" {
  description = "Memorystore for Valkey instance ID"
  value       = google_memorystore_instance.main.instance_id
}
