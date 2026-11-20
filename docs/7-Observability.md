# 7. Observability

Todo lo que se describe aquí lo crea `infra/modules/monitoring/`.

## Dashboard

**`wp-cicd · WordPress`**: la URL sale con `terraform output dashboard_url`, o en *Monitoring → Dashboards*.

Se organiza en grupos plegables:

| Grupo | Widgets |
|---|---|
| **Resumen** | Scorecards: uptime (fracción OK), peticiones/s del LB, latencia p95 de Run, instancias de Run, conexiones de la BD y CPU de la BD |
| **Incidentes** | Incidentes abiertos del proyecto |
| **Backend · Load Balancer** | Peticiones/s por clase de respuesta, ratio 5xx (PromQL), latencia total p50/p95 y latencia de backend p95 |
| **Backend · Cloud Run** | Peticiones/s por código, latencia p95/p99, instancias (activas y ociosas), CPU p95, memoria p95, startup latency, concurrencia máxima y PHP fatal errors |
| **Backend · Logs** | Logs de Cloud Run con severidad ERROR o superior |
| **Bases de datos · Cloud SQL** | up, CPU, memoria, disco (% y bytes), conexiones, queries/s, questions/s, IOPS de lectura y escritura, y bytes enviados y recibidos |
| **Bases de datos · Cloud SQL logs** | Logs de Cloud SQL con severidad WARNING o superior |
| **Bases de datos · Valkey** | Hit ratio (PromQL), memoria, CPU, clientes conectados, claves totales y claves expulsadas y expiradas por segundo |

Las líneas rojas de los gráficos son los mismos umbrales que usan las alertas.

## Señales base

| Señal | Recurso | Detalle |
|---|---|---|
| Uptime check | `wp-cicd-lb-http` | `GET http://<IP LB>/wp-login.php` cada 60 s desde Virginia, Oregón y Sudamérica. Acepta 2xx y 3xx |
| Métrica de logs | `wp-cicd-php-fatal-errors` | Cuenta las líneas `PHP (Fatal\|Parse) error` del servicio de Cloud Run |
| Logs del LB | `wp-cicd-backend` | `log_config.sample_rate = 1.0`, es decir, el 100 % de las peticiones |
| Logs de NAT | `wp-cicd-nat` | Solo errores |

## Alertas

Todas las alertas:
- notifican por email a `alert_emails` (hoy `enriquejose@gmail.com`);
- se cierran solas cuando la condición deja de cumplirse 30 min (`auto_close`);
- llevan un **runbook** en su documentación, con comandos `gcloud` y el enlace al dashboard;
- tienen las etiquetas `category` (`backend` | `database`), `component` (`lb` | `cloudrun` | `cicd` | `cloudsql` | `valkey`) y `severity` (`critical` | `warning`).

### Backend

| Alerta | Condición | Severidad | Variable de umbral |
|---|---|---|---|
| `[Backend] Sitio caído (uptime check)` | El uptime check falla en 2 o más regiones durante 2 min | critical | — |
| `[Backend] Ratio 5xx del Load Balancer alto` | 5xx / total > 5 % durante 5 min (PromQL) | critical | `lb_5xx_ratio_threshold` |
| `[Backend] Latencia p95 de Cloud Run alta` | p95 > 2000 ms durante 10 min | warning | `run_latency_p95_ms_threshold` (`alert_run_latency_p95_ms`) |
| `[Backend] Cloud Run en el máximo de instancias` | instancias >= `run_max_instances` durante 10 min | warning | `run_max_instances` |
| `[Backend] Memoria de Cloud Run alta` | p99 > 85 % durante 5 min | warning | `run_memory_threshold` |
| `[Backend] Errores fatales de PHP` | > 5 en 5 min | warning | `php_fatal_errors_threshold` |
| `[Backend] Build/deploy de Cloud Build fallido` | Un log `^ERROR` en cualquier build del proyecto | warning | — |

### Bases de datos

| Alerta | Condición | Severidad | Variable de umbral |
|---|---|---|---|
| `[DB] Cloud SQL caída` | `database/up` < 1 durante 3 min | critical | — |
| `[DB] CPU de Cloud SQL alta` | > 80 % durante 10 min | warning | `db_cpu_threshold` |
| `[DB] Memoria de Cloud SQL alta` | > 90 % durante 10 min | warning | `db_memory_threshold` |
| `[DB] Disco de Cloud SQL alto` | > 85 % durante 5 min | warning | `db_disk_threshold` |
| `[DB] Conexiones de Cloud SQL cerca del límite` | > 80 % de `max_connections` durante 5 min | critical | `db_connections_ratio` |
| `[DB] Fallo de backup de Cloud SQL` | Un log de error con "backup" en la instancia | critical | — |
| `[DB] Memoria de Valkey alta` | > 85 % durante 10 min | warning | `valkey_memory_threshold` |
| `[DB] Hit ratio de Valkey bajo` | < 70 % durante 30 min, con más de 1 lookup/s | warning | `valkey_hit_ratio_threshold` |

Las alertas de Valkey solo existen si `enable_cache = true`.

### Ajustar umbrales o destinatarios

- **Destinatarios:** `alert_emails` en `infra/env/prod.tfvars`.
- **Latencia:** `alert_run_latency_p95_ms`.
- **Resto de umbrales:** son variables del módulo `monitoring` (`infra/modules/monitoring/variables.tf`). Para cambiarlos por entorno, pásalos desde `infra/main.tf`.

Cualquier cambio sigue el flujo normal: PR → plan → merge → aprobar el apply.

### Silenciar durante un mantenimiento

```bash
gcloud monitoring policies list --filter='displayName:"[DB]"' --format='value(name,displayName)'
gcloud monitoring snoozes create --display-name="mantenimiento BD" \
  --criteria-policies=<POLICY_NAME> --start-time=now --end-time=+2h
```

## Runbooks rápidos

| Síntoma | Dónde mirar | Acción típica |
|---|---|---|
| Sitio caído | Dashboard → Resumen e Incidentes. `gcloud run services describe wp-cicd-service --region us-east1` | Si coincide con un deploy, haz rollback ([CI/CD](3-Ci-cd.md#rollback-manual)). Si no, revisa `[DB] Cloud SQL caída` |
| 5xx | Backend · Logs. Logs del LB filtrando `httpRequest.status>=500` | 502/503 sin logs de Run: saturación o arranque. 500 con `PHP Fatal`: código. `Error establishing a database connection`: BD |
| Lento | Latencia p95, CPU de Run, hit ratio de Valkey y queries/s | Comprueba que Redis esté *Connected*. Considera subir `db_tier` o `run_max_instances` |
| Conexiones de la BD altas | Conexiones frente a instancias de Run | Baja `run_max_instances` o sube `db_max_connections` (y la memoria del tier) |
| Disco de la BD alto | Disco usado (bytes) | Revisa tablas grandes (`wp_options` con autoload, `wp_postmeta`) y binlogs. El autoresize no tiene vuelta atrás |
| Valkey lleno o hit ratio bajo | Memoria, claves expulsadas e hit ratio | Sube `cache_node_type`, o haz flush si hubo un cambio masivo de contenido |

Consultas de logs útiles:

```bash
# Errores de WordPress
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="wp-cicd-service" AND severity>=ERROR' --limit 50
# 5xx en el LB
gcloud logging read 'resource.type="http_load_balancer" AND httpRequest.status>=500' --limit 50
# Builds fallidos
gcloud logging read 'resource.type="build" AND textPayload=~"^ERROR"' --limit 20
```

## Limitaciones

- La alerta de **builds fallidos** salta con cualquier build del proyecto que registre `ERROR`, incluidos los PRs con un plan fallido. Si genera ruido, añade al filtro `resource.labels.build_trigger_id`.
- La detección de **fallo de backup** se basa en logs de error que mencionan "backup". Complétala revisando de vez en cuando `gcloud sql backups list`.
- El uptime check prueba la **IP** del LB. Cuando haya dominio y HTTPS, apúntalo al dominio por el puerto 443.
