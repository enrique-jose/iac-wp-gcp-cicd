variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "project_name" {
  description = "Name of the project, used as prefix for resource names"
  type        = string
}

variable "alert_emails" {
  description = "Email addresses that receive the alerts"
  type        = list(string)
}

variable "lb_ip" {
  description = "Public IP of the HTTP load balancer (uptime check target)"
  type        = string
}

variable "uptime_path" {
  description = "Path probed by the uptime check"
  type        = string
  default     = "/wp-login.php"
}

variable "cloud_run_service_name" {
  description = "Name of the Cloud Run service"
  type        = string
}

variable "run_max_instances" {
  description = "Cloud Run max instances (threshold for the saturation alert)"
  type        = number
}

variable "db_instance_name" {
  description = "Name of the Cloud SQL instance"
  type        = string
}

variable "db_max_connections" {
  description = "Cloud SQL max_connections (threshold for the connections alert)"
  type        = number
}

variable "enable_cache" {
  description = "Whether the Valkey instance exists (adds the Valkey widgets and alerts)"
  type        = bool
}

variable "valkey_instance_id" {
  description = "Memorystore for Valkey instance ID"
  type        = string
  default     = ""
}

# ---- Thresholds ----

variable "run_latency_p95_ms_threshold" {
  description = "Cloud Run p95 latency threshold in ms"
  type        = number
  default     = 2000
}

variable "lb_5xx_ratio_threshold" {
  description = "Load balancer 5xx ratio threshold (0-1)"
  type        = number
  default     = 0.05
}

variable "run_memory_threshold" {
  description = "Cloud Run p99 memory utilization threshold (0-1)"
  type        = number
  default     = 0.85
}

variable "php_fatal_errors_threshold" {
  description = "PHP fatal errors in 5 minutes that trigger the alert"
  type        = number
  default     = 5
}

variable "db_cpu_threshold" {
  description = "Cloud SQL CPU utilization threshold (0-1)"
  type        = number
  default     = 0.8
}

variable "db_memory_threshold" {
  description = "Cloud SQL memory utilization threshold (0-1)"
  type        = number
  default     = 0.9
}

variable "db_disk_threshold" {
  description = "Cloud SQL disk utilization threshold (0-1)"
  type        = number
  default     = 0.85
}

variable "db_connections_ratio" {
  description = "Fraction of max_connections that triggers the connections alert"
  type        = number
  default     = 0.8
}

variable "valkey_memory_threshold" {
  description = "Valkey memory utilization threshold (0-1)"
  type        = number
  default     = 0.85
}

variable "valkey_hit_ratio_threshold" {
  description = "Valkey cache hit ratio below which the alert fires (0-1)"
  type        = number
  default     = 0.7
}
