# Remote state in GCS (created by ../bootstrap). GCS provides native state locking.
terraform {
  backend "gcs" {
    bucket = "cool-academy-489503-f3-tfstate"
    prefix = "wordpress"
  }
}
