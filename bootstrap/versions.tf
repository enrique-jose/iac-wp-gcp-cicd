terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Bootstrap state stays local (it creates the remote state bucket).
  # Keep bootstrap/terraform.tfstate safe; it is git-ignored.
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}
