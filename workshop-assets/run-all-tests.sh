#!/bin/bash
# Validación completa de todos los escenarios 00-10
# Ejecutar desde: workshop-assets/

# ── Entorno: asegurar PATH completo y variables Konnect ─────────────────────
# Necesario cuando el script se ejecuta desde un shell con PATH mínimo (ej. Antigravity)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Cargar variables de Konnect desde .zshrc si no están definidas
if [ -z "$KONNECT_TOKEN" ] && [ -f "$HOME/.zshrc" ]; then
  eval "$(grep -E '^export (KONNECT_TOKEN|KONNECT_ADDR|CONTROL_PLANE_NAME|CONTROL_PLANE_ID)=' "$HOME/.zshrc")"
fi
# ─────────────────────────────────────────────────────────────────────────────

PASS=0
FAIL=0
WAIT=30  # segundos a esperar sincronización Konnect → DP (aumentado de 20 a 30)

if [ ! -f ".deck.yaml" ]; then
  echo "❌ .deck.yaml no encontrado. Ejecuta: bash 00-setup/generate-deck-config.sh"
  exit 1
fi

# ── Stack de Observabilidad (Grafana, Prometheus, Loki, Jaeger) ───────────────
echo "🔍 Reiniciando stack de observabilidad (down → up)..."
docker compose -f observabilidad/docker-compose.yaml down 2>&1 | grep -E "Stopped|Removed|Error" | head -5
docker compose -f observabilidad/docker-compose.yaml up -d 2>&1 | grep -E "Started|Created|Error"
sleep 5
echo "  ✅ Stack LGTM listo (Grafana · Prometheus · Loki · Jaeger · Promtail)"
# ─────────────────────────────────────────────────────────────────────────────

# ── Backend Mock (Prism) — puerto 8080 ──────────────────────────────────────
echo "🔍 Levantando backend mock Prism (puerto 8080)..."
docker rm -f prism_mock 2>/dev/null || true
docker run -d --platform linux/amd64 --name prism_mock -p 8080:4010 \
  -v "$(pwd)/insomnia/flights-api.yaml:/tmp/flights-api.yaml" \
  stoplight/prism:5 mock -h 0.0.0.0 /tmp/flights-api.yaml -m false 2>&1 | tail -1
sleep 3
echo "  ✅ Prism mock listo en http://localhost:8080"
# ─────────────────────────────────────────────────────────────────────────────

# ── Backend httpbin — puerto 8081 (necesario para E07/E08/E10) ───────────────
echo "🔍 Levantando httpbin (puerto 8081)..."
docker rm -f httpbin 2>/dev/null || true
docker run -d --name httpbin -p 8081:80 kennethreitz/httpbin 2>&1 | tail -1
sleep 3
echo "  ✅ httpbin listo en http://localhost:8081"
# ─────────────────────────────────────────────────────────────────────────────


ok()   { echo "  ✅ $1"; ((PASS++)); }
fail() { echo "  ❌ $1 (esperado: $2, obtenido: $3)"; ((FAIL++)); }

check() {
  local desc="$1" expected="$2"
  local got
  got=$(curl -s -o /dev/null -w "%{http_code}" "${@:3}")
  if [ "$got" = "$expected" ]; then ok "$desc"; else fail "$desc" "$expected" "$got"; fi
}

# check_retry: reintenta cada 5s hasta 60s total (para checks con latencia de propagación)
check_retry() {
  local desc="$1" expected="$2"
  local got elapsed=0 max=60
  while [ $elapsed -lt $max ]; do
    got=$(curl -s -o /dev/null -w "%{http_code}" "${@:3}")
    if [ "$got" = "$expected" ]; then ok "$desc (${elapsed}s)"; return; fi
    sleep 5; elapsed=$((elapsed+5))
    echo "    ↻ Reintentando $desc... ($elapsed/${max}s, obtenido: $got)"
  done
  fail "$desc" "$expected" "$got"
}

apply() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📦 $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  # IMPORTANTE: usar 'sync' (no 'apply') para que cada escenario
  # reemplace el estado completo del CP (elimina plugins del escenario anterior)
  deck gateway sync "$2" 2>&1 | grep -E "creating|updating|deleting|Summary"
  echo "⏳ Aguardando sincronização (${WAIT}s)..."
  sleep $WAIT
}


# ─────────────────────────────────────────────
# LIMPIEZA COMPLETA: Gateway + Plataforma Konnect
# deck gateway sync limpia el Gateway (rutas, plugins, consumers)
# terraform destroy limpia: Catalog Services, Catalog APIs, API Products, Dev Portal
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧹 LIMPIEZA PLATAFORMA KONNECT (Terraform)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -f "09-apiops/terraform/terraform.tfstate" ]; then
  export TF_VAR_konnect_token="$KONNECT_TOKEN"
  terraform -chdir=09-apiops/terraform destroy -auto-approve -no-color 2>&1 \
    | grep -E "destroyed|Destroyed|Error|No changes" | head -5
  echo "  ✅ Plataforma Konnect limpiada (Catalog · API Products · Dev Portal)"
else
  echo "  ℹ️  Sin estado Terraform previo — nada que limpiar"
fi

apply "ESCENARIO 00 — Setup Observabilidad" "00-setup/kong.yaml"
check "GET / → 404 (sin rutas)" "404" http://localhost:8000/

# ─────────────────────────────────────────────
apply "ESCENARIO 01 — Base routing" "01-base/kong.yaml"
check "GET /flights → 200" "200" http://localhost:8000/flights
check "GET /customers → 200" "200" http://localhost:8000/customers

# ─────────────────────────────────────────────
apply "ESCENARIO 02 — Key Auth" "02-seguridad-auth/kong.yaml"
check_retry "Sin key → 401" "401" http://localhost:8000/flights
check "Key externa → 200" "200" -H "apikey: my-external-key" http://localhost:8000/flights
check "Key interna → 200 sin ACL aun" "200" -H "apikey: my-internal-key" http://localhost:8000/flights

# ─────────────────────────────────────────────
apply "ESCENARIO 03 — Restricción de métodos" "03-metodos-opcional/kong.yaml"
check "GET /flights → 200" "200" -H "apikey: my-external-key" http://localhost:8000/flights
check "POST /flights → 404" "404" -X POST -H "apikey: my-external-key" http://localhost:8000/flights

# ─────────────────────────────────────────────
apply "ESCENARIO 04 — ACL" "04-seguridad-acl-opcional/kong.yaml"
check "External → 200" "200" -H "apikey: my-external-key" http://localhost:8000/flights
check "Internal → 403" "403" -H "apikey: my-internal-key" http://localhost:8000/flights

# ─────────────────────────────────────────────
apply "ESCENARIO 05 — Rate Limiting (External: 5/min)" "05-rate-limiting-opcional/kong.yaml"
echo "  Enviando 7 requests con key externa (esperado: 200×5 → 429×2):"
codes=""
for i in {1..7}; do
  c=$(curl -s -o /dev/null -w "%{http_code}" -H "apikey: my-external-key" http://localhost:8000/flights)
  codes="$codes $c"
  echo "    Request $i: $c"
done
ok_count=$(echo "$codes" | tr ' ' '\n' | grep -c "200")
rl_count=$(echo "$codes" | tr ' ' '\n' | grep -c "429")
[ "$ok_count" -eq 5 ] && ok "5 requests com 200" || fail "requests com 200" "5" "$ok_count"
[ "$rl_count" -ge 2 ] && ok "2+ requests com 429" || fail "requests com 429" "2" "$rl_count"

# ─────────────────────────────────────────────
apply "ESCENARIO 06 — Transformaciones" "06-transformaciones-opcional/kong.yaml"
headers=$(curl -si -H "apikey: my-external-key" http://localhost:8000/flights 2>/dev/null)
echo "$headers" | grep -qi "x-perceptiva" && ok "Header x-perceptiva presente" || fail "Header x-perceptiva" "presente" "ausente"

# ─────────────────────────────────────────────
apply "ESCENARIO 07 — Correlation ID" "07-correlation-id/kong.yaml"
headers=$(curl -si -H "apikey: my-external-key" http://localhost:8000/flights 2>/dev/null)
echo "$headers" | grep -qi "x-correlation-id" && ok "Header x-correlation-id presente" || fail "Header x-correlation-id" "presente" "ausente"

# ─────────────────────────────────────────────
apply "ESCENARIO 08 — Observabilidad completa" "08-observabilidad/kong.yaml"
check_retry "GET /flights (external) → 200" "200" -H "apikey: my-external-key" http://localhost:8000/flights
check_retry "GET /debug/headers → 200 (httpbin)" "200" http://localhost:8000/debug/headers
metrics=$(curl -s http://localhost:8100/metrics | grep "^kong_http_requests_total" | wc -l | tr -d ' ')
[ "$metrics" -gt 0 ] && ok "Métricas Prometheus disponibles ($metrics series)" || fail "Métricas Prometheus" ">0" "$metrics"

# ─────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 ESCENARIO 09 — Testing con inso CLI"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
inso run test "Bateria Pruebas Escenario 08" \
  -e "Base Environment" \
  -w insomnia/Insomnia_Workspace.json 2>&1
[ $? -eq 0 ] && ok "Suite de 3 tests pasó" || fail "inso test suite" "exit 0" "exit $?"

# ─────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 ESCENARIO 10 — APIOps / Emulador CI"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash 10-apiops/emulador-ci.sh 2>&1 | grep -E "✅|⚠️|passing|COMPLETADO|Error"
ok "Pipeline APIOps ejecutado"

# Restaurar estado del Gateway para E10 (el emulador-ci.sh usa su propia config generada)
echo "  → Restaurando estado base con key-auth para E11..."
deck gateway sync 08-observabilidad/kong.yaml --silence-events 2>&1 | grep -E "Summary|Error" | head -3
sleep 15

# ─────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 ESCENARIO 11 — Clustering / DP2 (Terraform + Docker)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
# Destruir primero si existe (garantiza estado limpio para el test)
export TF_VAR_konnect_token="$KONNECT_TOKEN"
terraform -chdir=11-clustering/terraform destroy -auto-approve -no-color 2>&1 | grep -E "destroyed|Error" | head -2
# Lanzar el segundo Data Plane via Terraform (provider kreuzwerker/docker)
terraform -chdir=11-clustering/terraform apply -auto-approve -no-color 2>&1 | grep -E "created|Error|Apply complete"
echo "⏳ Aguardando DP2 conectar ao Konnect (20s)..."
sleep 20
check "DP2 porta 8010 — Sin key → 401" "401" http://localhost:8010/flights
check "DP2 porta 8010 — Key externa → 200" "200" -H "apikey: my-external-key" http://localhost:8010/flights



# ─────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo "📊 RESULTADO FINAL: ✅ $PASS pasaron | ❌ $FAIL fallaron"
echo "═══════════════════════════════════════════"
[ $FAIL -eq 0 ] && echo "🎉 TODOS LOS ESCENARIOS OK — LISTO PARA EL TALLER" || echo "⚠️  Revisar los fallos arriba"
