output "grafana" {
  value = "http://localhost:${var.grafana_port}  (admin / ${nonsensitive(var.grafana_password)})"
}

output "prometheus" {
  value = "http://localhost:${var.prometheus_port}"
}

output "alertmanager" {
  value = "http://localhost:${var.alertmanager_port}"
}

output "postgres_dsn" {
  value = "postgresql://pipeline:pipeline@localhost:${var.postgres_port}/pipeline"
}

output "alert_thresholds" {
  description = "What this apply will page on."
  value = {
    no_successful_run_for = "${var.stale_after_seconds}s"
    data_older_than       = "${var.data_stale_after_seconds}s"
    condition_held_for    = var.alert_for
  }
}
