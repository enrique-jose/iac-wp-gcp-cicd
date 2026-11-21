variable "gcp_project_id" {
  description = "GCP project ID where resources will be created"
  type        = string
}

variable "gcp_region" {
  description = "GCP region where resources will be created"
  type        = string
  default     = "us-east1"
}

variable "project_name" {
  description = "Name of the project, used as prefix for resource names"
  type        = string
  default     = "wordpress-community"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the subnet used by Cloud Run (Direct VPC egress, min /26)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.10.0/24"
}

variable "psa_cidr" {
  description = "CIDR range reserved for Private Service Access (Cloud SQL / Memorystore private IPs)"
  type        = string
  default     = "10.0.32.0/20"
}

variable "vpc_egress" {
  description = "Cloud Run VPC egress: PRIVATE_RANGES_ONLY (internet direct) or ALL_TRAFFIC (internet via Cloud NAT)"
  type        = string
  default     = "PRIVATE_RANGES_ONLY"

  validation {
    condition     = contains(["PRIVATE_RANGES_ONLY", "ALL_TRAFFIC"], var.vpc_egress)
    error_message = "vpc_egress must be PRIVATE_RANGES_ONLY or ALL_TRAFFIC."
  }
}

variable "db_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-f1-micro"
}

variable "db_name" {
  description = "Name of the WordPress database"
  type        = string
  default     = "wordpressdb"
}

variable "db_username" {
  description = "Username for the WordPress database"
  type        = string
  default     = "wpuser"
}

variable "db_password" {
  description = "Password for the WordPress database"
  type        = string
  sensitive   = true
}

variable "enable_cache" {
  description = "Create a Memorystore for Valkey instance for the WordPress object cache"
  type        = bool
  default     = true
}

variable "cache_node_type" {
  description = "Memorystore for Valkey node type (SHARED_CORE_NANO, STANDARD_SMALL, HIGHMEM_MEDIUM, ...)"
  type        = string
  default     = "SHARED_CORE_NANO"
}

variable "cache_replica_count" {
  description = "Number of Valkey read replicas"
  type        = number
  default     = 0
}

variable "db_max_connections" {
  description = "Cloud SQL max_connections flag (also used by the connections alert)"
  type        = number
  default     = 100
}

variable "wordpress_image" {
  description = "Initial container image for Cloud Run. Later revisions are deployed by the demo-wp pipeline (Terraform ignores image changes)"
  type        = string
  default     = "docker.io/library/wordpress:latest"
}

variable "run_min_instances" {
  description = "Minimum Cloud Run instances"
  type        = number
  default     = 1
}

variable "run_max_instances" {
  description = "Maximum Cloud Run instances"
  type        = number
  default     = 3
}

variable "alert_emails" {
  description = "Email addresses that receive the monitoring alerts"
  type        = list(string)
  default     = []
}

variable "alert_run_latency_p95_ms" {
  description = "Cloud Run p95 latency threshold (ms) for the backend latency alert"
  type        = number
  default     = 2000
}

variable "app_deployer_service_account" {
  description = "Service account of the demo-wp deploy pipeline (created by bootstrap)"
  type        = string
}
