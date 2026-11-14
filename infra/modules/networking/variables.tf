variable "project_name" {
  description = "Name of the project, used as prefix for resource names"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR block for the Cloud Run subnet"
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
}

variable "psa_cidr" {
  description = "CIDR range reserved for Private Service Access"
  type        = string
}
