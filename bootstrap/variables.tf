variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "Region for Cloud Build, Artifact Registry and the GitHub connection"
  type        = string
  default     = "us-east1"
}

variable "project_name" {
  description = "Prefix of the infra stack (must match infra/env/prod.tfvars project_name)"
  type        = string
  default     = "wp-cicd"
}

variable "github_connection_name" {
  description = "Name of the Cloud Build 2nd gen GitHub connection, created once from the console (Cloud Build > Repositories > Create host connection)"
  type        = string
  default     = "github"
}

variable "github_owner" {
  description = "GitHub user/organization that owns the repositories"
  type        = string
  default     = "enrique-jose"
}

variable "iac_repo_name" {
  description = "GitHub repository with the Terraform code"
  type        = string
  default     = "iac-wp-gcp-cicd"
}

variable "app_repo_name" {
  description = "GitHub repository with the WordPress fork"
  type        = string
  default     = "demo-wp"
}

variable "main_branch" {
  description = "Branch that deploys"
  type        = string
  default     = "main"
}

variable "approvers" {
  description = "Members allowed to approve infra-apply / infra-destroy builds (e.g. user:someone@example.com)"
  type        = list(string)
  default     = []
}

variable "terraform_version" {
  description = "Terraform version used by the pipelines"
  type        = string
  default     = "1.16.6"
}
