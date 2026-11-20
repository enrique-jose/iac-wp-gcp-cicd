locals {
  url_map_name   = "${var.project_name}-urlmap"
  db_database_id = "${var.project_id}:${var.db_instance_name}"

  # Base filters reused by alerts and dashboard widgets
  f_lb     = "resource.type=\"https_lb_rule\" AND resource.labels.url_map_name=\"${local.url_map_name}\""
  f_run    = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${var.cloud_run_service_name}\""
  f_sql    = "resource.type=\"cloudsql_database\" AND resource.labels.database_id=\"${local.db_database_id}\""
  f_valkey = "resource.type=\"memorystore.googleapis.com/Instance\" AND resource.labels.instance_id=\"${var.valkey_instance_id}\""

  # PromQL selectors (used for ratios)
  pq_lb     = "monitored_resource=\"https_lb_rule\",url_map_name=\"${local.url_map_name}\""
  pq_valkey = "monitored_resource=\"memorystore.googleapis.com/Instance\",instance_id=\"${var.valkey_instance_id}\""

  channels = [for c in google_monitoring_notification_channel.email : c.id]

  dashboard_link = "https://console.cloud.google.com/monitoring/dashboards/builder/${element(split("/", google_monitoring_dashboard.main.id), 3)}?project=${var.project_id}"
}

# ---------------------------------------------------------------------------
# Notification channels
# ---------------------------------------------------------------------------
resource "google_monitoring_notification_channel" "email" {
  for_each = toset(var.alert_emails)

  display_name = "${var.project_name} - ${each.value}"
  type         = "email"
  labels = {
    email_address = each.value
  }
}

# ---------------------------------------------------------------------------
# Uptime check on the load balancer
# ---------------------------------------------------------------------------
resource "google_monitoring_uptime_check_config" "lb" {
  display_name = "${var.project_name}-lb-http"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = var.uptime_path
    port         = 80
    use_ssl      = false
    validate_ssl = false
    accepted_response_status_codes {
      status_class = "STATUS_CLASS_2XX"
    }
    accepted_response_status_codes {
      status_class = "STATUS_CLASS_3XX"
    }
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.lb_ip
    }
  }

  selected_regions = ["USA_VIRGINIA", "USA_OREGON", "SOUTH_AMERICA"]
}

# ---------------------------------------------------------------------------
# Log-based metrics
# ---------------------------------------------------------------------------
resource "google_logging_metric" "php_fatal_errors" {
  name   = "${var.project_name}-php-fatal-errors"
  filter = "${local.f_run} AND textPayload=~\"PHP (Fatal|Parse) error\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

# ---------------------------------------------------------------------------
# Alert policies - BACKEND
# ---------------------------------------------------------------------------
resource "google_monitoring_alert_policy" "backend_uptime" {
  display_name          = "[Backend] Sitio caído (uptime check)"
  combiner              = "OR"
  notification_channels = local.channels
  severity              = "CRITICAL"
  user_labels           = { category = "backend", component = "lb", severity = "critical" }

  conditions {
    display_name = "Uptime check falla en 2+ regiones"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND metric.labels.check_id=\"${google_monitoring_uptime_check_config.lb.uptime_check_id}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "120s"
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.host"]
      }
      trigger { count = 1 }
    }
  }

  alert_strategy { auto_close = "1800s" }

  documentation {
    mime_type = "text/markdown"
    subject   = "[Backend][CRITICAL] WordPress no responde en http://${var.lb_ip}${var.uptime_path}"
    content   = <<-EOT
      El uptime check falla desde 2 o más regiones.

      **Revisar**
      1. Estado del servicio: `gcloud run services describe ${var.cloud_run_service_name} --region <region>`
      2. Logs de errores: `gcloud logging read '${local.f_run} AND severity>=ERROR' --limit 50`
      3. ¿Cloud SQL arriba? ver la alerta `[DB] Cloud SQL caída`.
      4. Último deploy de demo-wp: si coincide en el tiempo, hacer rollback con
         `gcloud run services update-traffic ${var.cloud_run_service_name} --to-revisions=<rev-anterior>=100`

      [Dashboard](${local.dashboard_link})
    EOT
  }
}

resource "google_monitoring_alert_policy" "backend_lb_5xx" {
  display_name          = "[Backend] Ratio 5xx del Load Balancer alto"
  combiner              = "OR"
  notification_channels = local.channels
  severity              = "CRITICAL"
  user_labels           = { category = "backend", component = "lb", severity = "critical" }

  conditions {
    display_name = "5xx / total > ${var.lb_5xx_ratio_threshold * 100}% durante 5 min"
    condition_prometheus_query_language {
      query               = <<-EOT
        (
          sum(rate(loadbalancing_googleapis_com:https_request_count{${local.pq_lb},response_code_class="500"}[5m]))
          /
          sum(rate(loadbalancing_googleapis_com:https_request_count{${local.pq_lb}}[5m]))
        ) > ${var.lb_5xx_ratio_threshold}
      EOT
      duration            = "300s"
      evaluation_interval = "60s"
    }
  }

  alert_strategy { auto_close = "1800s" }

  documentation {
    mime_type = "text/markdown"
    subject   = "[Backend][CRITICAL] Más del ${var.lb_5xx_ratio_threshold * 100}% de respuestas 5xx"
    content   = <<-EOT
      El Load Balancer está devolviendo errores 5xx.

      - 502/503 sin logs en Cloud Run → instancias saturadas o arrancando (ver instancias en el dashboard).
      - 500 con logs `PHP Fatal error` → error de código del último deploy de demo-wp: hacer rollback.
      - `Error establishing a database connection` → revisar Cloud SQL (conexiones / CPU).

      [Dashboard](${local.dashboard_link})
    EOT
  }
}

resource "google_monitoring_alert_policy" "backend_run_latency" {
  display_name          = "[Backend] Latencia p95 de Cloud Run alta"
  combiner              = "OR"
  notification_channels = local.channels
  severity              = "WARNING"
  user_labels           = { category = "backend", component = "cloudrun", severity = "warning" }

  conditions {
    display_name = "p95 > ${var.run_latency_p95_ms_threshold} ms durante 10 min"
    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/request_latencies\" AND ${local.f_run}"
      comparison      = "COMPARISON_GT"
      threshold_value = var.run_latency_p95_ms_threshold
      duration        = "600s"
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_PERCENTILE_95"
      }
      trigger { count = 1 }
    }
  }

  alert_strategy { auto_close = "1800s" }

  documentation {
    mime_type = "text/markdown"
    subject   = "[Backend][WARNING] Latencia p95 > ${var.run_latency_p95_ms_threshold} ms"
    content   = <<-EOT
      WordPress responde lento. Causas habituales: object cache (Valkey) desconectado,
      queries lentas en Cloud SQL, CPU de las instancias al 100% o cold starts.
      Revisar en el dashboard las secciones *Backend · Cloud Run* y *Bases de datos*.

      [Dashboard](${local.dashboard_link})
    EOT
  }
}

resource "google_monitoring_alert_policy" "backend_run_saturation" {
  display_name          = "[Backend] Cloud Run en el máximo de instancias"
  combiner              = "OR"
  notification_channels = local.channels
  severity              = "WARNING"
  user_labels           = { category = "backend", component = "cloudrun", severity = "warning" }

  conditions {
    display_name = "instancias >= ${var.run_max_instances} durante 10 min"
    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/container/instance_count\" AND ${local.f_run}"
      comparison      = "COMPARISON_GT"
      threshold_value = var.run_max_instances - 0.5
      duration        = "600s"
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MAX"
        cross_series_reducer = "REDUCE_SUM"
      }
      trigger { count = 1 }
    }
  }

  alert_strategy { auto_close = "1800s" }

  documentation {
    mime_type = "text/markdown"
    subject   = "[Backend][WARNING] Cloud Run lleva 10 min en ${var.run_max_instances} instancias"
    content   = <<-EOT
      El servicio no puede escalar más. Si la latencia o los 5xx también suben,
      aumentar `run_max_instances` en `infra/env/prod.tfvars` (y revisar `db_max_connections`:
      cada instancia abre conexiones a Cloud SQL).

      [Dashboard](${local.dashboard_link})
    EOT
  }
}

resource "google_monitoring_alert_policy" "backend_run_memory" {
  display_name          = "[Backend] Memoria de Cloud Run alta"
  combiner              = "OR"
  notification_channels = local.channels
  severity              = "WARNING"
  user_labels           = { category = "backend", component = "cloudrun", severity = "warning" }

  conditions {
    display_name = "p99 memoria > ${var.run_memory_threshold * 100}% durante 5 min"
    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/container/memory/utilizations\" AND ${local.f_run}"
      comparison      = "COMPARISON_GT"
      threshold_value = var.run_memory_threshold
      duration        = "300s"
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_PERCENTILE_99"
      }
      trigger { count = 1 }
    }
  }

  alert_strategy { auto_close = "1800s" }

  documentation {
    mime_type = "text/markdown"
    subject   = "[Backend][WARNING] Memoria de los contenedores > ${var.run_memory_threshold * 100}%"
    content   = "Riesgo de OOM (contenedor reiniciado). Revisar plugins nuevos o subir la memoria del contenedor en `modules/cloudrun`.\n\n[Dashboard](${local.dashboard_link})"
  }
}

resource "google_monitoring_alert_policy" "backend_php_fatal" {
  display_name          = "[Backend] Errores fatales de PHP"
  combiner              = "OR"
  notification_channels = local.channels
  severity              = "WARNING"
  user_labels           = { category = "backend", component = "cloudrun", severity = "warning" }

  conditions {
    display_name = "> ${var.php_fatal_errors_threshold} PHP Fatal/Parse errors en 5 min"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.php_fatal_errors.name}\" AND resource.type=\"cloud_run_revision\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.php_fatal_errors_threshold
      duration        = "0s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
      }
      trigger { count = 1 }
    }
  }

  alert_strategy { auto_close = "1800s" }

  documentation {
    mime_type = "text/markdown"
    subject   = "[Backend][WARNING] PHP Fatal errors en WordPress"
    content   = "Ver los errores: `gcloud logging read '${google_logging_metric.php_fatal_errors.filter}' --limit 20`.\nSuelen venir de un plugin/tema roto o de un deploy reciente de demo-wp.\n\n[Dashboard](${local.dashboard_link})"
  }
}

resource "google_monitoring_alert_policy" "backend_deploy_failed" {
  display_name          = "[Backend] Build/deploy de Cloud Build fallido"
  combiner              = "OR"
  notification_channels = local.channels
  severity              = "WARNING"
  user_labels           = { category = "backend", component = "cicd", severity = "warning" }

  conditions {
    display_name = "Un build de Cloud Build terminó con error"
    condition_matched_log {
      filter = "resource.type=\"build\" AND logName=\"projects/${var.project_id}/logs/cloudbuild\" AND textPayload=~\"^ERROR\""
      label_extractors = {
        build_id   = "EXTRACT(resource.labels.build_id)"
        trigger_id = "EXTRACT(resource.labels.build_trigger_id)"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
    notification_rate_limit { period = "300s" }
  }

  documentation {
    mime_type = "text/markdown"
    subject   = "[Backend][WARNING] Falló un build de Cloud Build"
    content   = "Ver el detalle: `gcloud builds describe $${log.extracted_label.build_id} --region <region>`.\nSi es `app-deploy`, el smoke test ya habrá devuelto el tráfico a la revisión anterior."
  }
}

# ---------------------------------------------------------------------------
# Alert policies - DATABASES (Cloud SQL + Valkey)
# ---------------------------------------------------------------------------
resource "google_monitoring_alert_policy" "db_sql_down" {
  display_name          = "[DB] Cloud SQL caída"
  combiner              = "OR"
  notification_channels = local.channels
  severity              = "CRITICAL"
  user_labels           = { category = "database", component = "cloudsql", severity = "critical" }

  conditions {
    display_name = "database/up < 1 durante 3 min"
    condition_threshold {
      filter          = "metric.type=\"cloudsql.googleapis.com/database/up\" AND ${local.f_sql}"
      comparison      = "COMPARISON_LT"
      threshold_value = 1
      duration        = "180s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MIN"
      }
      trigger { count = 1 }
    }
  }

  alert_strategy { auto_close = "1800s" }

  documentation {
    mime_type = "text/markdown"
    subject   = "[DB][CRITICAL] Cloud SQL ${var.db_instance_name} no está disponible"
    content   = "Revisar `gcloud sql instances describe ${var.db_instance_name}` y las operaciones recientes (`gcloud sql operations list --instance ${var.db_instance_name}`): mantenimiento, disco lleno o reinicio.\n\n[Dashboard](${local.dashboard_link})"
  }
}

resource "google_monitoring_alert_policy" "db_sql_cpu" {
  display_name          = "[DB] CPU de Cloud SQL alta"
  combiner              = "OR"
  notification_channels = local.channels
  severity              = "WARNING"
  user_labels           = { category = "database", component = "cloudsql", severity = "warning" }

  conditions {
    display_name = "CPU > ${var.db_cpu_threshold * 100}% durante 10 min"
    condition_threshold {
      filter          = "metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\" AND ${local.f_sql}"
      comparison      = "COMPARISON_GT"
      threshold_value = var.db_cpu_threshold
      duration        = "600s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
      trigger { count = 1 }
    }
  }

  alert_strategy { auto_close = "1800s" }

  documentation {
    mime_type = "text/markdown"
    subject   = "[DB][WARNING] CPU de Cloud SQL > ${var.db_cpu_threshold * 100}%"
    content   = "Comprobar queries/s en el dashboard y que el object cache (Valkey) esté conectado. Si es carga sostenida, subir `db_tier` (db-f1-micro tiene CPU compartida).\n\n[Dashboard](${local.dashboard_link})"
  }
}

resource "google_monitoring_alert_policy" "db_sql_memory" {
  display_name          = "[DB] Memoria de Cloud SQL alta"
  combiner              = "OR"
  notification_channels = local.channels
  severity              = "WARNING"
  user_labels           = { category = "database", component = "cloudsql", severity = "warning" }

  conditions {
    display_name = "Memoria > ${var.db_memory_threshold * 100}% durante 10 min"
    condition_threshold {
      filter          = "metric.type=\"cloudsql.googleapis.com/database/memory/utilization\" AND ${local.f_sql}"
      comparison      = "COMPARISON_GT"
      threshold_value = var.db_memory_threshold
      duration        = "600s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
      trigger { count = 1 }
    }
  }

  alert_strategy { auto_close = "1800s" }

  documentation {
    mime_type = "text/markdown"
    subject   = "[DB][WARNING] Memoria de Cloud SQL > ${var.db_memory_threshold * 100}%"
    content   = "Riesgo de OOM en MySQL. Revisar conexiones abiertas o subir `db_tier`.\n\n[Dashboard](${local.dashboard_link})"
  }
}

resource "google_monitoring_alert_policy" "db_sql_disk" {
  display_name          = "[DB] Disco de Cloud SQL alto"
  combiner              = "OR"
  notification_channels = local.channels
  severity              = "WARNING"
  user_labels           = { category = "database", component = "cloudsql", severity = "warning" }

  conditions {
    display_name = "Disco > ${var.db_disk_threshold * 100}%"
    condition_threshold {
      filter          = "metric.type=\"cloudsql.googleapis.com/database/disk/utilization\" AND ${local.f_sql}"
      comparison      = "COMPARISON_GT"
      threshold_value = var.db_disk_threshold
      duration        = "300s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MAX"
      }
      trigger { count = 1 }
    }
  }

  alert_strategy { auto_close = "1800s" }

  documentation {
    mime_type = "text/markdown"
    subject   = "[DB][WARNING] Disco de Cloud SQL > ${var.db_disk_threshold * 100}%"
    content   = "El disco tiene autoresize, pero crecer no tiene vuelta atrás. Revisar binlogs y tablas grandes (wp_options autoload, wp_postmeta, logs de plugins).\n\n[Dashboard](${local.dashboard_link})"
  }
}

resource "google_monitoring_alert_policy" "db_sql_connections" {
  display_name          = "[DB] Conexiones de Cloud SQL cerca del límite"
  combiner              = "OR"
  notification_channels = local.channels
  severity              = "CRITICAL"
  user_labels           = { category = "database", component = "cloudsql", severity = "critical" }

  conditions {
    display_name = "Conexiones > ${floor(var.db_max_connections * var.db_connections_ratio)} (${var.db_connections_ratio * 100}% de ${var.db_max_connections}) durante 5 min"
    condition_threshold {
      filter          = "metric.type=\"cloudsql.googleapis.com/database/network/connections\" AND ${local.f_sql}"
      comparison      = "COMPARISON_GT"
      threshold_value = floor(var.db_max_connections * var.db_connections_ratio)
      duration        = "300s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
      trigger { count = 1 }
    }
  }

  alert_strategy { auto_close = "1800s" }

  documentation {
    mime_type = "text/markdown"
    subject   = "[DB][CRITICAL] Conexiones a MySQL cerca de max_connections (${var.db_max_connections})"
    content   = "Si se alcanza el límite WordPress mostrará *Error establishing a database connection*. Ver el número de instancias de Cloud Run; subir `db_max_connections` o bajar `run_max_instances`.\n\n[Dashboard](${local.dashboard_link})"
  }
}

resource "google_monitoring_alert_policy" "db_sql_backup" {
  display_name          = "[DB] Fallo de backup de Cloud SQL"
  combiner              = "OR"
  notification_channels = local.channels
  severity              = "CRITICAL"
  user_labels           = { category = "database", component = "cloudsql", severity = "critical" }

  conditions {
    display_name = "Error en una operación de backup"
    condition_matched_log {
      filter = "${local.f_sql} AND severity>=ERROR AND (protoPayload.methodName=~\"[Bb]ackup\" OR textPayload=~\"[Bb]ackup\" OR jsonPayload.message=~\"[Bb]ackup\")"
    }
  }

  alert_strategy {
    auto_close = "1800s"
    notification_rate_limit { period = "3600s" }
  }

  documentation {
    mime_type = "text/markdown"
    subject   = "[DB][CRITICAL] Falló un backup de Cloud SQL ${var.db_instance_name}"
    content   = "Ver `gcloud sql backups list --instance ${var.db_instance_name}` y lanzar uno manual: `gcloud sql backups create --instance ${var.db_instance_name}`."
  }
}

resource "google_monitoring_alert_policy" "db_valkey_memory" {
  count = var.enable_cache ? 1 : 0

  display_name          = "[DB] Memoria de Valkey alta"
  combiner              = "OR"
  notification_channels = local.channels
  severity              = "WARNING"
  user_labels           = { category = "database", component = "valkey", severity = "warning" }

  conditions {
    display_name = "Memoria > ${var.valkey_memory_threshold * 100}% durante 10 min"
    condition_threshold {
      filter          = "metric.type=\"memorystore.googleapis.com/instance/memory/maximum_utilization\" AND ${local.f_valkey}"
      comparison      = "COMPARISON_GT"
      threshold_value = var.valkey_memory_threshold
      duration        = "600s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
      trigger { count = 1 }
    }
  }

  alert_strategy { auto_close = "1800s" }

  documentation {
    mime_type = "text/markdown"
    subject   = "[DB][WARNING] Memoria de Valkey > ${var.valkey_memory_threshold * 100}%"
    content   = "Con `allkeys-lru` Valkey empezará a expulsar claves (ver *evicted keys* en el dashboard). Si el hit ratio cae, subir `cache_node_type`.\n\n[Dashboard](${local.dashboard_link})"
  }
}

resource "google_monitoring_alert_policy" "db_valkey_hit_ratio" {
  count = var.enable_cache ? 1 : 0

  display_name          = "[DB] Hit ratio de Valkey bajo"
  combiner              = "OR"
  notification_channels = local.channels
  severity              = "WARNING"
  user_labels           = { category = "database", component = "valkey", severity = "warning" }

  conditions {
    display_name = "hits / (hits + misses) < ${var.valkey_hit_ratio_threshold * 100}% durante 30 min"
    condition_prometheus_query_language {
      # Only evaluated with meaningful traffic (> 1 lookup/s) to avoid noise on an idle site
      query               = <<-EOT
        (
          sum(rate(memorystore_googleapis_com:instance_stats_total_keyspace_hits_count{${local.pq_valkey}}[10m]))
          /
          (
            sum(rate(memorystore_googleapis_com:instance_stats_total_keyspace_hits_count{${local.pq_valkey}}[10m]))
            + sum(rate(memorystore_googleapis_com:instance_stats_total_keyspace_misses_count{${local.pq_valkey}}[10m]))
          )
        ) < ${var.valkey_hit_ratio_threshold}
        and
        (
          sum(rate(memorystore_googleapis_com:instance_stats_total_keyspace_hits_count{${local.pq_valkey}}[10m]))
          + sum(rate(memorystore_googleapis_com:instance_stats_total_keyspace_misses_count{${local.pq_valkey}}[10m]))
        ) > 1
      EOT
      duration            = "1800s"
      evaluation_interval = "60s"
    }
  }

  alert_strategy { auto_close = "1800s" }

  documentation {
    mime_type = "text/markdown"
    subject   = "[DB][WARNING] Hit ratio de Valkey < ${var.valkey_hit_ratio_threshold * 100}%"
    content   = "El object cache no está siendo efectivo: memoria llena (evictions), flush reciente o plugin Redis Object Cache desactivado (wp-admin → Settings → Redis).\n\n[Dashboard](${local.dashboard_link})"
  }
}
