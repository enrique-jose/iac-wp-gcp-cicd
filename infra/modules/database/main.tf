# Firewall rules - equivalent to the AWS db / ecs_tasks security groups:
# only workloads tagged as Cloud Run WordPress can reach MySQL on 3306.
resource "google_compute_firewall" "allow_mysql_from_run" {
  name        = "${var.project_name}-allow-mysql-from-run"
  description = "Allow MySQL traffic from Cloud Run WordPress"
  network     = var.network_name
  direction   = "EGRESS"
  priority    = 900

  target_tags        = [var.run_network_tag]
  destination_ranges = [var.psa_cidr]

  allow {
    protocol = "tcp"
    ports    = ["3306"]
  }
}

resource "google_compute_firewall" "deny_mysql_others" {
  name        = "${var.project_name}-deny-mysql-others"
  description = "Deny MySQL traffic from any other workload in the VPC"
  network     = var.network_name
  direction   = "EGRESS"
  priority    = 1000

  destination_ranges = [var.psa_cidr]

  deny {
    protocol = "tcp"
    ports    = ["3306"]
  }
}

# Cloud SQL instance names cannot be reused for ~1 week after deletion
resource "random_id" "db_suffix" {
  byte_length = 3
}

resource "google_sql_database_instance" "main" {
  name                = "${var.project_name}-db-${random_id.db_suffix.hex}"
  database_version    = "MYSQL_8_0"
  region              = var.region
  deletion_protection = false

  settings {
    tier              = var.db_tier
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 20
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
    }

    backup_configuration {
      enabled            = true
      binary_log_enabled = true
      start_time         = "03:00"

      backup_retention_settings {
        retained_backups = 7
      }
    }

    database_flags {
      name  = "max_connections"
      value = tostring(var.max_connections)
    }

    user_labels = {
      name = "${var.project_name}-db"
    }
  }
}

resource "google_sql_database" "main" {
  name     = var.db_name
  instance = google_sql_database_instance.main.name
}

resource "google_sql_user" "main" {
  name     = var.db_username
  instance = google_sql_database_instance.main.name
  password = var.db_password
  host     = "%"
}
