# ============================================================================
# OUTPUTS — Información post-apply
# ============================================================================

output "container_id" {
  description = "ID del contenedor Docker del segundo Data Plane"
  value       = docker_container.kong_dp2.id
}

output "container_name" {
  description = "Nombre del contenedor"
  value       = docker_container.kong_dp2.name
}

output "proxy_url" {
  description = "URL del proxy del DP2"
  value       = "http://localhost:8010"
}

output "status_url" {
  description = "URL del status endpoint del DP2"
  value       = "http://localhost:8110/status"
}
