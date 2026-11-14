output "wordpress_url" {
  description = "URL to access the WordPress site"
  value       = "http://${google_compute_global_address.lb.address}"
}

output "cloud_run_url" {
  description = "Direct Cloud Run service URL"
  value       = google_cloud_run_v2_service.main.uri
}

output "cloud_run_service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_v2_service.main.name
}

output "service_account_email" {
  description = "Email of the Cloud Run service account"
  value       = google_service_account.run.email
}

output "lb_forwarding_rule_name" {
  description = "Name of the global forwarding rule of the HTTP load balancer"
  value       = google_compute_global_forwarding_rule.http.name
}

output "lb_ip_address" {
  description = "Public IP of the HTTP load balancer"
  value       = google_compute_global_address.lb.address
}
