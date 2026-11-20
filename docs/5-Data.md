# 5. Data

## Almacenes de datos

| Almacén | Qué guarda | Persistente | Backup |
|---|---|---|---|
| Cloud SQL MySQL | Contenido de WordPress: posts, usuarios, opciones, etc. | Sí | Automático diario, 7 retenidos, más binlog |
| Memorystore Valkey | Object cache (opciones, queries y transients) | **No**, se puede perder sin impacto | No aplica |
| Sistema de archivos de Cloud Run | `wp-content/uploads` y plugins instalados desde wp-admin | **No**, es efímero | — |
| GCS `cool-academy-489503-f3-tfstate` | Estado de Terraform de `infra/` y planes de PR | Sí, con versionado | Versiones de objeto (20) |
| Artifact Registry `wp-cicd` | Imágenes de WordPress | Sí | Las imágenes se reconstruyen desde git |
| Secret Manager | Contraseña de la BD | Sí | Versiones del secret |

## Cloud SQL MySQL

| Parámetro | Valor |
|---|---|
| Instancia | `wp-cicd-db-<sufijo hex aleatorio>` |
| Versión / edición | `MYSQL_8_0` / `ENTERPRISE` |
| Tier | `db-f1-micro` (CPU compartida) |
| Disponibilidad | `ZONAL`, sin alta disponibilidad |
| Disco | `PD_SSD`, 20 GB, con autoresize |
| Red | **solo IP privada** (`ipv4_enabled = false`), por PSA en `10.0.32.0/20` |
| Flags | `max_connections = 100` |
| Base de datos / usuario | `wordpressdb` / `wpuser@%` |
| `deletion_protection` | `false` |

El nombre lleva un sufijo aleatorio porque Cloud SQL no deja reutilizar el nombre de una instancia borrada durante unos 7 días.

### Conexiones

Cada instancia de Cloud Run abre sus propias conexiones PHP/MySQL. Con `run_max_instances = 3`, el consumo de conexiones queda muy por debajo de 100. Si subes el máximo de instancias, revisa también la alerta *[DB] Conexiones cerca del límite* y `db_max_connections` ([Observability](7-Observability.md)).

### Backups y restauración

- **Automáticos:** diarios a las 03:00 UTC, se retienen 7 y tienen binary log activado, lo que permite point-in-time recovery dentro de la ventana de retención.
- **Manual**, antes de cambios grandes:
  ```bash
  INSTANCE=$(cd infra && terraform output -raw db_instance_name)   # o gcloud sql instances list
  gcloud sql backups create --instance $INSTANCE --description "pre-upgrade"
  gcloud sql backups list --instance $INSTANCE
  ```
- **Restaurar** sobre la misma instancia (sobrescribe los datos):
  ```bash
  gcloud sql backups restore <BACKUP_ID> --restore-instance $INSTANCE
  ```
- **Point-in-time**, clonando a una instancia nueva:
  ```bash
  gcloud sql instances clone $INSTANCE ${INSTANCE}-pitr --point-in-time '2026-11-20T10:00:00Z'
  ```
- **Exportar a GCS** (dump SQL):
  ```bash
  gcloud sql export sql $INSTANCE gs://<bucket>/wp-$(date +%F).sql.gz --database wordpressdb
  ```

> ⚠️ Con `deletion_protection = false`, un `terraform destroy` o un cambio que **recree** la instancia borra los datos. Los backups automáticos **se borran junto con la instancia**. Antes de un destroy, exporta a GCS.

## Memorystore for Valkey

| Parámetro | Valor |
|---|---|
| Instancia | `wp-cicd-valkey` |
| Motor | `VALKEY_8_0`, `CLUSTER_DISABLED`, 1 shard |
| Nodo | `SHARED_CORE_NANO`, 0 réplicas |
| Política de memoria | `maxmemory-policy = allkeys-lru` |
| Persistencia | `DISABLED` |
| Auth / TLS | `AUTH_DISABLED` / `TRANSIT_ENCRYPTION_DISABLED` (ver [Security](6-Security.md)) |
| Acceso | Endpoint PSC en la subred `private` (`10.0.10.0/24`), puerto 6379 |

Valkey es **solo cache**. Si se pierde o se vacía, WordPress sigue funcionando: hay más carga en MySQL hasta que el cache se vuelve a llenar. Para vaciarlo, entra en wp-admin → Settings → Redis → *Flush Cache*.

Las claves usan el prefijo `wp-cicd:` (`WP_REDIS_PREFIX`).

## Archivos subidos (`wp-content/uploads`)

Hoy se guardan en el sistema de archivos del contenedor y **se pierden** en cada deploy o reinicio. Además no se comparten entre instancias. Para producción hay dos opciones:
1. **Volumen GCS en Cloud Run:** un bucket montado en `/var/www/html/wp-content/uploads` con `volume_mounts` y `gcs` en `modules/cloudrun`.
2. **Plugin de offload**, por ejemplo WP Offload Media o WP-Stateless, que sube los medios a GCS y sirve las URLs desde allí.

## Estado de Terraform

| Stack | Ubicación | Bloqueo |
|---|---|---|
| `infra` | `gs://cool-academy-489503-f3-tfstate/wordpress/default.tfstate` | Nativo de GCS |
| `bootstrap` | `bootstrap/terraform.tfstate` (**local**, fuera de git) | — |

- Para recuperar una versión anterior del estado de infra: `gcloud storage ls -a gs://cool-academy-489503-f3-tfstate/wordpress/`.
- El estado contiene la contraseña de la BD en texto plano, así que el acceso al bucket debe estar restringido ([Security](6-Security.md#secretos)).
- Haz una copia de `bootstrap/terraform.tfstate`. Si se pierde, hay que importar cada recurso con `terraform import`.
