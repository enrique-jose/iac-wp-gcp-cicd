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

variable "network_name" {
  description = "Name of the VPC"
  type        = string
}

variable "psa_cidr" {
  description = "CIDR range reserved for Private Service Access"
  type        = string
}

variable "run_network_tag" {
  description = "Network tag of the Cloud Run workload allowed to reach the database"
  type        = string
}

variable "db_tier" {
  description = "Cloud SQL machine tier"
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

variable "max_connections" {
  description = "Value of the max_connections database flag"
  type        = number
  default     = 100
}
