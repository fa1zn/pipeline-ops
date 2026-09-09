resource "grafana_data_source" "prometheus" {
  type               = "prometheus"
  name               = "prometheus"
  url                = var.prometheus_url
  is_default         = true
  basic_auth_enabled = false
}

resource "grafana_folder" "pipeline" {
  title = "Pipeline"
}

locals {
  ds = { type = "prometheus", uid = grafana_data_source.prometheus.uid }

  # Panels are written out rather than pasted from a Grafana export, so a review
  # can see what changed. An exported dashboard diff is unreadable.
  stat_panels = [
    {
      title = "Since last successful run"
      expr  = "time() - pipeline_last_success_timestamp_seconds"
      unit  = "s"
      x     = 0
    },
    {
      title = "Data age (watermark lag)"
      expr  = "pipeline_watermark_lag_seconds"
      unit  = "s"
      x     = 6
    },
    {
      title = "Last run duration"
      expr  = "pipeline_run_duration_seconds"
      unit  = "s"
      x     = 12
    },
    {
      title = "Pushgateway reachable"
      expr  = "up{job=\"pushgateway\"}"
      unit  = "short"
      x     = 18
    },
  ]
}

resource "grafana_dashboard" "pipeline" {
  folder = grafana_folder.pipeline.uid

  config_json = jsonencode({
    title         = "Nightly pipeline"
    uid           = "${var.project}-nightly"
    timezone      = "browser"
    refresh       = "10s"
    time          = { from = "now-1h", to = "now" }
    schemaVersion = 39

    panels = concat(
      [for i, p in local.stat_panels : {
        type       = "stat"
        title      = p.title
        datasource = local.ds
        gridPos    = { h = 5, w = 6, x = p.x, y = 0 }
        targets    = [{ expr = p.expr, refId = "A" }]
        fieldConfig = {
          defaults = {
            unit = p.unit
            thresholds = {
              mode = "absolute"
              steps = [
                { color = "green", value = null },
                { color = "red", value = var.stale_threshold },
              ]
            }
          }
          overrides = []
        }
      }],
      [
        {
          type       = "timeseries"
          title      = "Stage duration against budget"
          datasource = local.ds
          gridPos    = { h = 8, w = 12, x = 0, y = 5 }
          targets = [{
            expr         = "pipeline_stage_duration_seconds"
            legendFormat = "{{stage}}"
            refId        = "A"
          }]
          fieldConfig = { defaults = { unit = "s" }, overrides = [] }
        },
        {
          type       = "timeseries"
          title      = "Rows processed per stage"
          datasource = local.ds
          gridPos    = { h = 8, w = 12, x = 12, y = 5 }
          targets = [{
            expr         = "pipeline_rows_processed"
            legendFormat = "{{stage}}"
            refId        = "A"
          }]
          fieldConfig = { defaults = { unit = "short" }, overrides = [] }
        },
        {
          type       = "timeseries"
          title      = "Stage success, last run"
          datasource = local.ds
          gridPos    = { h = 7, w = 24, x = 0, y = 13 }
          targets = [{
            expr         = "pipeline_stage_success"
            legendFormat = "{{stage}}"
            refId        = "A"
          }]
          fieldConfig = { defaults = { unit = "short" }, overrides = [] }
        },
      ]
    )
  })
}
