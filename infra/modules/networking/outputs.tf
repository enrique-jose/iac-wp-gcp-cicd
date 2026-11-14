output "network_id" {
  description = "ID of the VPC"
  value       = google_compute_network.main.id
}

output "network_name" {
  description = "Name of the VPC"
  value       = google_compute_network.main.name
}

output "public_subnet_id" {
  description = "ID of the Cloud Run subnet"
  value       = google_compute_subnetwork.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = google_compute_subnetwork.private.id
}

output "psa_connection_id" {
  description = "ID of the Private Service Access connection"
  value       = google_service_networking_connection.psa.id
}
