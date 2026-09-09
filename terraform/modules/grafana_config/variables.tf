variable "project" { type = string }
variable "prometheus_url" { type = string }
variable "stale_threshold" {
  description = "Drives the red band on the freshness panels so the dashboard and the alert cannot drift apart."
  type        = number
}
