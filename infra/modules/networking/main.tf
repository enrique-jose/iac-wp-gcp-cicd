resource "google_compute_network" "main" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# Subnet used by Cloud Run (Direct VPC egress) - equivalent to the AWS public subnets
resource "google_compute_subnetwork" "public" {
  name                     = "${var.project_name}-public-subnet"
  ip_cidr_range            = var.public_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.main.id
  private_ip_google_access = true

  # Cloud Run Direct VPC egress keeps its serverless IPs reserved in this subnet for
  # 1-2h after the service is deleted. Wait for GCP to release them before deleting
  # the subnet, otherwise destroy fails with resourceInUseByAnotherResource.
  # Requires gcloud on the machine running terraform.
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      for i in $(seq 1 180); do
        n=$(gcloud compute addresses list --project "${self.project}" \
              --filter="purpose=SERVERLESS AND subnetwork~/${self.name}$" \
              --format="value(name)" | wc -l | tr -d ' ')
        [ "$n" = "0" ] && exit 0
        echo "Waiting for $n Cloud Run serverless IP(s) in ${self.name} to be released ($i/180)..."
        sleep 60
      done
      echo "Timed out waiting for serverless IPs to be released" >&2
      exit 1
    EOT
  }
}

resource "google_compute_subnetwork" "private" {
  name                     = "${var.project_name}-private-subnet"
  ip_cidr_range            = var.private_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.main.id
  private_ip_google_access = true
}

# Cloud Router + Cloud NAT - equivalent to the AWS NAT gateway
resource "google_compute_router" "main" {
  name    = "${var.project_name}-router"
  region  = var.region
  network = google_compute_network.main.id
}

resource "google_compute_router_nat" "main" {
  name                               = "${var.project_name}-nat"
  router                             = google_compute_router.main.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Private Service Access - private IPs for Cloud SQL / Memorystore inside the VPC
resource "google_compute_global_address" "psa" {
  name          = "${var.project_name}-psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = split("/", var.psa_cidr)[0]
  prefix_length = tonumber(split("/", var.psa_cidr)[1])
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa.name]
  deletion_policy         = "ABANDON"
}
