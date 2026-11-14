# Memorystore for Valkey - in-memory object cache for WordPress (equivalent to AWS ElastiCache).
# Valkey is reached through Private Service Connect, which needs a service connection policy.
resource "google_network_connectivity_service_connection_policy" "valkey" {
  name          = "${var.project_name}-valkey-scp"
  location      = var.region
  service_class = "gcp-memorystore"
  network       = var.network_id
  description   = "PSC policy for Memorystore for Valkey"

  psc_config {
    subnetworks = [var.private_subnet_id]
  }
}

# Firewall rules: only Cloud Run WordPress can reach Valkey on 6379
resource "google_compute_firewall" "allow_valkey_from_run" {
  name        = "${var.project_name}-allow-valkey-from-run"
  description = "Allow Valkey traffic from Cloud Run WordPress"
  network     = var.network_name
  direction   = "EGRESS"
  priority    = 900

  target_tags        = [var.run_network_tag]
  destination_ranges = [var.private_subnet_cidr]

  allow {
    protocol = "tcp"
    ports    = ["6379"]
  }
}

resource "google_compute_firewall" "deny_valkey_others" {
  name        = "${var.project_name}-deny-valkey-others"
  description = "Deny Valkey traffic from any other workload in the VPC"
  network     = var.network_name
  direction   = "EGRESS"
  priority    = 1000

  destination_ranges = [var.private_subnet_cidr]

  deny {
    protocol = "tcp"
    ports    = ["6379"]
  }
}

resource "google_memorystore_instance" "main" {
  instance_id                 = "${var.project_name}-valkey"
  location                    = var.region
  engine_version              = var.engine_version
  node_type                   = var.node_type
  mode                        = "CLUSTER_DISABLED"
  shard_count                 = 1
  replica_count               = var.replica_count
  authorization_mode          = "AUTH_DISABLED"
  transit_encryption_mode     = "TRANSIT_ENCRYPTION_DISABLED"
  deletion_protection_enabled = false

  desired_auto_created_endpoints {
    network    = var.network_id
    project_id = var.project_id
  }

  engine_configs = {
    "maxmemory-policy" = "allkeys-lru"
  }

  persistence_config {
    mode = "DISABLED"
  }

  labels = {
    name = "${var.project_name}-valkey"
  }

  depends_on = [google_network_connectivity_service_connection_policy.valkey]
}
