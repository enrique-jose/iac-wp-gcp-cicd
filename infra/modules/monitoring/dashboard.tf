# Dashboard "<project_name> · WordPress" with one collapsible group per category.
# Layout: mosaic of 48 columns. Each section declares its tile size; tiles are placed
# left-to-right and wrapped automatically, below the section's collapsible header.

locals {
  # ---- widget builders ------------------------------------------------------
  # Line chart from a Monitoring filter
  w_line = {
    for k, v in {
      # LB
      lb_requests = {
        title   = "Peticiones/s por clase de respuesta", filter = "metric.type=\"loadbalancing.googleapis.com/https/request_count\" AND ${local.f_lb}",
        aligner = "ALIGN_RATE", reducer = "REDUCE_SUM", group_by = ["metric.label.response_code_class"], label = "req/s", thresholds = []
      }
      lb_latency_p50 = {
        title   = "Latencia total LB p50 (ms)", filter = "metric.type=\"loadbalancing.googleapis.com/https/total_latencies\" AND ${local.f_lb}",
        aligner = "ALIGN_DELTA", reducer = "REDUCE_PERCENTILE_50", group_by = [], label = "ms", thresholds = []
      }
      lb_latency_p95 = {
        title   = "Latencia total LB p95 (ms)", filter = "metric.type=\"loadbalancing.googleapis.com/https/total_latencies\" AND ${local.f_lb}",
        aligner = "ALIGN_DELTA", reducer = "REDUCE_PERCENTILE_95", group_by = [], label = "ms", thresholds = [var.run_latency_p95_ms_threshold]
      }
      lb_backend_latency = {
        title   = "Latencia de backend p95 (ms)", filter = "metric.type=\"loadbalancing.googleapis.com/https/backend_latencies\" AND ${local.f_lb}",
        aligner = "ALIGN_DELTA", reducer = "REDUCE_PERCENTILE_95", group_by = [], label = "ms", thresholds = []
      }
      # Cloud Run
      run_requests = {
        title   = "Cloud Run peticiones/s por código", filter = "metric.type=\"run.googleapis.com/request_count\" AND ${local.f_run}",
        aligner = "ALIGN_RATE", reducer = "REDUCE_SUM", group_by = ["metric.label.response_code_class"], label = "req/s", thresholds = []
      }
      run_latency_p95 = {
        title   = "Cloud Run latencia p95 (ms)", filter = "metric.type=\"run.googleapis.com/request_latencies\" AND ${local.f_run}",
        aligner = "ALIGN_DELTA", reducer = "REDUCE_PERCENTILE_95", group_by = [], label = "ms", thresholds = [var.run_latency_p95_ms_threshold]
      }
      run_latency_p99 = {
        title   = "Cloud Run latencia p99 (ms)", filter = "metric.type=\"run.googleapis.com/request_latencies\" AND ${local.f_run}",
        aligner = "ALIGN_DELTA", reducer = "REDUCE_PERCENTILE_99", group_by = [], label = "ms", thresholds = []
      }
      run_instances = {
        title   = "Instancias (activas / ociosas)", filter = "metric.type=\"run.googleapis.com/container/instance_count\" AND ${local.f_run}",
        aligner = "ALIGN_MAX", reducer = "REDUCE_SUM", group_by = ["metric.label.state"], label = "instancias", thresholds = [var.run_max_instances]
      }
      run_cpu = {
        title   = "CPU de contenedores p95", filter = "metric.type=\"run.googleapis.com/container/cpu/utilizations\" AND ${local.f_run}",
        aligner = "ALIGN_DELTA", reducer = "REDUCE_PERCENTILE_95", group_by = [], label = "ratio", thresholds = []
      }
      run_memory = {
        title   = "Memoria de contenedores p95", filter = "metric.type=\"run.googleapis.com/container/memory/utilizations\" AND ${local.f_run}",
        aligner = "ALIGN_DELTA", reducer = "REDUCE_PERCENTILE_95", group_by = [], label = "ratio", thresholds = [var.run_memory_threshold]
      }
      run_startup = {
        title   = "Startup latency p95 (ms)", filter = "metric.type=\"run.googleapis.com/container/startup_latencies\" AND ${local.f_run}",
        aligner = "ALIGN_DELTA", reducer = "REDUCE_PERCENTILE_95", group_by = [], label = "ms", thresholds = []
      }
      run_concurrency = {
        title   = "Concurrencia máxima por instancia p95", filter = "metric.type=\"run.googleapis.com/container/max_request_concurrencies\" AND ${local.f_run}",
        aligner = "ALIGN_DELTA", reducer = "REDUCE_PERCENTILE_95", group_by = [], label = "req", thresholds = []
      }
      run_php_fatal = {
        title   = "PHP Fatal/Parse errors (log metric)", filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.php_fatal_errors.name}\" AND resource.type=\"cloud_run_revision\"",
        aligner = "ALIGN_DELTA", reducer = "REDUCE_SUM", group_by = [], label = "errores", thresholds = []
      }
      # Cloud SQL
      sql_up = {
        title   = "Cloud SQL disponible (up)", filter = "metric.type=\"cloudsql.googleapis.com/database/up\" AND ${local.f_sql}",
        aligner = "ALIGN_MIN", reducer = "REDUCE_MIN", group_by = [], label = "up", thresholds = []
      }
      sql_cpu = {
        title   = "CPU", filter = "metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\" AND ${local.f_sql}",
        aligner = "ALIGN_MEAN", reducer = "REDUCE_MAX", group_by = [], label = "ratio", thresholds = [var.db_cpu_threshold]
      }
      sql_memory = {
        title   = "Memoria", filter = "metric.type=\"cloudsql.googleapis.com/database/memory/utilization\" AND ${local.f_sql}",
        aligner = "ALIGN_MEAN", reducer = "REDUCE_MAX", group_by = [], label = "ratio", thresholds = [var.db_memory_threshold]
      }
      sql_disk = {
        title   = "Disco (utilización)", filter = "metric.type=\"cloudsql.googleapis.com/database/disk/utilization\" AND ${local.f_sql}",
        aligner = "ALIGN_MAX", reducer = "REDUCE_MAX", group_by = [], label = "ratio", thresholds = [var.db_disk_threshold]
      }
      sql_disk_bytes = {
        title   = "Disco usado (bytes)", filter = "metric.type=\"cloudsql.googleapis.com/database/disk/bytes_used\" AND ${local.f_sql}",
        aligner = "ALIGN_MAX", reducer = "REDUCE_MAX", group_by = [], label = "bytes", thresholds = []
      }
      sql_connections = {
        title   = "Conexiones", filter = "metric.type=\"cloudsql.googleapis.com/database/network/connections\" AND ${local.f_sql}",
        aligner = "ALIGN_MAX", reducer = "REDUCE_MAX", group_by = [], label = "conexiones", thresholds = [floor(var.db_max_connections * var.db_connections_ratio)]
      }
      sql_queries = {
        title   = "Queries/s", filter = "metric.type=\"cloudsql.googleapis.com/database/mysql/queries\" AND ${local.f_sql}",
        aligner = "ALIGN_RATE", reducer = "REDUCE_SUM", group_by = [], label = "q/s", thresholds = []
      }
      sql_questions = {
        title   = "Questions/s (sentencias de clientes)", filter = "metric.type=\"cloudsql.googleapis.com/database/mysql/questions\" AND ${local.f_sql}",
        aligner = "ALIGN_RATE", reducer = "REDUCE_SUM", group_by = [], label = "q/s", thresholds = []
      }
      sql_read_ops = {
        title   = "Disk read ops/s", filter = "metric.type=\"cloudsql.googleapis.com/database/disk/read_ops_count\" AND ${local.f_sql}",
        aligner = "ALIGN_RATE", reducer = "REDUCE_SUM", group_by = [], label = "ops/s", thresholds = []
      }
      sql_write_ops = {
        title   = "Disk write ops/s", filter = "metric.type=\"cloudsql.googleapis.com/database/disk/write_ops_count\" AND ${local.f_sql}",
        aligner = "ALIGN_RATE", reducer = "REDUCE_SUM", group_by = [], label = "ops/s", thresholds = []
      }
      sql_rx = {
        title   = "MySQL bytes recibidos/s", filter = "metric.type=\"cloudsql.googleapis.com/database/mysql/received_bytes_count\" AND ${local.f_sql}",
        aligner = "ALIGN_RATE", reducer = "REDUCE_SUM", group_by = [], label = "B/s", thresholds = []
      }
      sql_tx = {
        title   = "MySQL bytes enviados/s", filter = "metric.type=\"cloudsql.googleapis.com/database/mysql/sent_bytes_count\" AND ${local.f_sql}",
        aligner = "ALIGN_RATE", reducer = "REDUCE_SUM", group_by = [], label = "B/s", thresholds = []
      }
      # Valkey
      vk_cpu = {
        title   = "Valkey CPU (máx)", filter = "metric.type=\"memorystore.googleapis.com/instance/cpu/maximum_utilization\" AND ${local.f_valkey}",
        aligner = "ALIGN_MAX", reducer = "REDUCE_MAX", group_by = [], label = "ratio", thresholds = []
      }
      vk_memory = {
        title   = "Valkey memoria (máx)", filter = "metric.type=\"memorystore.googleapis.com/instance/memory/maximum_utilization\" AND ${local.f_valkey}",
        aligner = "ALIGN_MAX", reducer = "REDUCE_MAX", group_by = [], label = "ratio", thresholds = [var.valkey_memory_threshold]
      }
      vk_clients = {
        title   = "Valkey clientes conectados", filter = "metric.type=\"memorystore.googleapis.com/instance/clients/total_connected_clients\" AND ${local.f_valkey}",
        aligner = "ALIGN_MAX", reducer = "REDUCE_SUM", group_by = [], label = "clientes", thresholds = []
      }
      vk_keys = {
        title   = "Valkey claves totales", filter = "metric.type=\"memorystore.googleapis.com/instance/keyspace/total_keys\" AND ${local.f_valkey}",
        aligner = "ALIGN_MAX", reducer = "REDUCE_SUM", group_by = [], label = "claves", thresholds = []
      }
      vk_evicted = {
        title   = "Valkey claves expulsadas/s", filter = "metric.type=\"memorystore.googleapis.com/instance/stats/total_evicted_keys_count\" AND ${local.f_valkey}",
        aligner = "ALIGN_RATE", reducer = "REDUCE_SUM", group_by = [], label = "claves/s", thresholds = []
      }
      vk_expired = {
        title   = "Valkey claves expiradas/s", filter = "metric.type=\"memorystore.googleapis.com/instance/stats/total_expired_keys_count\" AND ${local.f_valkey}",
        aligner = "ALIGN_RATE", reducer = "REDUCE_SUM", group_by = [], label = "claves/s", thresholds = []
      }
      } : k => {
      title = v.title
      xyChart = {
        chartOptions = { mode = "COLOR" }
        dataSets = [{
          plotType   = "LINE"
          targetAxis = "Y1"
          timeSeriesQuery = {
            timeSeriesFilter = {
              filter = v.filter
              aggregation = {
                alignmentPeriod    = "60s"
                perSeriesAligner   = v.aligner
                crossSeriesReducer = v.reducer
                groupByFields      = v.group_by
              }
            }
          }
        }]
        thresholds = [for t in v.thresholds : { value = t, targetAxis = "Y1" }]
        yAxis      = { label = v.label, scale = "LINEAR" }
      }
    }
  }

  # Line charts from PromQL (ratios)
  w_promql = {
    lb_5xx_ratio = {
      title = "Ratio 5xx del LB"
      xyChart = {
        dataSets = [{
          plotType        = "LINE"
          targetAxis      = "Y1"
          timeSeriesQuery = { prometheusQuery = "sum(rate(loadbalancing_googleapis_com:https_request_count{${local.pq_lb},response_code_class=\"500\"}[5m])) / sum(rate(loadbalancing_googleapis_com:https_request_count{${local.pq_lb}}[5m]))" }
        }]
        thresholds = [{ value = var.lb_5xx_ratio_threshold, targetAxis = "Y1" }]
        yAxis      = { label = "ratio", scale = "LINEAR" }
      }
    }
    vk_hit_ratio = {
      title = "Valkey hit ratio"
      xyChart = {
        dataSets = [{
          plotType        = "LINE"
          targetAxis      = "Y1"
          timeSeriesQuery = { prometheusQuery = "sum(rate(memorystore_googleapis_com:instance_stats_total_keyspace_hits_count{${local.pq_valkey}}[5m])) / (sum(rate(memorystore_googleapis_com:instance_stats_total_keyspace_hits_count{${local.pq_valkey}}[5m])) + sum(rate(memorystore_googleapis_com:instance_stats_total_keyspace_misses_count{${local.pq_valkey}}[5m])))" }
        }]
        thresholds = [{ value = var.valkey_hit_ratio_threshold, targetAxis = "Y1" }]
        yAxis      = { label = "ratio", scale = "LINEAR" }
      }
    }
  }

  # Scorecards for the summary row
  w_score = {
    for k, v in {
      uptime = {
        title   = "Uptime (fracción OK)"
        filter  = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND metric.labels.check_id=\"${google_monitoring_uptime_check_config.lb.uptime_check_id}\""
        aligner = "ALIGN_FRACTION_TRUE", reducer = "REDUCE_MEAN", threshold = 0.99, direction = "BELOW"
      }
      rps = {
        title   = "Peticiones/s (LB)", filter = "metric.type=\"loadbalancing.googleapis.com/https/request_count\" AND ${local.f_lb}",
        aligner = "ALIGN_RATE", reducer = "REDUCE_SUM", threshold = null, direction = null
      }
      p95 = {
        title   = "Latencia p95 Run (ms)", filter = "metric.type=\"run.googleapis.com/request_latencies\" AND ${local.f_run}",
        aligner = "ALIGN_DELTA", reducer = "REDUCE_PERCENTILE_95", threshold = var.run_latency_p95_ms_threshold, direction = "ABOVE"
      }
      instances = {
        title   = "Instancias Run", filter = "metric.type=\"run.googleapis.com/container/instance_count\" AND ${local.f_run}",
        aligner = "ALIGN_MAX", reducer = "REDUCE_SUM", threshold = var.run_max_instances, direction = "ABOVE"
      }
      db_conn = {
        title   = "Conexiones DB", filter = "metric.type=\"cloudsql.googleapis.com/database/network/connections\" AND ${local.f_sql}",
        aligner = "ALIGN_MAX", reducer = "REDUCE_MAX", threshold = floor(var.db_max_connections * var.db_connections_ratio), direction = "ABOVE"
      }
      db_cpu = {
        title   = "CPU DB", filter = "metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\" AND ${local.f_sql}",
        aligner = "ALIGN_MEAN", reducer = "REDUCE_MAX", threshold = var.db_cpu_threshold, direction = "ABOVE"
      }
      } : k => {
      title = v.title
      scorecard = merge(
        {
          timeSeriesQuery = {
            timeSeriesFilter = {
              filter = v.filter
              aggregation = {
                alignmentPeriod    = "300s"
                perSeriesAligner   = v.aligner
                crossSeriesReducer = v.reducer
              }
            }
          }
          sparkChartView = { sparkChartType = "SPARK_LINE" }
        },
        v.threshold == null ? {} : {
          thresholds = [{ value = v.threshold, color = "RED", direction = v.direction }]
        }
      )
    }
  }

  w_other = {
    incidents = {
      title        = "Incidentes abiertos"
      incidentList = {}
    }
    run_logs = {
      title = "Logs de error de Cloud Run"
      logsPanel = {
        filter        = "${local.f_run} AND severity>=ERROR"
        resourceNames = ["projects/${var.project_id}"]
      }
    }
    sql_logs = {
      title = "Logs de error de Cloud SQL"
      logsPanel = {
        filter        = "${local.f_sql} AND severity>=WARNING"
        resourceNames = ["projects/${var.project_id}"]
      }
    }
  }

  w = merge(local.w_line, local.w_promql, local.w_score, local.w_other)

  # ---- sections -------------------------------------------------------------
  sections = concat(
    [
      { title = "Resumen", tile_w = 8, tile_h = 8, widgets = ["uptime", "rps", "p95", "instances", "db_conn", "db_cpu"] },
      { title = "Incidentes", tile_w = 48, tile_h = 10, widgets = ["incidents"] },
      { title = "Backend · Load Balancer", tile_w = 24, tile_h = 14, widgets = ["lb_requests", "lb_5xx_ratio", "lb_latency_p50", "lb_latency_p95", "lb_backend_latency"] },
      { title = "Backend · Cloud Run", tile_w = 16, tile_h = 14, widgets = ["run_requests", "run_latency_p95", "run_latency_p99", "run_instances", "run_cpu", "run_memory", "run_startup", "run_concurrency", "run_php_fatal"] },
      { title = "Backend · Logs", tile_w = 48, tile_h = 16, widgets = ["run_logs"] },
      { title = "Bases de datos · Cloud SQL", tile_w = 16, tile_h = 14, widgets = ["sql_up", "sql_cpu", "sql_memory", "sql_disk", "sql_disk_bytes", "sql_connections", "sql_queries", "sql_questions", "sql_read_ops", "sql_write_ops", "sql_rx", "sql_tx"] },
      { title = "Bases de datos · Cloud SQL logs", tile_w = 48, tile_h = 14, widgets = ["sql_logs"] },
    ],
    var.enable_cache ? [
      { title = "Bases de datos · Valkey (object cache)", tile_w = 16, tile_h = 14, widgets = ["vk_hit_ratio", "vk_memory", "vk_cpu", "vk_clients", "vk_keys", "vk_evicted", "vk_expired"] },
    ] : []
  )

  section_heights = [
    for s in local.sections : s.tile_h * ceil(length(s.widgets) / floor(48 / s.tile_w))
  ]
  section_offsets = [
    for i, s in local.sections : sum(concat([0], slice(local.section_heights, 0, i)))
  ]

  tiles = flatten([
    for i, s in local.sections : concat(
      [{
        xPos   = 0
        yPos   = local.section_offsets[i]
        width  = 48
        height = local.section_heights[i]
        widget = { title = s.title, collapsibleGroup = { collapsed = false } }
      }],
      [
        for j, name in s.widgets : {
          xPos   = (j % floor(48 / s.tile_w)) * s.tile_w
          yPos   = local.section_offsets[i] + floor(j / floor(48 / s.tile_w)) * s.tile_h
          width  = s.tile_w
          height = s.tile_h
          widget = local.w[name]
        }
      ]
    )
  ])
}

resource "google_monitoring_dashboard" "main" {
  dashboard_json = jsonencode({
    displayName = "${var.project_name} · WordPress"
    labels      = { wordpress = "", (var.project_name) = "" }
    mosaicLayout = {
      columns = 48
      tiles   = local.tiles
    }
  })
}
