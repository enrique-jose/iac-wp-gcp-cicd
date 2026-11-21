# 2. Infrastructure

## Estructura de Terraform

```
bootstrap/                      # stack 1: se aplica en local una vez (estado local)
infra/                          # stack 2: lo aplica Cloud Build (estado en GCS)
├── backend.tf                  # gs://cool-academy-489503-f3-tfstate, prefix "wordpress"
├── main.tf                     # APIs + llamadas a módulos
├── variables.tf / outputs.tf / versions.tf
├── env/prod.tfvars             # valores del entorno (sin secretos)
├── cloudbuild/                 # pipelines (ver 3-Ci-cd.md)
└── modules/
    ├── networking/
    ├── database/
    ├── cache/
    ├── cloudrun/
    └── monitoring/
```

- Versiones: Terraform `>= 1.5.0` (los pipelines usan la `1.16.6`), provider `hashicorp/google ~> 6.0` y `hashicorp/random ~> 3.6`. Cada módulo declara sus propias restricciones de versión en su `versions.tf`.
- Dependencias entre módulos: `networking` → `database` y `cache` → `cloudrun` → `monitoring`.

## APIs habilitadas por `infra`

`compute`, `run`, `sqladmin`, `servicenetworking`, `secretmanager`, `memorystore`, `networkconnectivity`, `serviceconsumermanagement` y `monitoring`. Todas usan `disable_on_destroy = false`. El bootstrap habilita además las APIs del CI/CD ([CI/CD](3-Ci-cd.md)).

## Módulo `networking`

| Recurso | Nombre | Detalle |
|---|---|---|
| VPC | `wp-cicd-vpc` | custom (`auto_create_subnetworks = false`), routing `REGIONAL` |
| Subred public | `wp-cicd-public-subnet` | `10.0.1.0/24`, Private Google Access. La usa Cloud Run (Direct VPC egress) |
| Subred private | `wp-cicd-private-subnet` | `10.0.10.0/24`, Private Google Access. Aloja el endpoint PSC de Valkey |
| Cloud Router + NAT | `wp-cicd-router` y `wp-cicd-nat` | NAT para todas las subredes, IPs automáticas, log solo de errores |
| Rango PSA | `wp-cicd-psa-range` | `10.0.32.0/20` (`VPC_PEERING`) |
| Peering PSA | `servicenetworking.googleapis.com` | `deletion_policy = "ABANDON"`, porque Cloud SQL libera el peering con horas de retraso |

> La subred `public` tiene un **provisioner de destroy** que espera, hasta 3 h y llamando a `gcloud`, a que Cloud Run libere sus IPs serverless (`serverless-ipv4-cloudrun-*`). Tarda entre 1 y 2 h después de borrar el servicio. Por eso `infra-destroy` usa la imagen de `gcloud`.

## Módulo `database`

Cloud SQL MySQL 8.0, que se detalla en [Data](5-Data.md#cloud-sql-mysql). También crea los firewalls de egress:

| Regla | Prioridad | Efecto |
|---|---|---|
| `wp-cicd-allow-mysql-from-run` | 900 | **allow** tcp/3306 hacia `10.0.32.0/20` desde el tag `wp-cicd-run` |
| `wp-cicd-deny-mysql-others` | 1000 | **deny** tcp/3306 hacia `10.0.32.0/20` para el resto de la VPC |

## Módulo `cache` (`enable_cache = true`)

Memorystore for Valkey, que se detalla en [Data](5-Data.md#memorystore-for-valkey). Crea:

- la **service connection policy** `wp-cicd-valkey-scp` (clase `gcp-memorystore`) sobre la subred `private`;
- los firewalls equivalentes a los de la BD, para tcp/6379 hacia `10.0.10.0/24`.

## Módulo `cloudrun`

| Recurso | Detalle |
|---|---|
| SA `wp-cicd-run` | `cloudsql.client`, `logging.logWriter`, `monitoring.metricWriter` y `artifactregistry.reader` |
| Secret `wp-cicd-db-password` | Valor de `var.db_password`. El SA de Run tiene `secretAccessor` |
| Servicio `wp-cicd-service` | Cloud Run v2. `ingress = INTERNAL_LOAD_BALANCER`, `invoker_iam_disabled = true` |
| Escalado | `min = 1`, `max = 3` (`run_min_instances` / `run_max_instances`) |
| Contenedor | puerto 80, 1 vCPU y 1 GiB. Imagen inicial `docker.io/library/wordpress:latest` |
| Probes | startup TCP :80 (10 s / 6 intentos), liveness HTTP `/` (cada 30 s) |
| VPC | Direct VPC egress en la subred `public`, tag `wp-cicd-run`, egress `PRIVATE_RANGES_ONLY` |
| `lifecycle.ignore_changes` | `image`, `client`, `client_version` y `traffic`. Los gestiona el pipeline de la app |
| LB | IP global `wp-cicd-lb-ip`, NEG serverless `wp-cicd-neg`, backend `wp-cicd-backend` (log al 100 %), URL map, HTTP proxy y forwarding rule `:80` (`EXTERNAL_MANAGED`) |

Variables de entorno del contenedor:
- `WORDPRESS_DB_HOST`, `WORDPRESS_DB_NAME` y `WORDPRESS_DB_USER`;
- `WORDPRESS_DB_PASSWORD`, que se lee del secret;
- `WORDPRESS_CONFIG_EXTRA`, que define `WP_MEMORY_LIMIT`, la detección de HTTPS detrás del LB y `WP_REDIS_HOST/PORT/PREFIX`.

## Módulo `monitoring`

Dashboard, uptime check, métrica de logs y alertas. Se detalla en [Observability](7-Observability.md).

## Variables principales (`infra/env/prod.tfvars`)

| Variable | Valor | Descripción |
|---|---|---|
| `gcp_project_id` | `cool-academy-489503-f3` | Proyecto |
| `gcp_region` | `us-east1` | Región |
| `project_name` | `wp-cicd` | Prefijo de todos los recursos |
| `public_subnet_cidr` / `private_subnet_cidr` / `psa_cidr` | `10.0.1.0/24` / `10.0.10.0/24` / `10.0.32.0/20` | Rangos de red |
| `vpc_egress` | `PRIVATE_RANGES_ONLY` | `ALL_TRAFFIC` hace que todo el tráfico de Run salga por Cloud NAT |
| `db_tier` / `db_name` / `db_username` | `db-f1-micro` / `wordpressdb` / `wpuser` | Cloud SQL |
| `db_max_connections` | `100` | Flag de MySQL. También es el umbral de la alerta |
| `enable_cache` / `cache_node_type` / `cache_replica_count` | `true` / `SHARED_CORE_NANO` / `0` | Valkey |
| `run_min_instances` / `run_max_instances` | `1` / `3` | Escalado de Cloud Run |
| `alert_emails` | `["enriquejose@gmail.com"]` | Destinatarios de las alertas |
| `alert_run_latency_p95_ms` | `2000` | Umbral de latencia |
| `db_password` | (no está en el archivo) | Lo inyecta Cloud Build como `TF_VAR_db_password` |

## Outputs

`wordpress_url`, `cloud_run_url`, `lb_ip`, `cloud_run_service_name`, `cloud_run_service_account`, `db_endpoint` (sensible), `db_connection_name`, `db_instance_name`, `valkey_host`, `vpc_id` y `dashboard_url`. Se imprimen en el paso `outputs` de `infra-apply`.

## Diferencias con `iacode-wp-gcp2`

| Cambio | Dónde |
|---|---|
| Estado remoto en GCS, en lugar de local | `infra/backend.tf` |
| `db_password` desde Secret Manager (CI), en lugar de `terraform.tfvars` | pipelines |
| Prefijo `wp-cicd`, en lugar de `wordpress-community` | `env/prod.tfvars` |
| Variables `wordpress_image`, `run_min/max_instances` y `db_max_connections` | `variables.tf` y módulos |
| `ignore_changes` en image, client y traffic de Cloud Run | `modules/cloudrun` |
| `artifactregistry.reader` en el SA de Run | `modules/cloudrun` |
| Módulo `monitoring` | `modules/monitoring` |
| `versions.tf` por módulo (lo exige tflint) | `modules/*/versions.tf` |

## Cambiar la infraestructura

1. Crea una rama y modifica `infra/`. Ejecuta en local:
   ```bash
   cd infra
   terraform fmt -recursive
   terraform init -backend=false
   terraform validate
   ```
2. Abre un PR. `wp-cicd-infra-plan` publica el plan. Revisa `Plan: X to add, Y to change, Z to destroy` en el log o en `gs://cool-academy-489503-f3-tfstate/plans/pr-<n>/<sha>/plan.txt`.
3. Haz merge y aprueba `wp-cicd-infra-apply` ([CI/CD](3-Ci-cd.md#aprobar-un-build)).

> ⚠️ Cambios que **recrean** Cloud SQL: `database_version`, `region` y el nombre de la instancia. Se pierden los datos. Revisa siempre que el plan no muestre `must be replaced` en `google_sql_database_instance`.
