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

variable "network_name" {
  description = "Name of the VPC"
  type        = string
}

variable "private_subnet_id" {
  description = "ID of the subnet where the Valkey PSC endpoint is created"
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR block of the subnet where the Valkey PSC endpoint is created"
  type        = string
}

variable "run_network_tag" {
  description = "Network tag of the Cloud Run workload allowed to reach Valkey"
  type        = string
}

variable "engine_version" {
  description = "Valkey engine version"
  type        = string
  default     = "VALKEY_8_0"
}

variable "node_type" {
  description = "Valkey node type (SHARED_CORE_NANO, STANDARD_SMALL, HIGHMEM_MEDIUM, ...)"
  type        = string
  default     = "SHARED_CORE_NANO"
}

variable "replica_count" {
  description = "Number of read replicas"
  type        = number
  default     = 0
}
