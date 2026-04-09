# ============================================================================
# DATA SOURCES — Lookup mínimo de recursos existentes en Konnect
# ============================================================================
#
# NOTA: El provider Kong/konnect ~2.7 tiene limitaciones en data sources:
#   - konnect_gateway_service  → no existe
#   - konnect_gateway_control_plane_list → falla con CLUSTER_TYPE_SERVERLESS_V1
#
# Solución: el control_plane_id se pasa directamente como variable TF_VAR_*
# exportada por emulador-ci.sh desde la API REST de Konnect.
# ============================================================================
