resource "docker_network" "this" {
  name = var.project
}

resource "docker_volume" "pgdata" {
  name = "${var.project}-pgdata"
}

resource "docker_volume" "grafana" {
  name = "${var.project}-grafana"
}

resource "docker_volume" "alerts" {
  name = "${var.project}-alerts"
}

# ---------------------------------------------------------------- data store
resource "docker_image" "postgres" {
  name = "postgres:16-alpine"
}

resource "docker_container" "postgres" {
  name    = "${var.project}-postgres"
  image   = docker_image.postgres.image_id
  restart = "unless-stopped"

  env = [
    "POSTGRES_USER=pipeline",
    "POSTGRES_PASSWORD=pipeline",
    "POSTGRES_DB=pipeline",
  ]

  networks_advanced {
    name    = docker_network.this.name
    aliases = ["postgres"]
  }

  ports {
    internal = 5432
    external = var.postgres_port
  }

  volumes {
    volume_name    = docker_volume.pgdata.name
    container_path = "/var/lib/postgresql/data"
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U pipeline"]
    interval = "5s"
    retries  = 12
  }
}

# ------------------------------------------------------------ metrics intake
resource "docker_image" "pushgateway" {
  name = "prom/pushgateway:v1.9.0"
}

resource "docker_container" "pushgateway" {
  name    = "${var.project}-pushgateway"
  image   = docker_image.pushgateway.image_id
  restart = "unless-stopped"

  networks_advanced {
    name    = docker_network.this.name
    aliases = ["pushgateway"]
  }

  ports {
    internal = 9091
    external = var.pushgateway_port
  }
}

# -------------------------------------------------------------- prometheus
resource "docker_image" "prometheus" {
  name = "prom/prometheus:v2.55.1"
}

resource "docker_container" "prometheus" {
  name    = "${var.project}-prometheus"
  image   = docker_image.prometheus.image_id
  restart = "unless-stopped"

  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.path=/prometheus",
    "--web.enable-lifecycle",
  ]

  networks_advanced {
    name    = docker_network.this.name
    aliases = ["prometheus"]
  }

  ports {
    internal = 9090
    external = var.prometheus_port
  }

  volumes {
    host_path      = "${var.observability_dir}/prometheus/rendered/prometheus.yml"
    container_path = "/etc/prometheus/prometheus.yml"
    read_only      = true
  }

  volumes {
    host_path      = "${var.observability_dir}/prometheus/rendered/rules"
    container_path = "/etc/prometheus/rules"
    read_only      = true
  }

  # A rendered rule file changing on disk does not restart the server, so the
  # fingerprint is carried into a label purely to force a replacement.
  labels {
    label = "config.fingerprint"
    value = var.config_fingerprint
  }
}

# ------------------------------------------------------------ alertmanager
resource "docker_image" "alertmanager" {
  name = "prom/alertmanager:v0.27.0"
}

resource "docker_container" "alertmanager" {
  name    = "${var.project}-alertmanager"
  image   = docker_image.alertmanager.image_id
  restart = "unless-stopped"

  networks_advanced {
    name    = docker_network.this.name
    aliases = ["alertmanager"]
  }

  ports {
    internal = 9093
    external = var.alertmanager_port
  }

  volumes {
    host_path      = "${var.observability_dir}/alertmanager/alertmanager.yml"
    container_path = "/etc/alertmanager/alertmanager.yml"
    read_only      = true
  }

  labels {
    label = "config.fingerprint"
    value = var.config_fingerprint
  }
}

# ------------------------------------------------------- where a page lands
resource "docker_image" "python" {
  name = "python:3.12-slim"
}

resource "docker_container" "sink" {
  name    = "${var.project}-sink"
  image   = docker_image.python.image_id
  restart = "unless-stopped"
  command = ["python", "/app/sink.py"]

  networks_advanced {
    name    = docker_network.this.name
    aliases = ["sink"]
  }

  ports {
    internal = 8080
    external = var.sink_port
  }

  volumes {
    host_path      = "${var.observability_dir}/sink/sink.py"
    container_path = "/app/sink.py"
    read_only      = true
  }

  volumes {
    volume_name    = docker_volume.alerts.name
    container_path = "/var/log/alerts"
  }

  labels {
    label = "config.fingerprint"
    value = var.config_fingerprint
  }
}

# ------------------------------------------------------------------ grafana
resource "docker_image" "grafana" {
  name = "grafana/grafana:11.3.0"
}

resource "docker_container" "grafana" {
  name    = "${var.project}-grafana"
  image   = docker_image.grafana.image_id
  restart = "unless-stopped"

  env = [
    "GF_SECURITY_ADMIN_PASSWORD=${var.grafana_password}",
    "GF_AUTH_ANONYMOUS_ENABLED=true",
    "GF_USERS_DEFAULT_THEME=light",
  ]

  networks_advanced {
    name    = docker_network.this.name
    aliases = ["grafana"]
  }

  ports {
    internal = 3000
    external = var.grafana_port
  }

  volumes {
    volume_name    = docker_volume.grafana.name
    container_path = "/var/lib/grafana"
  }
}

# --------------------------------------------------------------- the job
resource "docker_image" "pipeline" {
  name = "${var.project}/pipeline:latest"

  build {
    context = "${var.root_dir}/pipeline"
  }

  triggers = {
    src = sha1(join("", [for f in fileset("${var.root_dir}/pipeline", "**") :
    filesha1("${var.root_dir}/pipeline/${f}")]))
  }
}
