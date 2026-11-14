# One-time bootstrap for the CI/CD of the WordPress stack.
# Creates what the pipelines need before they can run: remote state bucket,
# Artifact Registry, the DB password secret, service accounts + IAM, the GitHub
# repositories (on an existing 2nd gen connection) and the Cloud Build triggers.

data "google_project" "current" {}

locals {
  run_sa_email = "${substr("${var.project_name}-run", 0, 30)}@${var.gcp_project_id}.iam.gserviceaccount.com"
  ar_repo_url  = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.wordpress.repository_id}"
  branch_regex = "^${var.main_branch}$"
}

# ---------------------------------------------------------------------------
# APIs
# ---------------------------------------------------------------------------
resource "google_project_service" "services" {
  for_each = toset([
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Remote state bucket (also stores the PR plans under plans/)
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "tfstate" {
  name                        = "${var.gcp_project_id}-tfstate"
  location                    = var.gcp_region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 20
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age            = 30
      matches_prefix = ["plans/"]
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.services]
}

# ---------------------------------------------------------------------------
# Artifact Registry for the WordPress fork image
# ---------------------------------------------------------------------------
resource "google_artifact_registry_repository" "wordpress" {
  repository_id = var.project_name
  location      = var.gcp_region
  format        = "DOCKER"
  description   = "WordPress images built from ${var.github_owner}/${var.app_repo_name}"

  cleanup_policies {
    id     = "keep-last-20"
    action = "KEEP"
    most_recent_versions {
      keep_count = 20
    }
  }

  cleanup_policies {
    id     = "delete-old-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "1209600s" # 14 days
    }
  }

  depends_on = [google_project_service.services]
}

# ---------------------------------------------------------------------------
# DB password consumed by the infra pipeline as TF_VAR_db_password
# ---------------------------------------------------------------------------
resource "random_password" "db" {
  length  = 24
  special = false
}

resource "google_secret_manager_secret" "tf_db_password" {
  secret_id = "${var.project_name}-tf-db-password"

  replication {
    auto {}
  }

  depends_on = [google_project_service.services]
}

resource "google_secret_manager_secret_version" "tf_db_password" {
  secret      = google_secret_manager_secret.tf_db_password.id
  secret_data = random_password.db.result
}

# ---------------------------------------------------------------------------
# Service account: infra pipelines (terraform plan / apply / destroy)
# ---------------------------------------------------------------------------
resource "google_service_account" "tf" {
  account_id   = "${var.project_name}-tf"
  display_name = "${var.project_name} Terraform (Cloud Build)"
}

resource "google_project_iam_member" "tf" {
  for_each = toset([
    "roles/compute.admin",
    "roles/cloudsql.admin",
    "roles/memorystore.admin",
    "roles/networkconnectivity.admin",
    "roles/servicenetworking.networksAdmin",
    "roles/run.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/resourcemanager.projectIamAdmin",
    "roles/secretmanager.admin",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/monitoring.editor",
    "roles/logging.configWriter",
    "roles/logging.logWriter",
  ])

  project = var.gcp_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.tf.email}"
}

resource "google_storage_bucket_iam_member" "tf_state" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.tf.email}"
}

resource "google_secret_manager_secret_iam_member" "tf_db_password" {
  secret_id = google_secret_manager_secret.tf_db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.tf.email}"
}

# ---------------------------------------------------------------------------
# Service account: app pipeline (build image + deploy new Cloud Run revision)
# ---------------------------------------------------------------------------
resource "google_service_account" "app" {
  account_id   = "${var.project_name}-app"
  display_name = "${var.project_name} app deploy (Cloud Build)"
}

resource "google_project_iam_member" "app" {
  for_each = toset([
    "roles/run.developer",
    "roles/logging.logWriter",
    "roles/compute.viewer", # read the LB IP for the smoke test
  ])

  project = var.gcp_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.app.email}"
}

resource "google_artifact_registry_repository_iam_member" "app_writer" {
  repository = google_artifact_registry_repository.wordpress.name
  location   = google_artifact_registry_repository.wordpress.location
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.app.email}"
}

# Deploying a revision requires actAs on the runtime SA of the service.
# That SA is created by the infra stack, so the binding is project-level but
# conditioned to that single service account.
resource "google_project_iam_member" "app_act_as_run_sa" {
  project = var.gcp_project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.app.email}"

  condition {
    title      = "only-${var.project_name}-run-sa"
    expression = "resource.name == \"projects/-/serviceAccounts/${local.run_sa_email}\""
  }
}

# ---------------------------------------------------------------------------
# Build approvers
# ---------------------------------------------------------------------------
resource "google_project_iam_member" "approvers" {
  for_each = toset(var.approvers)

  project = var.gcp_project_id
  role    = "roles/cloudbuild.builds.approver"
  member  = each.value
}

# ---------------------------------------------------------------------------
# GitHub repositories on the existing 2nd gen connection
# ---------------------------------------------------------------------------
resource "google_cloudbuildv2_repository" "iac" {
  name              = var.iac_repo_name
  location          = var.gcp_region
  parent_connection = var.github_connection_name
  remote_uri        = "https://github.com/${var.github_owner}/${var.iac_repo_name}.git"

  depends_on = [google_project_service.services]
}

resource "google_cloudbuildv2_repository" "app" {
  name              = var.app_repo_name
  location          = var.gcp_region
  parent_connection = var.github_connection_name
  remote_uri        = "https://github.com/${var.github_owner}/${var.app_repo_name}.git"

  depends_on = [google_project_service.services]
}

# ---------------------------------------------------------------------------
# Triggers - infra (repo iac-wp-gcp-cicd, configs in infra/cloudbuild/)
# ---------------------------------------------------------------------------
locals {
  infra_substitutions = {
    _TF_VERSION   = var.terraform_version
    _STATE_BUCKET = google_storage_bucket.tfstate.name
    _TFVARS       = "env/prod.tfvars"
    _DB_SECRET    = google_secret_manager_secret.tf_db_password.secret_id
  }
}

resource "google_cloudbuild_trigger" "infra_plan" {
  name            = "${var.project_name}-infra-plan"
  location        = var.gcp_region
  description     = "PR to ${var.main_branch}: fmt, validate, tflint and terraform plan"
  filename        = "infra/cloudbuild/infra-plan.yaml"
  included_files  = ["infra/**"]
  service_account = google_service_account.tf.id
  substitutions   = local.infra_substitutions

  repository_event_config {
    repository = google_cloudbuildv2_repository.iac.id
    pull_request {
      branch          = local.branch_regex
      comment_control = "COMMENTS_ENABLED_FOR_EXTERNAL_CONTRIBUTORS_ONLY"
    }
  }
}

resource "google_cloudbuild_trigger" "infra_apply" {
  name            = "${var.project_name}-infra-apply"
  location        = var.gcp_region
  description     = "Push to ${var.main_branch}: terraform apply (requires approval)"
  filename        = "infra/cloudbuild/infra-apply.yaml"
  included_files  = ["infra/**"]
  service_account = google_service_account.tf.id
  substitutions   = local.infra_substitutions

  repository_event_config {
    repository = google_cloudbuildv2_repository.iac.id
    push {
      branch = local.branch_regex
    }
  }

  approval_config {
    approval_required = true
  }
}

resource "google_cloudbuild_trigger" "infra_destroy" {
  name            = "${var.project_name}-infra-destroy"
  location        = var.gcp_region
  description     = "Manual: terraform destroy of the whole stack (requires approval)"
  service_account = google_service_account.tf.id
  substitutions   = local.infra_substitutions

  source_to_build {
    repository = google_cloudbuildv2_repository.iac.id
    ref        = "refs/heads/${var.main_branch}"
    repo_type  = "GITHUB"
  }

  git_file_source {
    path       = "infra/cloudbuild/infra-destroy.yaml"
    repository = google_cloudbuildv2_repository.iac.id
    revision   = "refs/heads/${var.main_branch}"
    repo_type  = "GITHUB"
  }

  approval_config {
    approval_required = true
  }
}

# ---------------------------------------------------------------------------
# Triggers - app (repo demo-wp, config cloudbuild.yaml at the repo root)
# ---------------------------------------------------------------------------
locals {
  app_substitutions = {
    _REGION  = var.gcp_region
    _AR_REPO = local.ar_repo_url
    _SERVICE = "${var.project_name}-service"
    _LB_IP   = "${var.project_name}-lb-ip"
  }
}

resource "google_cloudbuild_trigger" "app_pr" {
  name            = "${var.project_name}-app-pr"
  location        = var.gcp_region
  description     = "PR to ${var.main_branch} in ${var.app_repo_name}: lint + docker build (no deploy)"
  filename        = "cloudbuild.yaml"
  service_account = google_service_account.app.id
  substitutions   = merge(local.app_substitutions, { _DEPLOY = "false" })

  repository_event_config {
    repository = google_cloudbuildv2_repository.app.id
    pull_request {
      branch          = local.branch_regex
      comment_control = "COMMENTS_ENABLED_FOR_EXTERNAL_CONTRIBUTORS_ONLY"
    }
  }
}

resource "google_cloudbuild_trigger" "app_deploy" {
  name            = "${var.project_name}-app-deploy"
  location        = var.gcp_region
  description     = "Push to ${var.main_branch} in ${var.app_repo_name}: build, push and deploy to Cloud Run"
  filename        = "cloudbuild.yaml"
  service_account = google_service_account.app.id
  substitutions   = merge(local.app_substitutions, { _DEPLOY = "true" })

  repository_event_config {
    repository = google_cloudbuildv2_repository.app.id
    push {
      branch = local.branch_regex
    }
  }
}
