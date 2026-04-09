# ============================================================================
# KONG KONNECT — PLATAFORMA DECLARATIVA (Terraform)
# Reemplaza las Fases 6, 6b y 7 del emulador-ci.sh
#
# Gestión declarativa completa de:
#   FASE 7  — Dev Portal (se crea primero — portal_ids es required en API Products)
#   FASE 6  — API Products + versiones + specs + docs  → publicados en el portal
#   FASE 6b — Service Catalog (v1/catalog-services)
#
# ✅ Todo cubierto por el provider Kong/konnect ~2.7
#
# ❌ NO disponible en el provider (queda como curl residual en emulador-ci.sh):
#   - Fase 6c: Catalog APIs v3 (konnect_api, konnect_api_version, etc.)
#   - Resource Mapping (v1/resource-mappings)
#
# Uso:
#   terraform init
#   terraform plan    ← equivalente a "deck gateway diff" para la plataforma
#   terraform apply   ← deploy declarativo idempotente
#   terraform destroy ← limpieza total
# ============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    konnect = {
      source  = "Kong/konnect"
      version = "~> 2.7"
    }
  }
}

# ── Provider ─────────────────────────────────────────────────────────────────
provider "konnect" {
  personal_access_token = var.konnect_token
  server_url            = var.konnect_server_url
}


# ============================================================================
# FASE 7 — DEV PORTAL
# Debe crearse primero porque portal_ids es requerido en konnect_api_product
# Equivale a: POST /v2/portals
# ============================================================================

resource "konnect_portal" "workshop" {
  name                      = "Kong Workshop — Portal"
  is_public                 = false
  auto_approve_applications = false
  auto_approve_developers   = false
}


# ============================================================================
# FASE 6 — API PRODUCTS (v2)
# Equivale a: POST /v2/api-products + /product-versions + /specifications + /documents
# ============================================================================

# ── Flights API ───────────────────────────────────────────────────────────────
resource "konnect_api_product" "flights" {
  name        = "Kong Workshop — Flights API"
  description = "Flights API — Workshop Kong Konnect (APIOps Demo)"
  portal_ids  = [konnect_portal.workshop.id]
  labels      = { workshop = "true", scenario = "apiops" }
}

resource "konnect_api_product_version" "flights_v1" {
  api_product_id = konnect_api_product.flights.id
  name           = "v1"
  gateway_service = var.gateway_service_id_flights != "" ? {
    control_plane_id = var.control_plane_id
    id               = var.gateway_service_id_flights
  } : null
}

resource "konnect_api_product_specification" "flights_spec" {
  api_product_id         = konnect_api_product.flights.id
  api_product_version_id = konnect_api_product_version.flights_v1.id
  name                   = "flights-api.yaml"
  content                = filebase64("${path.module}/../../insomnia/flights-api.yaml")
}

resource "konnect_api_product_document" "flights_doc" {
  api_product_id     = konnect_api_product.flights.id
  title              = "Documentación"
  slug               = "getting-started"
  status             = "published"
  content            = filebase64("${path.module}/../docs/flights-api.md")
  parent_document_id = null
}

# ── Bookings API ──────────────────────────────────────────────────────────────
resource "konnect_api_product" "bookings" {
  name        = "Kong Workshop — Bookings API"
  description = "Bookings API — Workshop Kong Konnect (APIOps Demo)"
  portal_ids  = [konnect_portal.workshop.id]
  labels      = { workshop = "true", scenario = "apiops" }
}

resource "konnect_api_product_version" "bookings_v1" {
  api_product_id = konnect_api_product.bookings.id
  name           = "v1"
  gateway_service = var.gateway_service_id_bookings != "" ? {
    control_plane_id = var.control_plane_id
    id               = var.gateway_service_id_bookings
  } : null
}

resource "konnect_api_product_specification" "bookings_spec" {
  api_product_id         = konnect_api_product.bookings.id
  api_product_version_id = konnect_api_product_version.bookings_v1.id
  name                   = "bookings-api.yaml"
  content                = filebase64("${path.module}/../specs/bookings-api.yaml")
}

resource "konnect_api_product_document" "bookings_doc" {
  api_product_id     = konnect_api_product.bookings.id
  title              = "Documentación"
  slug               = "getting-started"
  status             = "published"
  content            = filebase64("${path.module}/../docs/bookings-api.md")
  parent_document_id = null
}

# ── Customers API ─────────────────────────────────────────────────────────────
resource "konnect_api_product" "customers" {
  name        = "Kong Workshop — Customers API"
  description = "Customers API — Workshop Kong Konnect (APIOps Demo)"
  portal_ids  = [konnect_portal.workshop.id]
  labels      = { workshop = "true", scenario = "apiops" }
}

resource "konnect_api_product_version" "customers_v1" {
  api_product_id = konnect_api_product.customers.id
  name           = "v1"
  gateway_service = var.gateway_service_id_customers != "" ? {
    control_plane_id = var.control_plane_id
    id               = var.gateway_service_id_customers
  } : null
}

resource "konnect_api_product_specification" "customers_spec" {
  api_product_id         = konnect_api_product.customers.id
  api_product_version_id = konnect_api_product_version.customers_v1.id
  name                   = "customers-api.yaml"
  content                = filebase64("${path.module}/../specs/customers-api.yaml")
}

resource "konnect_api_product_document" "customers_doc" {
  api_product_id     = konnect_api_product.customers.id
  title              = "Documentación"
  slug               = "getting-started"
  status             = "published"
  content            = filebase64("${path.module}/../docs/customers-api.md")
  parent_document_id = null
}

# ── Routes API ────────────────────────────────────────────────────────────────
resource "konnect_api_product" "routes" {
  name        = "Kong Workshop — Routes API"
  description = "Routes API — Workshop Kong Konnect (APIOps Demo)"
  portal_ids  = [konnect_portal.workshop.id]
  labels      = { workshop = "true", scenario = "apiops" }
}

resource "konnect_api_product_version" "routes_v1" {
  api_product_id = konnect_api_product.routes.id
  name           = "v1"
  gateway_service = var.gateway_service_id_routes != "" ? {
    control_plane_id = var.control_plane_id
    id               = var.gateway_service_id_routes
  } : null
}

resource "konnect_api_product_specification" "routes_spec" {
  api_product_id         = konnect_api_product.routes.id
  api_product_version_id = konnect_api_product_version.routes_v1.id
  name                   = "routes-api.yaml"
  content                = filebase64("${path.module}/../specs/routes-api.yaml")
}

resource "konnect_api_product_document" "routes_doc" {
  api_product_id     = konnect_api_product.routes.id
  title              = "Documentación"
  slug               = "getting-started"
  status             = "published"
  content            = filebase64("${path.module}/../docs/routes-api.md")
  parent_document_id = null
}


# ============================================================================
# PUBLICACIÓN EN EL PORTAL — Fase 7 (product versions publicados)
# Equivale a: POST /v2/portals/{id}/product-versions
# ============================================================================

resource "konnect_portal_product_version" "flights" {
  portal_id                        = konnect_portal.workshop.id
  product_version_id               = konnect_api_product_version.flights_v1.id
  publish_status                   = "published"
  deprecated                       = false
  application_registration_enabled = false
  auto_approve_registration        = false
  auth_strategy_ids                = []
}

resource "konnect_portal_product_version" "bookings" {
  portal_id                        = konnect_portal.workshop.id
  product_version_id               = konnect_api_product_version.bookings_v1.id
  publish_status                   = "published"
  deprecated                       = false
  application_registration_enabled = false
  auto_approve_registration        = false
  auth_strategy_ids                = []
}

resource "konnect_portal_product_version" "customers" {
  portal_id                        = konnect_portal.workshop.id
  product_version_id               = konnect_api_product_version.customers_v1.id
  publish_status                   = "published"
  deprecated                       = false
  application_registration_enabled = false
  auto_approve_registration        = false
  auth_strategy_ids                = []
}

resource "konnect_portal_product_version" "routes" {
  portal_id                        = konnect_portal.workshop.id
  product_version_id               = konnect_api_product_version.routes_v1.id
  publish_status                   = "published"
  deprecated                       = false
  application_registration_enabled = false
  auto_approve_registration        = false
  auth_strategy_ids                = []
}


# ============================================================================
# FASE 6b — SERVICE CATALOG (v1/catalog-services)
# ============================================================================
# NOTA: Los catalog services se gestionan vía la sección "RESIDUAL" del
# emulador-ci.sh mediante curl, ya que el provider tiene un bug de unmarshal
# al recibir respuestas de error de unicidad ("name must be unique").
# Ver: https://github.com/Kong/terraform-provider-konnect/issues
# Por eso se omiten aquí para evitar fallos en terraform apply.
# ============================================================================

