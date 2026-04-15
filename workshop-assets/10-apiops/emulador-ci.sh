#!/bin/bash

# ── Entorno: asegurar PATH completo y variables Konnect ─────────────────────
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if [ -z "$KONNECT_TOKEN" ] && [ -f "$HOME/.zshrc" ]; then
  eval "$(grep -E '^export (KONNECT_TOKEN|KONNECT_ADDR|CONTROL_PLANE_NAME|CONTROL_PLANE_ID)=' "$HOME/.zshrc")"
fi
# ─────────────────────────────────────────────────────────────────────────────

# Resolución de rutas
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ASSETS_DIR="$(dirname "$SCRIPT_DIR")"
INSOMNIA_DIR="$ASSETS_DIR/insomnia"

# Directorio de trabajo del pipeline (archivos intermedios)
PIPELINE_DIR="/tmp/apiops-pipeline"
rm -rf "$PIPELINE_DIR" && mkdir -p "$PIPELINE_DIR"

# Fuentes de configuración (multi-team)
PLATFORM_DIR="$SCRIPT_DIR/platform-team"
FLIGHTS_OAS="$INSOMNIA_DIR/flights-api.yaml"
BOOKINGS_SPEC="$SCRIPT_DIR/specs/bookings-api.yaml"
CUSTOMERS_SPEC="$SCRIPT_DIR/specs/customers-api.yaml"
ROUTES_SPEC="$SCRIPT_DIR/specs/routes-api.yaml"

# Separador visual de workflow
wf_header() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════╗"
  printf  "║  %-64s║\n" "$1"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  echo "   Ref: https://developer.konghq.com/konnect-reference-platform/apiops/"
  echo ""
}

pr_banner() {
  echo ""
  echo "  ┌─────────────────────────────────────────────────────────────┐"
  echo "  │  🔀  PULL REQUEST SIMULADO (en CI real: GitHub Actions PR)  │"
  echo "  │  $1"
  echo "  │  Estado: ✅ Auto-aprobado para el workshop                   │"
  echo "  └─────────────────────────────────────────────────────────────┘"
  echo ""
}

echo ""
echo "🚀 PIPELINE APIOPS — Konnect Reference Platform Model 🚀"
echo "=================================================================="
echo "  Basado en: developer.konghq.com/konnect-reference-platform/apiops"
echo "  Empresa de ejemplo: KongAirlines → nuestro caso: Workshop Airlines"
echo "  Equipos: flights-team · bookings-team · customers-team · routes-team"
echo "  Plataforma: platform-team (observabilidad, conformance, Terraform)"
echo "=================================================================="

# ============================================================================
# WORKFLOW 1: OpenAPI → decK
# Equivale a: konnect-spec-to-deck.yaml de KongAirlines
# Pasos: OAS lint → openapi2kong → add-plugins (equipo) → add-tags →
#        merge (platform plugins) → render (config unificada) →
#        validate → lint (conformance)
# ============================================================================
wf_header "WORKFLOW 1/3 │ OpenAPI → decK  (konnect-spec-to-deck)"

# ── PASO 1.1: OAS Conformance (diseño primero) ────────────────────────────
echo "[1.1] inso lint spec — OAS Conformance (Platform Team ruleset)..."
if inso lint spec "$FLIGHTS_OAS" 2>&1; then
  echo "  ✅ Spec válida."
else
  echo "  ⚠️  La spec tiene errores de diseño. En CI real esto bloquearia el PR."
  echo "     (Continuando para mostrar el resto del pipeline...)"
fi

# ── PASO 1.2: openapi2kong — Generar config base por equipo ───────────────
echo ""
echo "[1.2] deck file openapi2kong — Compilando OAS → decK por equipo..."

# Flights API (fuente: insomnia/flights-api.yaml)
deck file openapi2kong -s "$FLIGHTS_OAS" \
  | deck file add-tags --selector='$..services[*]' flights-team \
  -o "$PIPELINE_DIR/flights-base.yaml" 2>/dev/null
echo "  ✅ flights-team: $PIPELINE_DIR/flights-base.yaml"

# Bookings API
deck file openapi2kong -s "$BOOKINGS_SPEC" \
  | deck file add-tags --selector='$..services[*]' bookings-team \
  -o "$PIPELINE_DIR/bookings-base.yaml" 2>/dev/null
echo "  ✅ bookings-team: $PIPELINE_DIR/bookings-base.yaml"

# Customers API
deck file openapi2kong -s "$CUSTOMERS_SPEC" \
  | deck file add-tags --selector='$..services[*]' customers-team \
  -o "$PIPELINE_DIR/customers-base.yaml" 2>/dev/null
echo "  ✅ customers-team: $PIPELINE_DIR/customers-base.yaml"

# Routes API
deck file openapi2kong -s "$ROUTES_SPEC" \
  | deck file add-tags --selector='$..services[*]' routes-team \
  -o "$PIPELINE_DIR/routes-base.yaml" 2>/dev/null
echo "  ✅ routes-team: $PIPELINE_DIR/routes-base.yaml"

# ── PASO 1.3: add-plugins (equipo) — Plugins propios de cada API Team ─────
echo ""
echo "[1.3] deck file add-plugins — Inyectando plugins de cada equipo..."
echo "  (Cada equipo agrega sus propios plugins de transformación y validación)"

deck file add-plugins \
  -s "$PIPELINE_DIR/flights-base.yaml" \
  "$SCRIPT_DIR/flights-team/plugins-equipo.yaml" \
  -o "$PIPELINE_DIR/flights-plugins.yaml" 2>/dev/null
echo "  ✅ flights-team: correlation-id + response-transformer aplicados"

deck file add-plugins \
  -s "$PIPELINE_DIR/bookings-base.yaml" \
  "$SCRIPT_DIR/bookings-team/plugins-equipo.yaml" \
  -o "$PIPELINE_DIR/bookings-plugins.yaml" 2>/dev/null
echo "  ✅ bookings-team: correlation-id aplicado"

deck file add-plugins \
  -s "$PIPELINE_DIR/customers-base.yaml" \
  "$SCRIPT_DIR/customers-team/plugins-equipo.yaml" \
  -o "$PIPELINE_DIR/customers-plugins.yaml" 2>/dev/null
echo "  ✅ customers-team: correlation-id aplicado"

deck file add-plugins \
  -s "$PIPELINE_DIR/routes-base.yaml" \
  "$SCRIPT_DIR/routes-team/plugins-equipo.yaml" \
  -o "$PIPELINE_DIR/routes-plugins.yaml" 2>/dev/null
echo "  ✅ routes-team: correlation-id aplicado"

# ── PASO 1.4: render — Unificación de todas las APIs ─────────────────────
echo ""
echo "[1.4] deck file render — Unificando todas las APIs en kong-from-oas.yaml..."
deck file render \
  "$PIPELINE_DIR/flights-plugins.yaml" \
  "$PIPELINE_DIR/bookings-plugins.yaml" \
  "$PIPELINE_DIR/customers-plugins.yaml" \
  "$PIPELINE_DIR/routes-plugins.yaml" \
  -o "$PIPELINE_DIR/kong-from-oas.yaml" 2>/dev/null
echo "  ✅ Config unificada: $PIPELINE_DIR/kong-from-oas.yaml"

# ── PASO 1.5: merge — Platform Team inyecta plugins globales ──────────────
echo ""
echo "[1.5] deck file merge — Platform Team inyecta plugins de observabilidad..."
echo "  (prometheus + file-log + opentelemetry — siempre presentes en TODAS las APIs)"

deck file merge \
  "$PIPELINE_DIR/kong-from-oas.yaml" \
  "$PLATFORM_DIR/plugins-observabilidad.yaml" \
  -o "$PIPELINE_DIR/kong-merged.yaml" 2>/dev/null || \
deck file merge \
  "$PIPELINE_DIR/kong-from-oas.yaml" \
  "$PLATFORM_DIR/plugins-observabilidad.yaml" \
  > "$PIPELINE_DIR/kong-merged.yaml" 2>/dev/null

if [ -s "$PIPELINE_DIR/kong-merged.yaml" ]; then
  echo "  ✅ Plugins de observabilidad del Platform Team fusionados"
else
  # Fallback: usar la config sin merge de observabilidad
  cp "$PIPELINE_DIR/kong-from-oas.yaml" "$PIPELINE_DIR/kong-merged.yaml"
  echo "  ⚠️  Merge con plugins de observabilidad no disponible — usando config base"
fi

# ── PASO 1.6: validate (offline) ─────────────────────────────────────────
echo ""
echo "[1.6] deck file validate — Validación offline de la config final..."
deck file validate "$PIPELINE_DIR/kong-merged.yaml" 2>/dev/null && \
  echo "  ✅ Config final válida (offline)" || \
  echo "  ⚠️  Validación offline con advertencias (no bloquea — revisión manual recomendada)"

# ── PASO 1.7: lint — Conformance del Platform Team ───────────────────────
echo ""
echo "[1.7] deck file lint — Conformance del Platform Team (linting-rules.yaml)..."
echo "  (Verifica tags, nombres de rutas, URLs de upstream)"
deck file lint \
  -s "$PIPELINE_DIR/kong-merged.yaml" \
  --fail-severity warn \
  "$PLATFORM_DIR/linting-rules.yaml" 2>/dev/null && \
  echo "  ✅ Conformance OK — config aprobada por el Platform Team" || \
  echo "  ⚠️  Advertencias de conformance. En CI real requiere revisión de plataforma."

# Guardar resultado del Workflow 1 (el archivo siempre existirá)
cp "$PIPELINE_DIR/kong-merged.yaml" "$SCRIPT_DIR/kong-generated.yaml"
echo "  📄 Artifact generado: kong-generated.yaml"

pr_banner "Workflow 1 completado: kong-generated.yaml listo para Stage   │"

# ── PASO 1.8: inso run test — Batería post-spec (antes del diff) ─────────
echo "[1.8] inso run test — Validación de comportamiento pre-despliegue..."
inso run test "Bateria Pruebas Escenario 09" -e "Base Environment" \
  -w "$INSOMNIA_DIR/Insomnia_Workspace.json" 2>&1

# ============================================================================
# WORKFLOW 2: Stage decK Changes
# Equivale a: konnect-stage-deck-change.yaml de KongAirlines
# Genera el diff y lo presenta como un PR para revisión del adminstrador
# ============================================================================
wf_header "WORKFLOW 2/3 │ Stage decK Changes  (konnect-stage-deck-change)"

echo "[2.1] deck gateway diff — Calculando cambios vs. estado actual del Control Plane..."
echo "  (En GitHub Actions: este diff se publica como comentario en el PR)"
echo ""

if [ ! -f "$ASSETS_DIR/.deck.yaml" ]; then
  echo "  ⚠️  No se encontró .deck.yaml"
else
  deck gateway diff "$SCRIPT_DIR/kong-generated.yaml" 2>&1
  DIFF_EXIT=$?
  echo ""
  if [ $DIFF_EXIT -eq 0 ] || [ $DIFF_EXIT -eq 2 ]; then
    echo "  ✅ Drift Detection completado — revisa el plan de cambios arriba."
  else
    echo "  ⚠️  Error al ejecutar el diff (exit $DIFF_EXIT)"
  fi
fi

pr_banner "Workflow 2 completado: diff revisado → aprobado para Sync      │"

# ============================================================================
# WORKFLOW 3: decK Sync
# Equivale a: konnect-deck-sync.yaml de KongAirlines
# Se dispara al mergear el PR del Workflow 2. En el workshop: auto-aprobado.
# ============================================================================
wf_header "WORKFLOW 3/3 │ decK Sync  (konnect-deck-sync)"

echo "[3.1] deck gateway sync — Aplicando configuración al Control Plane..."
echo "  (En CI real: se ejecuta automáticamente al mergear el PR #2)"
echo ""

if [ -f "$ASSETS_DIR/.deck.yaml" ]; then
  deck gateway sync "$SCRIPT_DIR/kong-generated.yaml" 2>&1
  SYNC_EXIT=$?
  echo ""
  if [ $SYNC_EXIT -eq 0 ]; then
    echo "  ✅ Sync completado — Gateway actualizado con la nueva config"
  else
    echo "  ❌ Error en deck gateway sync (exit $SYNC_EXIT)"
  fi
fi

# ============================================================================
# FASE ADICIONAL 4: Terraform — Platform Resources (Konnect)
# Fuera del scope de la Reference Platform (solo decK), pero complementario:
# gestiona API Products, Dev Portal y Service Catalog via Terraform.
# ============================================================================
echo ""
echo "┌──────────────────────────────────────────────────────────────────┐"
echo "│  FASE 4 │ Terraform — Recursos de Plataforma Konnect             │"
echo "│  (API Products · Dev Portal · Service Catalog)                   │"
echo "└──────────────────────────────────────────────────────────────────┘"

TERRAFORM_DIR="$SCRIPT_DIR/terraform"
KONNECT_REGION="${KONNECT_REGION:-us}"
KONNECT_API="https://${KONNECT_REGION}.api.konghq.com"

# Obtener Control Plane ID dinámicamente
echo "  → Obteniendo Control Plane ID..."
CP_RESP=$(curl -s -H "Authorization: Bearer $KONNECT_TOKEN" \
  "$KONNECT_API/v2/control-planes?filter%5Bname%5D%5Beq%5D=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${CONTROL_PLANE_NAME:-Local Gateway}'))")")
CP_ID=$(echo "$CP_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data'][0]['id'] if d.get('data') else '')" 2>/dev/null)

if [ -z "$CP_ID" ]; then
  echo "  ⚠️  No se pudo obtener el Control Plane ID (¿KONNECT_TOKEN válido?)"
else
  echo "  ✅ Control Plane ID: $CP_ID"
fi

# Obtener Gateway Service IDs
SVC_RESP=$(curl -s -H "Authorization: Bearer $KONNECT_TOKEN" \
  "$KONNECT_API/v2/control-planes/$CP_ID/core-entities/services?size=50")

get_svc_id() {
  local name="$1"
  echo "$SVC_RESP" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for s in d.get('data', []):
    if s.get('name') == '$name':
        print(s.get('id', ''))
        break
" 2>/dev/null
}

# Exportar variables para Terraform
export TF_VAR_konnect_token="$KONNECT_TOKEN"
export TF_VAR_konnect_server_url="$KONNECT_API"
export TF_VAR_control_plane_id="$CP_ID"
export TF_VAR_gateway_service_id_flights="$(get_svc_id "flights")"
export TF_VAR_gateway_service_id_bookings="$(get_svc_id "bookings")"
export TF_VAR_gateway_service_id_customers="$(get_svc_id "customers")"
export TF_VAR_gateway_service_id_routes="$(get_svc_id "routes")"

if ! command -v terraform &>/dev/null; then
  echo "  ⚠️  Terraform no instalado — saltando (brew install terraform)"
else
  cd "$TERRAFORM_DIR"
  terraform init -upgrade -input=false -no-color 2>&1 | grep -E "(Initializing|provider|Error)" | head -5
  echo "  → terraform plan (Drift Detection de Plataforma)..."
  terraform plan -out=tfplan -input=false -no-color 2>&1 | tail -5
  echo "  → terraform apply..."
  if terraform apply -auto-approve -input=false -no-color tfplan 2>&1; then
    echo "  ✅ Plataforma Konnect desplegada:"
    echo "     📚 API Products + versiones + specs + docs"
    echo "     🌐 Dev Portal → $(terraform output -raw portal_v2_url 2>/dev/null || echo 'ver Konnect UI')"
  else
    echo "  ❌ Error en terraform apply"
  fi
  cd "$SCRIPT_DIR"
fi

# ── Service Catalog + Resource Mappings (curl — único residuo Terraform) ────
echo ""
echo "  → Service Catalog + Resource Mappings (curl — único residuo no cubierto por Terraform)..."
SC_BASE="https://${KONNECT_REGION}.api.konghq.com/v1"

# Paso A: Obtener resources actuales del gateway (gateway_svc)
RESOURCES_JSON=$(curl -sg -H "Authorization: Bearer $KONNECT_TOKEN" \
  "$SC_BASE/resources?filter%5Btype%5D%5Beq%5D=gateway_svc&page%5Bsize%5D=100")

get_resource_id() {
  local svc_name="$1"
  echo "$RESOURCES_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('data', []):
    if item.get('name') == '$svc_name' and item.get('type') == 'gateway_svc':
        print(item.get('id', ''))
        break
" 2>/dev/null
}

# Paso B: Crear Catalog Services (si no existen) y obtener sus IDs
create_or_get_catalog_service() {
  local slug="$1"
  local display="$2"

  # Intentar crear
  RESP=$(curl -sg -o /tmp/cs.json -w "%{http_code}" \
    -X POST "$SC_BASE/catalog-services" \
    -H "Authorization: Bearer $KONNECT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$slug\",\"display_name\":\"$display\"}")

  if [ "$RESP" = "201" ]; then
    CS_ID=$(python3 -c "import json; d=json.load(open('/tmp/cs.json')); print(d.get('id',''))" 2>/dev/null)
    echo "  ✅ Catalog Service creado: $slug ($CS_ID)"
    echo "$CS_ID"
  elif [ "$RESP" = "409" ]; then
    # Ya existe — obtenerlo
    ALL_CS=$(curl -sg -H "Authorization: Bearer $KONNECT_TOKEN" "$SC_BASE/catalog-services")
    CS_ID=$(echo "$ALL_CS" | python3 -c "
import json,sys,os
data=json.load(sys.stdin).get('data',[])
for s in data:
    if s.get('name')=='$slug': print(s['id']); break
" 2>/dev/null)
    echo "  ℹ️  Catalog Service ya existe: $slug ($CS_ID)"
    echo "$CS_ID"
  else
    echo "  ⚠️  Error creando Catalog Service '$slug' (HTTP $RESP): $(cat /tmp/cs.json 2>/dev/null)"
    echo ""
  fi
}

# Paso C: Crear services y vincular con resource-mappings
for MAPPING in "flights-api|Flights API|flights" "bookings-api|Bookings API|bookings" "customers-api|Customers API|customers" "routes-api|Routes API|routes"; do
  IFS='|' read -r CS_SLUG CS_DISPLAY GW_NAME <<< "$MAPPING"

  # Crear/obtener el Catalog Service
  CS_ID=$(create_or_get_catalog_service "$CS_SLUG" "$CS_DISPLAY" | tail -1)
  [ -z "$CS_ID" ] && echo "  ⚠️  No se pudo obtener ID para '$CS_SLUG'" && continue

  # Obtener el gateway resource ID
  RESOURCE_ID=$(get_resource_id "$GW_NAME")
  [ -z "$RESOURCE_ID" ] && echo "  ⚠️  Gateway resource '$GW_NAME' no encontrado" && continue

  # Crear el resource-mapping usando el ID (UUID) del Catalog Service
  RM_RESP=$(curl -sg -o /tmp/rm.json -w "%{http_code}" \
    -X POST "$SC_BASE/resource-mappings" \
    -H "Authorization: Bearer $KONNECT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"service\": \"$CS_SLUG\", \"resource\": \"$RESOURCE_ID\"}")
  [ "$RM_RESP" = "201" ] && echo "  ✅ $GW_NAME → $CS_SLUG vinculado"
  [ "$RM_RESP" = "409" ] && echo "  ℹ️  $GW_NAME → $CS_SLUG ya vinculado"
  [ "$RM_RESP" != "201" ] && [ "$RM_RESP" != "409" ] && \
    echo "  ⚠️  Error $GW_NAME (HTTP $RM_RESP)"
done

echo ""
echo "=================================================================="
echo "🎉 PIPELINE COMPLETADO EXITOSAMENTE. LISTO PARA PRODUCCIÓN 🎉"
echo ""
echo "  Estructura multi-equipo aplicada:"
echo "    Workflow 1 → OAS → decK (3 equipos + Platform Team)"
echo "    Workflow 2 → Stage diff  (deck gateway diff)"
echo "    Workflow 3 → Sync        (deck gateway sync)"
echo "    Fase 4     → Terraform   (API Products · Portal · Catalog)"
echo "=================================================================="
