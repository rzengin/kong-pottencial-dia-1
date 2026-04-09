# ============================================================================
# VARIABLES — Configuración de autenticación y entorno
# ============================================================================

variable "konnect_token" {
  description = "Kong Konnect Personal Access Token (PAT)"
  type        = string
  sensitive   = true
}

variable "konnect_server_url" {
  description = "URL base del API de Konnect (ej: https://us.api.konghq.com)"
  type        = string
  default     = "https://us.api.konghq.com"
}

variable "control_plane_id" {
  description = "ID del Control Plane (obtenido por emulador-ci.sh vía API REST antes de terraform apply)"
  type        = string
  default     = ""
}

# ── IDs de los Gateway Services ──────────────────────────────────────────────
# El provider no tiene data source para konnect_gateway_service.
# Los IDs se obtienen automáticamente en el emulador-ci.sh vía la API REST
# y se exportan como TF_VAR_gateway_service_id_* antes de ejecutar terraform.
# Si no se proporcionan (vacío), el vínculo gateway_service queda omitido
# y aún así los API Products se crean correctamente.

variable "gateway_service_id_flights" {
  description = "ID del Gateway Service 'flights' en el Control Plane"
  type        = string
  default     = ""
}

variable "gateway_service_id_bookings" {
  description = "ID del Gateway Service 'bookings' en el Control Plane"
  type        = string
  default     = ""
}

variable "gateway_service_id_customers" {
  description = "ID del Gateway Service 'customers' en el Control Plane"
  type        = string
  default     = ""
}

variable "gateway_service_id_routes" {
  description = "ID del Gateway Service 'routes' en el Control Plane"
  type        = string
  default     = ""
}
