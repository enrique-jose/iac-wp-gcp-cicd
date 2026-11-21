variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "project_name" {
  description = "Name of the project, used as prefix for resource names"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "network_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet" {
  description = "ID of the subnet used for Direct VPC egress"
  type        = string
}

variable "run_network_tag" {
  description = "Network tag applied to Cloud Run so firewall rules allow DB access"
  type        = string
}

variable "vpc_egress" {
  description = "Cloud Run VPC egress setting"
  type        = string
}

variable "db_host" {
  description = "Host of the database"
  type        = string
}

variable "db_name" {
  description = "Name of the database"
  type        = string
}

variable "db_username" {
  description = "Username for the database"
  type        = string
}

variable "db_password" {
  description = "Password for the database"
  type        = string
  sensitive   = true
}

variable "cache_host" {
  description = "Valkey host for the object cache (empty to disable)"
  type        = string
  default     = ""
}

variable "cache_port" {
  description = "Valkey port for the object cache"
  type        = number
  default     = 6379
}

variable "wordpress_image" {
  description = "Initial container image (later revisions are deployed by CI/CD)"
  type        = string
  default     = "docker.io/library/wordpress:latest"
}

variable "min_instance_count" {
  description = "Minimum number of Cloud Run instances"
  type        = number
  default     = 1
}

variable "max_instance_count" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 3
}

variable "deployer_members" {
  description = "Members allowed to deploy revisions as the runtime SA (roles/iam.serviceAccountUser on it)"
  type        = list(string)
  default     = []
}
