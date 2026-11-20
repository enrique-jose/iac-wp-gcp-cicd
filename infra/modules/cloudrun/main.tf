locals {
  wp_config_extra = join("\n", compact([
    "define('WP_MEMORY_LIMIT', '256M');",
    # Behind the load balancer: trust the forwarded protocol
    "if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') { $_SERVER['HTTPS'] = 'on'; }",
    # Object cache on Valkey (Redis protocol compatible, used by the Redis Object Cache plugin)
    var.cache_host != "" ? "define('WP_REDIS_HOST', '${var.cache_host}');" : "",
    var.cache_host != "" ? "define('WP_REDIS_PORT', ${var.cache_port});" : "",
    var.cache_host != "" ? "define('WP_REDIS_PREFIX', '${var.project_name}:');" : "",
  ]))
}

# Service account - equivalent to the AWS ECS execution / task roles
resource "google_service_account" "run" {
  account_id   = substr("${var.project_name}-run", 0, 30)
  display_name = "${var.project_name} Cloud Run service account"
}

resource "google_project_iam_member" "run" {
  for_each = toset([
    "roles/cloudsql.client",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/artifactregistry.reader",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.run.email}"
}

# DB password stored in Secret Manager instead of a plain env var
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.project_name}-db-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = var.db_password
}

resource "google_secret_manager_secret_iam_member" "run" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.run.email}"
}

# Cloud Run service - equivalent to the AWS ECS cluster + task definition + service
resource "google_cloud_run_v2_service" "main" {
  name                = "${var.project_name}-service"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  deletion_protection = false

  # Public access without granting roles/run.invoker to allUsers (blocked by the
  # iam.allowedPolicyMemberDomains org policy). Ingress still only accepts the LB.
  invoker_iam_disabled = true

  template {
    service_account = google_service_account.run.email

    scaling {
      min_instance_count = var.min_instance_count
      max_instance_count = var.max_instance_count
    }

    vpc_access {
      egress = var.vpc_egress

      network_interfaces {
        network    = var.network_id
        subnetwork = var.public_subnet
        tags       = [var.run_network_tag]
      }
    }

    containers {
      name  = "wordpress"
      image = var.wordpress_image

      ports {
        container_port = 80
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }

      env {
        name  = "WORDPRESS_DB_HOST"
        value = var.db_host
      }

      env {
        name  = "WORDPRESS_DB_NAME"
        value = var.db_name
      }

      env {
        name  = "WORDPRESS_DB_USER"
        value = var.db_username
      }

      env {
        name = "WORDPRESS_DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password.secret_id
            version = "latest"
          }
        }
      }

      env {
        name  = "WORDPRESS_CONFIG_EXTRA"
        value = local.wp_config_extra
      }

      startup_probe {
        initial_delay_seconds = 10
        period_seconds        = 10
        timeout_seconds       = 5
        failure_threshold     = 6

        tcp_socket {
          port = 80
        }
      }

      liveness_probe {
        initial_delay_seconds = 60
        period_seconds        = 30
        timeout_seconds       = 5
        failure_threshold     = 3

        http_get {
          path = "/"
          port = 80
        }
      }
    }
  }

  labels = {
    name = "${var.project_name}-service"
  }

  # The image (and the client that deployed it) is owned by the demo-wp Cloud Build
  # pipeline (gcloud run services update), and so is traffic (its smoke test can roll
  # back to the previous revision). Terraform only creates the service.
  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
      traffic,
    ]
  }

  depends_on = [
    google_secret_manager_secret_iam_member.run,
    google_secret_manager_secret_version.db_password,
  ]
}

# External HTTP load balancer - equivalent to the AWS ALB + target group + listener
resource "google_compute_global_address" "lb" {
  name = "${var.project_name}-lb-ip"
}

resource "google_compute_region_network_endpoint_group" "run" {
  name                  = "${var.project_name}-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.main.name
  }
}

resource "google_compute_backend_service" "main" {
  name                  = "${var.project_name}-backend"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_region_network_endpoint_group.run.id
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_url_map" "main" {
  name            = "${var.project_name}-urlmap"
  default_service = google_compute_backend_service.main.id
}

resource "google_compute_target_http_proxy" "main" {
  name    = "${var.project_name}-http-proxy"
  url_map = google_compute_url_map.main.id
}

resource "google_compute_global_forwarding_rule" "http" {
  name                  = "${var.project_name}-http"
  target                = google_compute_target_http_proxy.main.id
  ip_address            = google_compute_global_address.lb.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
