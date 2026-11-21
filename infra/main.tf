provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

locals {
  # Network tag applied to Cloud Run; firewall rules in database/cache only allow this tag
  run_network_tag = "${var.project_name}-run"
}

# APIs required by the stack
resource "google_project_service" "services" {
  for_each = toset([
    "compute.googleapis.com",
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "secretmanager.googleapis.com",
    "memorystore.googleapis.com",
    "networkconnectivity.googleapis.com",
    "serviceconsumermanagement.googleapis.com",
    "monitoring.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

module "networking" {
  source = "./modules/networking"

  project_name        = var.project_name
  region              = var.gcp_region
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  psa_cidr            = var.psa_cidr

  depends_on = [google_project_service.services]
}

module "database" {
  source = "./modules/database"

  project_name    = var.project_name
  region          = var.gcp_region
  network_id      = module.networking.network_id
  network_name    = module.networking.network_name
  psa_cidr        = var.psa_cidr
  run_network_tag = local.run_network_tag

  db_tier     = var.db_tier
  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password

  max_connections = var.db_max_connections

  depends_on = [module.networking]
}

module "cache" {
  source = "./modules/cache"
  count  = var.enable_cache ? 1 : 0

  project_id          = var.gcp_project_id
  project_name        = var.project_name
  region              = var.gcp_region
  network_id          = module.networking.network_id
  network_name        = module.networking.network_name
  private_subnet_id   = module.networking.private_subnet_id
  private_subnet_cidr = var.private_subnet_cidr
  run_network_tag     = local.run_network_tag

  node_type     = var.cache_node_type
  replica_count = var.cache_replica_count

  depends_on = [module.networking]
}

module "cloudrun" {
  source = "./modules/cloudrun"

  project_id      = var.gcp_project_id
  project_name    = var.project_name
  region          = var.gcp_region
  network_id      = module.networking.network_id
  public_subnet   = module.networking.public_subnet_id
  run_network_tag = local.run_network_tag
  vpc_egress      = var.vpc_egress

  wordpress_image    = var.wordpress_image
  deployer_members   = ["serviceAccount:${var.app_deployer_service_account}"]
  min_instance_count = var.run_min_instances
  max_instance_count = var.run_max_instances

  db_host     = module.database.db_private_ip
  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password

  cache_host = var.enable_cache ? module.cache[0].valkey_host : ""
  cache_port = var.enable_cache ? module.cache[0].valkey_port : 6379

  depends_on = [module.database, module.cache]
}

module "monitoring" {
  source = "./modules/monitoring"

  project_id   = var.gcp_project_id
  project_name = var.project_name
  alert_emails = var.alert_emails

  lb_ip                  = module.cloudrun.lb_ip_address
  cloud_run_service_name = module.cloudrun.cloud_run_service_name
  run_max_instances      = var.run_max_instances

  db_instance_name   = module.database.db_instance_name
  db_max_connections = var.db_max_connections

  enable_cache       = var.enable_cache
  valkey_instance_id = var.enable_cache ? module.cache[0].valkey_instance_id : ""

  run_latency_p95_ms_threshold = var.alert_run_latency_p95_ms

  depends_on = [google_project_service.services]
}
