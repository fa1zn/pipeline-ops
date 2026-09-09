output "grafana_container_id" { value = docker_container.grafana.id }
output "network" { value = docker_network.this.name }
output "pipeline_image" { value = docker_image.pipeline.name }
