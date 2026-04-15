#!/bin/bash
# =============================================================================
# KONG WORKSHOP — LIMPIEZA DE KONNECT (Catalog Services + API Catalog + Dev Portal)
# =============================================================================
# Ejecutar desde: workshop-assets/
# Uso: bash 00-setup/cleanup-konnect.sh
#
# Este script elimina los recursos creados por el Escenario 10 (APIOps):
#   - Catalog Services en "Applications > Catalog > Services"
#   - API Products "Kong Workshop — *" (y todas sus versiones/specs)
#   - Dev Portal "Kong Workshop Portal"
#
# Se invoca automáticamente al inicio del taller (Ejercicio 0) para garantizar
# que cada ejecución del pipeline parte de un estado limpio y reproducible.
# =============================================================================

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if [ -z "$KONNECT_TOKEN" ] && [ -f "$HOME/.zshrc" ]; then
  eval "$(grep -E '^export (KONNECT_TOKEN|KONNECT_ADDR|CONTROL_PLANE_NAME|CONTROL_PLANE_ID)=' "$HOME/.zshrc")"
fi

KONNECT_REGION="${KONNECT_REGION:-us}"
KONNECT_BASE="https://${KONNECT_REGION}.api.konghq.com"
SC_BASE="https://${KONNECT_REGION}.api.konghq.com/v1"

# Los 4 API Products del workshop
CATALOG_PRODUCTS=(
  "Kong Workshop — Flights API"
  "Kong Workshop — Bookings API"
  "Kong Workshop — Customers API"
  "Kong Workshop — Routes API"
)

# Los 4 Catalog Services del Service Catalog (slugs lowercase = lo que almacena la API)
CATALOG_SVC_NAMES=(
  "flights-api"
  "bookings-api"
  "customers-api"
  "routes-api"
)

if [ -z "$KONNECT_TOKEN" ]; then
  echo "❌ KONNECT_TOKEN no definido. Ejecuta primero: bash 00-setup/generate-deck-config.sh"
  exit 1
fi

PORTAL_NAME="Kong Workshop — Portal"

echo "🧹 Limpiando recursos de Konnect para el workshop..."

# -------------------------------------------------------------------------
# 0a. Eliminar APIs del Catalog > APIs (v3 API)
# -------------------------------------------------------------------------
echo ""
echo "  [Catalog > APIs] Buscando APIs del workshop..."

API_CATALOG_BASE_C="https://${KONNECT_REGION}.api.konghq.com/v3"
API_CATALOG_NAMES=("Flights API" "Bookings API" "Customers API" "Routes API")

ALL_AC=$(curl -s "$API_CATALOG_BASE_C/apis?page_size=50" \
  -H "Authorization: Bearer $KONNECT_TOKEN")

for AC_NAME in "${API_CATALOG_NAMES[@]}"; do
  AC_ID=$(echo "$ALL_AC" | AC_NAME="$AC_NAME" python3 -c "
import sys, json, os
name = os.environ['AC_NAME']
data = json.load(sys.stdin).get('data', [])
for a in data:
    if a.get('name') == name:
        print(a['id'])
" 2>/dev/null)

  if [ -z "$AC_ID" ]; then
    echo "  ✓ No existía API: '$AC_NAME'"
  else
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
      -X DELETE "$API_CATALOG_BASE_C/apis/$AC_ID" \
      -H "Authorization: Bearer $KONNECT_TOKEN")
    if [ "$HTTP" = "204" ] || [ "$HTTP" = "200" ]; then
      echo "  ✅ API eliminada: '$AC_NAME' ($AC_ID)"
    else
      echo "  ⚠️  Error al eliminar API '$AC_NAME' (HTTP $HTTP)"
    fi
  fi
done

# -------------------------------------------------------------------------
# 0b. Eliminar Catalog Services del Service Catalog (Applications > Catalog > Services)
# -------------------------------------------------------------------------
echo ""
echo "  [Service Catalog] Buscando Catalog Services del workshop..."

ALL_CS=$(curl -s "$SC_BASE/catalog-services?page_size=50" \
  -H "Authorization: Bearer $KONNECT_TOKEN")

for CS_NAME in "${CATALOG_SVC_NAMES[@]}"; do
  CS_ID=$(echo "$ALL_CS" | CS_NAME="$CS_NAME" python3 -c "
import sys, json, os
name = os.environ['CS_NAME']
data = json.load(sys.stdin).get('data', [])
for s in data:
    if s.get('name') == name:
        print(s['id'])
" 2>/dev/null)

  if [ -z "$CS_ID" ]; then
    echo "  ✓ No existía Catalog Service: '$CS_NAME'"
  else
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
      -X DELETE "$SC_BASE/catalog-services/$CS_ID" \
      -H "Authorization: Bearer $KONNECT_TOKEN")
    if [ "$HTTP" = "204" ] || [ "$HTTP" = "200" ]; then
      echo "  ✅ Catalog Service eliminado: '$CS_NAME' ($CS_ID)"
    else
      echo "  ⚠️  Error al eliminar Catalog Service '$CS_NAME' (HTTP $HTTP)"
    fi
  fi
done

# -------------------------------------------------------------------------
# 1. Eliminar los 4 API Products del Catálogo (cascade: versiones/specs/docs)
# -------------------------------------------------------------------------
echo ""
echo "  [API Products] Buscando API Products del workshop..."

for PRODUCT_NAME in "${CATALOG_PRODUCTS[@]}"; do
  ENCODED_NAME=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$PRODUCT_NAME'))")
  PRODUCT_SEARCH=$(curl -s \
    "$KONNECT_BASE/v2/api-products?filter%5Bname%5D=$ENCODED_NAME" \
    -H "Authorization: Bearer $KONNECT_TOKEN")

  PRODUCT_IDS=$(echo "$PRODUCT_SEARCH" | \
    PRODUCT_NAME="$PRODUCT_NAME" python3 -c "
import sys, json, os
name = os.environ['PRODUCT_NAME']
data = json.load(sys.stdin).get('data', [])
for p in data:
    if p.get('name') == name:
        print(p['id'])
" 2>/dev/null)

  if [ -z "$PRODUCT_IDS" ]; then
    echo "  ✓ No existía: '$PRODUCT_NAME'"
  else
    for PID in $PRODUCT_IDS; do
      HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
        -X DELETE "$KONNECT_BASE/v2/api-products/$PID" \
        -H "Authorization: Bearer $KONNECT_TOKEN")
      if [ "$HTTP" = "204" ] || [ "$HTTP" = "200" ]; then
        echo "  ✅ Eliminado: '$PRODUCT_NAME' ($PID)"
      else
        echo "  ⚠️  Error al eliminar '$PRODUCT_NAME' $PID (HTTP $HTTP)"
      fi
    done
  fi
done

# -------------------------------------------------------------------------
# 2. Eliminar Dev Portal del workshop
# -------------------------------------------------------------------------
echo ""
echo "  [Dev Portal] Buscando portal '$PORTAL_NAME'..."

PORTAL_SEARCH=$(curl -s "$KONNECT_BASE/v2/portals" \
  -H "Authorization: Bearer $KONNECT_TOKEN")

PORTAL_IDS=$(echo "$PORTAL_SEARCH" | \
  PORTAL_NAME="$PORTAL_NAME" python3 -c "
import sys, json, os
name = os.environ['PORTAL_NAME']
data = json.load(sys.stdin).get('data', [])
for p in data:
    if p.get('name') == name:
        print(p['id'])
" 2>/dev/null)

if [ -z "$PORTAL_IDS" ]; then
  echo "  ✓ No existía Dev Portal '$PORTAL_NAME' — nada que limpiar."
else
  for PORTAL_ID in $PORTAL_IDS; do
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
      -X DELETE "$KONNECT_BASE/v2/portals/$PORTAL_ID" \
      -H "Authorization: Bearer $KONNECT_TOKEN")
    if [ "$HTTP" = "204" ] || [ "$HTTP" = "200" ]; then
      echo "  ✅ Dev Portal v2 eliminado: $PORTAL_ID"
    else
      echo "  ⚠️  Error al eliminar Dev Portal v2 $PORTAL_ID (HTTP $HTTP)"
    fi
  done
fi

# Limpiar también los portales v3 (kongportals.com)
PORTAL_V3_NAME="Kong Workshop Private"
echo ""
echo "  [Dev Portal v3] Buscando portal v3 '$PORTAL_V3_NAME'..."
API_V3_BASE="https://${KONNECT_REGION}.api.konghq.com/v3"
V3_PORTAL_IDS=$(curl -s "$API_V3_BASE/portals?page_size=20" \
  -H "Authorization: Bearer $KONNECT_TOKEN" | \
  python3 -c "
import sys, json
data = json.load(sys.stdin).get('data', [])
for p in data:
    if p.get('name') == '$PORTAL_V3_NAME':
        print(p['id'])
" 2>/dev/null)

if [ -z "$V3_PORTAL_IDS" ]; then
  echo "  ✓ No existía Dev Portal v3 '$PORTAL_V3_NAME' — nada que limpiar."
else
  for V3_PID in $V3_PORTAL_IDS; do
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
      -X DELETE "$API_V3_BASE/portals/$V3_PID" \
      -H "Authorization: Bearer $KONNECT_TOKEN")
    if [ "$HTTP" = "204" ] || [ "$HTTP" = "200" ]; then
      echo "  ✅ Dev Portal v3 eliminado: $V3_PID"
    else
      echo "  ⚠️  Error al eliminar Portal v3 $V3_PID (HTTP $HTTP)"
    fi
  done
fi

echo ""
echo "✅ Limpieza completada. El Escenario 10 puede ejecutarse con estado limpio."

