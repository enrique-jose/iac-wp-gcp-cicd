output "wordpress_url" {
  description = "URL to access the WordPress site (through the HTTP load balancer)"
  value       = module.cloudrun.wordpress_url
}

output "cloud_run_url" {
  description = "Direct Cloud Run URL (only reachable via the load balancer, ingress is restricted)"
  value       = module.cloudrun.cloud_run_url
}

output "db_endpoint" {
  description = "Private IP of the Cloud SQL instance"
  value       = module.database.db_private_ip
  sensitive   = true
}

output "db_connection_name" {
  description = "Cloud SQL connection name (project:region:instance)"
  value       = module.database.db_connection_name
}

output "valkey_host" {
  description = "Memorystore for Valkey host (empty when the cache is disabled)"
  value       = var.enable_cache ? module.cache[0].valkey_host : ""
}

output "vpc_id" {
  description = "ID of the VPC created"
  value       = module.networking.network_id
}

output "lb_ip" {
  description = "Public IP of the HTTP load balancer"
  value       = module.cloudrun.lb_ip_address
}

output "cloud_run_service_name" {
  description = "Name of the Cloud Run service (used by the demo-wp deploy pipeline)"
  value       = module.cloudrun.cloud_run_service_name
}

output "cloud_run_service_account" {
  description = "Service account used by Cloud Run"
  value       = module.cloudrun.service_account_email
}

output "db_instance_name" {
  description = "Name of the Cloud SQL instance"
  value       = module.database.db_instance_name
}

output "dashboard_url" {
  description = "Cloud Monitoring dashboard URL"
  value       = module.monitoring.dashboard_url
}
