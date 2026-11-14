output "state_bucket" {
  description = "Remote state bucket (must match infra/backend.tf)"
  value       = google_storage_bucket.tfstate.name
}

output "artifact_registry" {
  description = "Docker repository for the WordPress image"
  value       = local.ar_repo_url
}

output "tf_service_account" {
  description = "Service account used by the infra triggers"
  value       = google_service_account.tf.email
}

output "app_service_account" {
  description = "Service account used by the demo-wp triggers"
  value       = google_service_account.app.email
}

output "db_password_secret" {
  description = "Secret Manager secret with the DB password (TF_VAR_db_password)"
  value       = google_secret_manager_secret.tf_db_password.secret_id
}

output "triggers" {
  description = "Cloud Build triggers"
  value = {
    infra_plan    = google_cloudbuild_trigger.infra_plan.name
    infra_apply   = google_cloudbuild_trigger.infra_apply.name
    infra_destroy = google_cloudbuild_trigger.infra_destroy.name
    app_pr        = google_cloudbuild_trigger.app_pr.name
    app_deploy    = google_cloudbuild_trigger.app_deploy.name
  }
}
