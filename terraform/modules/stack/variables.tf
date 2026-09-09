variable "project" { type = string }
variable "observability_dir" { type = string }
variable "root_dir" { type = string }
variable "grafana_port" { type = number }
variable "grafana_password" {
  type      = string
  sensitive = true
}
variable "prometheus_port" { type = number }
variable "alertmanager_port" { type = number }
variable "pushgateway_port" { type = number }
variable "postgres_port" { type = number }
variable "sink_port" { type = number }
variable "config_fingerprint" {
  description = "Hash of the rendered configs. Changing it replaces Prometheus, which is the only way a rule change reaches a running server."
  type        = string
}
