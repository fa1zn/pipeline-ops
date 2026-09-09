variable "docker_host" {
  description = <<-D
    Docker endpoint. Leave null to fall back to DOCKER_HOST, which the Makefile
    fills in from the active docker context. Colima, OrbStack and Rancher all
    put the socket somewhere other than /var/run/docker.sock, so hardcoding it
    breaks on every machine but the one it was written on.
  D
  type        = string
  default     = null
}

variable "project" {
  description = "Prefix for every resource name, so two copies can coexist."
  type        = string
  default     = "pipeline-ops"
}

# --- alerting thresholds -----------------------------------------------------
# These are variables rather than constants because the production values are
# hours and no one will sit and watch an hour pass to check a rule works. The
# drill tfvars shortens them to seconds. Same rules, same code path.

variable "stale_after_seconds" {
  description = "Page when no run has succeeded for this long. 26h in production: a daily job plus two hours of slack."
  type        = number
  default     = 93600
}

variable "data_stale_after_seconds" {
  description = "Page when the newest ingested row is older than this. Answers a different question from stale_after_seconds."
  type        = number
  default     = 10800
}

variable "failure_window" {
  description = "Lookback for the stage-failure alert."
  type        = string
  default     = "1h"
}

variable "alert_for" {
  description = "How long a condition must hold before it pages. Absorbs a single bad scrape."
  type        = string
  default     = "2m"
}

variable "scrape_interval" {
  type    = string
  default = "15s"
}

# --- ports -------------------------------------------------------------------
variable "grafana_port" {
  type    = number
  default = 3000
}
variable "prometheus_port" {
  type    = number
  default = 9090
}
variable "alertmanager_port" {
  type    = number
  default = 9093
}
variable "pushgateway_port" {
  type    = number
  default = 9091
}
variable "postgres_port" {
  type    = number
  default = 55432
}
variable "sink_port" {
  type    = number
  default = 8085
}

variable "grafana_password" {
  type      = string
  default   = "admin"
  sensitive = true
}
