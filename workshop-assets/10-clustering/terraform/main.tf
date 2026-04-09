# ============================================================================
# ESCENARIO 10 — Clustering / Data Plane 2 (Docker + Terraform)
#
# Lanza un segundo Kong Data Plane local de forma declarativa.
# Demuestra que un nuevo nodo se registra automáticamente en Konnect
# y hereda toda la configuración del Control Plane sin intervención manual.
#
# Uso:
#   terraform init
#   terraform apply   ← lanza el contenedor kong_local_dp2
#   terraform destroy ← elimina el contenedor
# ============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}

# ── Imagen de Kong Gateway ────────────────────────────────────────────────────
resource "docker_image" "kong" {
  name         = "kong/kong-gateway:3.13"
  keep_locally = true  # no borrar la imagen al hacer destroy
}

# ── Segundo Data Plane ────────────────────────────────────────────────────────
resource "docker_container" "kong_dp2" {
  name     = "kong_local_dp2"
  image    = docker_image.kong.image_id
  hostname = "557f6aa59348"
  user     = "kong"
  restart  = "always"

  # Puertos expuestos (separados del DP1 que usa 8000/8443/8100)
  ports {
    internal = 8000
    external = 8010
  }
  ports {
    internal = 8443
    external = 8453
  }
  ports {
    internal = 8100
    external = 8110
  }

  # ── Variables de entorno del Data Plane ─────────────────────────────────────
  env = [
    "KONG_ROLE=data_plane",
    "KONG_STATUS_LISTEN=0.0.0.0:8100",
    "KONG_DATABASE=off",
    "KONG_KONNECT_MODE=on",
    "KONG_VITALS=off",
    "KONG_ROUTER_FLAVOR=expressions",
    "KONG_TRACING_INSTRUMENTATIONS=all",
    "KONG_CLUSTER_MTLS=pki",
    "KONG_CLUSTER_CONTROL_PLANE=${var.cluster_control_plane}",
    "KONG_CLUSTER_SERVER_NAME=${var.cluster_server_name}",
    "KONG_CLUSTER_TELEMETRY_ENDPOINT=${var.cluster_telemetry_endpoint}",
    "KONG_CLUSTER_TELEMETRY_SERVER_NAME=${var.cluster_telemetry_server_name}",
    "KONG_LUA_SSL_TRUSTED_CERTIFICATE=system",
    "KONG_UNTRUSTED_LUA=on",
    "KONG_CLUSTER_CERT=${var.cluster_cert}",
    "KONG_CLUSTER_CERT_KEY=${var.cluster_cert_key}",
  ]
}
