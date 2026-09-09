locals {
  obs  = abspath("${path.module}/../observability")
  root = abspath("${path.module}/..")

  # Rendered once here and mounted read-only, so the alert thresholds live in
  # tfvars rather than in a YAML file someone edits by hand on the box.
  humanize = {
    stale = format("%dh", ceil(var.stale_after_seconds / 3600))
    data  = format("%dh", ceil(var.data_stale_after_seconds / 3600))
  }
}

resource "local_file" "prometheus_config" {
  filename = "${local.obs}/prometheus/rendered/prometheus.yml"
  content = templatefile("${local.obs}/prometheus/prometheus.yml.tftpl", {
    scrape_interval = var.scrape_interval
  })
}

resource "local_file" "prometheus_rules" {
  filename = "${local.obs}/prometheus/rendered/rules/pipeline.rules.yml"
  content = templatefile("${local.obs}/prometheus/rules/pipeline.rules.yml.tftpl", {
    scrape_interval          = var.scrape_interval
    alert_for                = var.alert_for
    failure_window           = var.failure_window
    stale_after_seconds      = var.stale_after_seconds
    data_stale_after_seconds = var.data_stale_after_seconds
    stale_after_human        = local.humanize.stale
    data_stale_after_human   = local.humanize.data
  })
}

module "stack" {
  source = "./modules/stack"

  project           = var.project
  observability_dir = local.obs
  root_dir          = local.root

  grafana_port      = var.grafana_port
  grafana_password  = var.grafana_password
  prometheus_port   = var.prometheus_port
  alertmanager_port = var.alertmanager_port
  pushgateway_port  = var.pushgateway_port
  postgres_port     = var.postgres_port
  sink_port         = var.sink_port

  config_fingerprint = sha256(join("", [
    local_file.prometheus_config.content,
    local_file.prometheus_rules.content,
    file("${local.obs}/alertmanager/alertmanager.yml"),
    file("${local.obs}/sink/sink.py"),
  ]))

  depends_on = [local_file.prometheus_config, local_file.prometheus_rules]
}

# The grafana provider talks to a server that this same apply just created, so
# nothing may touch it until it answers. Terraform cannot make a provider depend
# on a resource, but it can make the resources that use it wait.
resource "terraform_data" "grafana_ready" {
  triggers_replace = [module.stack.grafana_container_id]

  provisioner "local-exec" {
    command = <<-SH
      for i in $(seq 1 60); do
        curl -sf http://localhost:${var.grafana_port}/api/health >/dev/null && exit 0
        sleep 2
      done
      echo "grafana did not become healthy" >&2
      exit 1
    SH
  }
}

module "grafana_config" {
  source = "./modules/grafana_config"

  project         = var.project
  prometheus_url  = "http://prometheus:9090"
  stale_threshold = var.stale_after_seconds

  depends_on = [terraform_data.grafana_ready]
}
