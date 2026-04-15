# ============================================================================
# OUTPUTS — Información útil post-apply
# ============================================================================

output "portal_id" {
  description = "ID del Dev Portal creado"
  value       = konnect_portal.workshop.id
}

output "portal_v2_url" {
  description = "URL del Dev Portal v2"
  value       = "https://${konnect_portal.workshop.default_domain}"
}

# Alias para compatibilidad con el emulador-ci.sh
output "portal_url" {
  description = "URL pública del Dev Portal"
  value       = "https://${konnect_portal.workshop.default_domain}"
}

output "api_product_ids" {
  description = "Mapa de nombre → ID de cada API Product creado"
  value = {
    flights   = konnect_api_product.flights.id
    bookings  = konnect_api_product.bookings.id
    customers = konnect_api_product.customers.id
    routes    = konnect_api_product.routes.id
  }
}

output "portal_published_versions" {
  description = "Versiones publicadas en el portal"
  value = {
    flights   = konnect_portal_product_version.flights.id
    bookings  = konnect_portal_product_version.bookings.id
    customers = konnect_portal_product_version.customers.id
    routes    = konnect_portal_product_version.routes.id
  }
}

output "control_plane_id" {
  description = "ID del Control Plane usado"
  value       = var.control_plane_id
}
