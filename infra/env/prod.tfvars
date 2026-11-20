# Non-secret values for the single (prod) environment.
# db_password is NOT here: Cloud Build injects it as TF_VAR_db_password from Secret Manager.
gcp_project_id = "cool-academy-489503-f3"
gcp_region     = "us-east1"

# Different prefix from iacode-wp-gcp2 ("wordpress-community"), which lives in the same project
project_name = "wp-cicd"

public_subnet_cidr  = "10.0.1.0/24"
private_subnet_cidr = "10.0.10.0/24"
psa_cidr            = "10.0.32.0/20"
vpc_egress          = "PRIVATE_RANGES_ONLY"

db_tier            = "db-f1-micro"
db_name            = "wordpressdb"
db_username        = "wpuser"
db_max_connections = 100

enable_cache        = true
cache_node_type     = "SHARED_CORE_NANO"
cache_replica_count = 0

run_min_instances = 1
run_max_instances = 3

alert_emails             = ["enriquejose@gmail.com"]
alert_run_latency_p95_ms = 2000
