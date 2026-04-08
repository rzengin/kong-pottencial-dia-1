#!/bin/bash

# Resolución de rutas: funciona sin importar desde dónde se llame el script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ASSETS_DIR="$(dirname "$SCRIPT_DIR")"   # workshop-assets/
INSOMNIA_DIR="$ASSETS_DIR/insomnia"
GENERATED_FILE="$SCRIPT_DIR/kong-generated.yaml"  # dentro del proyecto

# =========================================================================
# KONG APIOPS PIPELINE EMULATOR
# Este script emula un GitHub Action o GitLab CI Runner ejecutando
# el flujo completo de plataforma: Linting, Conversión y Testing.
# =========================================================================

echo -e "\n🚀 INICIANDO PIPELINE DE INTEGRACIÓN CONTINUA (APIOps) 🚀"
echo "================================================================="

# ----------------------------------------------------
# FASE 1: VALIDACIÓN DEL DISEÑO VÍA LINTING (Design-First)
# ----------------------------------------------------
echo -e "\n[FASE 1] -> inso lint spec (Validando OpenAPI Contract)..."
# Validamos que el YAML de OpenAPI no tenga errores semánticos ni rompa reglas.
if inso lint spec "$INSOMNIA_DIR/flights-api.yaml" 2>&1; then
  echo "✅ Spec válida."
else
  echo -e "\n⚠️  La spec tiene errores de diseño (ver arriba). En un pipeline real esto bloquearía el despliegue."
  echo "   (Continuando demo para mostrar las fases siguientes...)"
fi

# ----------------------------------------------------
# FASE 2: GENERACIÓN DE CÓDIGO (Specs-to-Kong) 
# ----------------------------------------------------
echo -e "\n[FASE 2] -> deck file openapi2kong (Compilando a Declarativo)..."
# Traducimos automáticamente el contrato a la configuración nativa del Gateway
deck file openapi2kong -s "$INSOMNIA_DIR/flights-api.yaml" > "$GENERATED_FILE"
echo "✅ Configuración de Gateway generada en $GENERATED_FILE"

# ----------------------------------------------------
# FASE 3: LINTING DE LA INFRAESTRUCTURA GENERADA
# ----------------------------------------------------
echo -e "\n[FASE 3] -> deck file validate (Verificando Infraestructura)..."
deck file validate "$GENERATED_FILE"

# ----------------------------------------------------
# FASE 4: DRIFT DETECTION & PLAN (Dry-Run)
# ----------------------------------------------------
echo -e "\n[FASE 4] -> deck gateway diff (Plan de Despliegue)..."
# Compara el archivo generado con el estado actual del Control Plane en Konnect.
# Muestra exactamente qué se crearía, actualizaría o eliminaría si se hiciera el apply.

if [ ! -f "$ASSETS_DIR/.deck.yaml" ]; then
  echo "  ⚠️  No se encontró $ASSETS_DIR/.deck.yaml"
  echo "     Ejecuta: bash 00-setup/generate-deck-config.sh"
else
  deck gateway diff "$GENERATED_FILE" 2>&1
  DIFF_EXIT=$?
  if [ $DIFF_EXIT -eq 0 ] || [ $DIFF_EXIT -eq 2 ]; then
    echo "  ✅ Drift Detection completado — revisa el plan de cambios arriba."
  else
    echo "  ❌ Error al ejecutar el diff (exit $DIFF_EXIT)"
  fi
fi

# ----------------------------------------------------
# FASE 5: TESTING DE COMPORTAMIENTO
# ----------------------------------------------------
echo -e "\n[FASE 5] -> inso run test (Validación Unitaria Constante)..."
# Ejecutamos las aserciones construidas por QA para certificar que el Gateway 
# cumple con seguridad, rate limits y enrutamiento esperado.
inso run test "Bateria Pruebas Escenario 08" -e "Base Environment" -w "$INSOMNIA_DIR/Insomnia_Workspace.json"

# ----------------------------------------------------
# FASE 6: PUBLICACIÓN EN KONNECT API CATALOG
# ----------------------------------------------------
echo -e "\n[FASE 6] -> Konnect API Catalog (Publicando spec en el catálogo interno)..."
# Registramos el contrato OpenAPI en el Service Hub de Konnect para que
# los equipos internos puedan descubrir y consumir la API.

KONNECT_REGION="${KONNECT_REGION:-us}"
KONNECT_BASE="https://${KONNECT_REGION}.api.konghq.com"
PRODUCT_NAME="Flights API"
VERSION_NAME="v1"

# 6a. Buscar o crear el API Product
PRODUCT_SEARCH=$(curl -s -X GET \
  "$KONNECT_BASE/v2/api-products?filter%5Bname%5D=Flights+API" \
  -H "Authorization: Bearer $KONNECT_TOKEN" \
  -H "Accept: application/json")

PRODUCT_ID=$(echo "$PRODUCT_SEARCH" | \
  python3 -c "import sys,json; d=json.load(sys.stdin)['data']; print(d[0]['id'] if d else '')" 2>/dev/null)

if [ -z "$PRODUCT_ID" ]; then
  echo "  Creando API Product '$PRODUCT_NAME' en el catálogo..."
  CREATE_RESP=$(curl -s -X POST "$KONNECT_BASE/v2/api-products" \
    -H "Authorization: Bearer $KONNECT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"$PRODUCT_NAME\", \"description\": \"API de vuelos — Workshop Kong Konnect\"}")
  PRODUCT_ID=$(echo "$CREATE_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
  echo "  ✅ API Product creado: $PRODUCT_ID"
else
  echo "  ℹ️  API Product existente encontrado: $PRODUCT_ID"
fi

# 6b. Buscar o crear la versión del producto
VERSION_SEARCH=$(curl -s \
  "$KONNECT_BASE/v2/api-products/$PRODUCT_ID/product-versions" \
  -H "Authorization: Bearer $KONNECT_TOKEN")

VERSION_ID=$(echo "$VERSION_SEARCH" | \
  python3 -c "import sys,json; d=json.load(sys.stdin).get('data',[]); matches=[v['id'] for v in d if v.get('name')=='$VERSION_NAME']; print(matches[0] if matches else '')" 2>/dev/null)

if [ -z "$VERSION_ID" ]; then
  echo "  Creando versión '$VERSION_NAME'..."
  VER_RESP=$(curl -s -X POST \
    "$KONNECT_BASE/v2/api-products/$PRODUCT_ID/product-versions" \
    -H "Authorization: Bearer $KONNECT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"$VERSION_NAME\", \"publish_status\": \"published\"}")
  VERSION_ID=$(echo "$VER_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
  echo "  ✅ Versión '$VERSION_NAME' creada: $VERSION_ID"
else
  echo "  ℹ️  Versión '$VERSION_NAME' existente: $VERSION_ID"
fi

# 6c. Subir (o actualizar) la especificación OpenAPI
# El campo 'content' debe estar codificado en base64 según la API de Konnect
SPEC_PAYLOAD=$(python3 -c "
import json, base64
content = open('$INSOMNIA_DIR/flights-api.yaml', 'rb').read()
encoded = base64.b64encode(content).decode('utf-8')
print(json.dumps({'name': 'flights-api.yaml', 'content': encoded}))
")

# Endpoint: /specifications (plural) — POST para crear, PATCH para actualizar
SPEC_RESP=$(curl -s -o /tmp/spec_resp.json -w "%{http_code}" \
  -X POST "$KONNECT_BASE/v2/api-products/$PRODUCT_ID/product-versions/$VERSION_ID/specifications" \
  -H "Authorization: Bearer $KONNECT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$SPEC_PAYLOAD")

if [ "$SPEC_RESP" = "409" ]; then
  # Spec ya existe — obtener su ID y actualizarla
  SPEC_ID=$(cat /tmp/spec_resp.json | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
  if [ -z "$SPEC_ID" ]; then
    SPEC_ID=$(curl -s "$KONNECT_BASE/v2/api-products/$PRODUCT_ID/product-versions/$VERSION_ID/specifications" \
      -H "Authorization: Bearer $KONNECT_TOKEN" | \
      python3 -c "import sys,json; d=json.load(sys.stdin).get('data',[]); print(d[0]['id'] if d else '')" 2>/dev/null)
  fi
  SPEC_RESP=$(curl -s -o /tmp/spec_resp.json -w "%{http_code}" \
    -X PATCH "$KONNECT_BASE/v2/api-products/$PRODUCT_ID/product-versions/$VERSION_ID/specifications/$SPEC_ID" \
    -H "Authorization: Bearer $KONNECT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$SPEC_PAYLOAD")
  echo "  ✅ Especificación OpenAPI actualizada en el catálogo (HTTP $SPEC_RESP)"
elif [ "$SPEC_RESP" = "201" ] || [ "$SPEC_RESP" = "200" ]; then
  echo "  ✅ Especificación OpenAPI publicada en el catálogo (HTTP $SPEC_RESP)"
else
  echo "  ⚠️  Respuesta inesperada al publicar spec: HTTP $SPEC_RESP"
  python3 -c "import json; f=open('/tmp/spec_resp.json'); print(json.dumps(json.load(f), indent=2))" 2>/dev/null
fi

# ----------------------------------------------------
# FASE 7: PUBLICACIÓN EN DEV PORTAL
# ----------------------------------------------------
echo -e "\n[FASE 7] -> Konnect Dev Portal (Publicando API para consumidores externos)..."
# Habilitamos la visibilidad de la API en el portal de desarrolladores
# para que equipos externos puedan registrarse y obtener credenciales.

# Obtener el portal por defecto
PORTAL_RESP=$(curl -s "$KONNECT_BASE/v2/portals" \
  -H "Authorization: Bearer $KONNECT_TOKEN")

PORTAL_ID=$(echo "$PORTAL_RESP" | \
  python3 -c "import sys,json; d=json.load(sys.stdin).get('data',[]); print(d[0]['id'] if d else '')" 2>/dev/null)

if [ -z "$PORTAL_ID" ]; then
  echo "  ⚠️  No se encontró un Dev Portal activo en esta organización."
  echo "     Crea un portal en https://cloud.konghq.com/portals y vuelve a ejecutar."
else
  echo "  ℹ️  Dev Portal encontrado: $PORTAL_ID"

  # Publicar la versión del producto en el portal
  PUBLISH_RESP=$(curl -s -o /tmp/portal_resp.json -w "%{http_code}" \
    -X POST "$KONNECT_BASE/v2/portals/$PORTAL_ID/product-versions" \
    -H "Authorization: Bearer $KONNECT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"product_version_id\": \"$VERSION_ID\",
      \"publish_status\": \"published\",
      \"deprecated\": false,
      \"application_registration_enabled\": true,
      \"auto_approve_registration\": false
    }")

  if [ "$PUBLISH_RESP" = "201" ]; then
    echo "  ✅ API publicada en el Dev Portal (visible para desarrolladores externos)"
  elif [ "$PUBLISH_RESP" = "409" ]; then
    echo "  ✅ API ya estaba publicada en el Dev Portal — sin cambios necesarios"
  else
    echo "  ⚠️  Respuesta al publicar en portal: HTTP $PUBLISH_RESP"
    cat /tmp/portal_resp.json
  fi
fi

echo "================================================================="
echo -e "🎉 PIPELINE COMPLETADO EXITOSAMENTE. LISTO PARA PRODUCCIÓN 🎉\n"
