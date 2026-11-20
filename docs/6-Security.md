# 6. Security

## Service accounts

| SA | La usa | Roles |
|---|---|---|
| `wp-cicd-tf` | Triggers `infra-plan`, `infra-apply` e `infra-destroy` | Proyecto: `compute.admin`, `cloudsql.admin`, `memorystore.admin`, `networkconnectivity.admin`, `servicenetworking.networksAdmin`, `run.admin`, `iam.serviceAccountAdmin`, `iam.serviceAccountUser`, `resourcemanager.projectIamAdmin`, `secretmanager.admin`, `serviceusage.serviceUsageAdmin`, `monitoring.editor`, `logging.configWriter` y `logging.logWriter`. **Bucket de estado:** `storage.objectAdmin`. **Secret** `wp-cicd-tf-db-password`: `secretAccessor` |
| `wp-cicd-app` | Triggers `app-pr` y `app-deploy` | `run.developer`, `logging.logWriter` y `compute.viewer` (para leer la IP del LB). **AR** `wp-cicd`: `artifactregistry.writer`. `iam.serviceAccountUser` **condicionado** a `wp-cicd-run` |
| `wp-cicd-run` | Runtime de Cloud Run (WordPress) | `cloudsql.client`, `logging.logWriter`, `monitoring.metricWriter` y `artifactregistry.reader`. **Secret** `wp-cicd-db-password`: `secretAccessor` |

Separación de privilegios:
- El pipeline de la app **no puede** cambiar la infraestructura, el IAM ni los secretos. Solo puede publicar imágenes y crear revisiones de un servicio que ya existe.
- El SA de Terraform tiene permisos amplios (incluido `projectIamAdmin`), porque gestiona el IAM del stack. Por eso **cada apply requiere aprobación humana**.
- Los SAs del CI/CD se crean en `bootstrap/`, fuera del alcance de `infra`. Así un apply no puede quitarse sus propios permisos.

## Aprobaciones y acceso humano

| Acción | Requiere |
|---|---|
| Aplicar o destruir infra | Merge en `main` **y** aprobación en Cloud Build (`roles/cloudbuild.builds.approver`, hoy `egonzalez@sequentia.co`) |
| Destruir | Además, la substitution `_CONFIRM=destroy` |
| Desplegar la app | Merge en `main` de `demo-wp` |

Recomendado: activar en GitHub la **protección de rama** de `main` en los dos repos, con PR obligatorio, el check de Cloud Build en verde y al menos una revisión.

## Organization policies que afectan al stack

| Política | Efecto | Cómo lo resuelve el stack |
|---|---|---|
| `iam.allowedPolicyMemberDomains` | No se puede dar IAM a cuentas fuera de la organización (`@gmail.com`) ni a `allUsers` | Cloud Run usa `invoker_iam_disabled = true` en lugar de `allUsers:run.invoker`. Los aprobadores son cuentas de la organización |

Los **canales de notificación** por email no son IAM, así que las alertas sí pueden ir a direcciones externas.

## Secretos

| Secreto | Dónde | Lo lee |
|---|---|---|
| `wp-cicd-tf-db-password` | Secret Manager (bootstrap) | `wp-cicd-tf` (como `TF_VAR_db_password`) |
| `wp-cicd-db-password` | Secret Manager (infra) | `wp-cicd-run` (como `WORDPRESS_DB_PASSWORD`) |
| Token OAuth de GitHub | Secret Manager (lo crea la consola al conectar GitHub) | Cloud Build service agent |

- No hay secretos en el repo. `env/prod.tfvars` no contiene la contraseña.
- ⚠️ La contraseña queda en **texto plano en el estado de Terraform**, tanto en el bucket GCS como en el `terraform.tfstate` local de bootstrap. El acceso al bucket debe limitarse a `wp-cicd-tf` y a los administradores.
- Para rotar la contraseña:
  1. Añade una versión nueva a `wp-cicd-tf-db-password`, o cambia `random_password` en bootstrap con `terraform apply -replace=random_password.db`.
  2. Lanza un `infra-apply` (por ejemplo con un commit vacío en `infra/`). Ese apply actualiza el usuario de MySQL y el secret de runtime.
  3. Cloud Run lee `latest` cuando arranca una instancia. Para forzar el cambio, despliega una revisión nueva.

## Red

| Control | Detalle |
|---|---|
| Ingress de Cloud Run | `INTERNAL_LOAD_BALANCER`: la URL `*.run.app` no es accesible directamente |
| Cloud SQL | Solo IP privada (PSA), sin IP pública |
| Valkey | Solo endpoint PSC en la subred `private` |
| Firewall de egress | 3306 y 6379 permitidos **solo** desde el tag `wp-cicd-run`, y denegados al resto de la VPC (prioridad 900 frente a 1000) |
| Salida a internet | `PRIVATE_RANGES_ONLY`: Cloud Run sale directamente, no por NAT. Con `ALL_TRAFFIC` todo pasaría por Cloud NAT con IPs del NAT |

## Cadena de suministro

- Imágenes desplegadas **por digest** (`@sha256`), con la etiqueta OCI `org.opencontainers.image.revision=<commit>`.
- Base `wordpress:php8.3-apache` de Docker Hub (imagen oficial). El plugin Redis Object Cache se descarga de `downloads.wordpress.org` con la versión fijada (`3.0.0`).
- `trivy config` analiza la IaC en cada PR, aunque de momento no bloquea.
- `demo-wp` es un repo **público**. No contiene secretos, pero muestra el ID del proyecto y los nombres de los recursos.

## Limitaciones y mejoras recomendadas

| Riesgo | Mejora |
|---|---|
| **Solo HTTP.** Las credenciales de wp-admin viajan sin cifrar | Dominio + `google_compute_managed_ssl_certificate` + `target_https_proxy` (:443), con redirección de 80 a 443 |
| Valkey sin auth ni TLS | `authorization_mode = "IAM_AUTH"` / `transit_encryption_mode = "SERVER_AUTHENTICATION"`, con soporte en el plugin |
| Sin WAF | Cloud Armor en `wp-cicd-backend`: rate limit en `wp-login.php` y `xmlrpc.php`, y reglas OWASP preconfiguradas |
| `deletion_protection = false` en Cloud SQL | Activarlo una vez que el entorno sea estable |
| Contraseña en el estado de Terraform | Generarla y escribirla con `secret_data_wo` (atributos write-only) y gestionar el usuario fuera de Terraform |
| `xmlrpc.php` expuesto | Bloquearlo en el LB (Cloud Armor) o con un mu-plugin |
| Escaneo de imágenes | Activar Artifact Analysis (vulnerability scanning) en el repo `wp-cicd` |
