output "dashboard_url" {
  description = "Cloud Monitoring dashboard URL"
  value       = local.dashboard_link
}

output "notification_channel_ids" {
  description = "IDs of the email notification channels"
  value       = local.channels
}

output "uptime_check_id" {
  description = "ID of the load balancer uptime check"
  value       = google_monitoring_uptime_check_config.lb.uptime_check_id
}
