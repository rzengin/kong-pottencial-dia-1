#!/bin/bash
# ============================================================
# PRE-DEMO: Ejecuta escenarios 00 → 07 y deja el entorno
# listo para que el instructor ejecute el 08 EN VIVO.
# Ejecutar desde: workshop-assets/
# ============================================================

# ── Entorno ──────────────────────────────────────────────────
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if [ -z "$KONNECT_TOKEN" ] && [ -f "$HOME/.zshrc" ]; then
  eval "$(grep -E '^export (KONNECT_TOKEN|KONNECT_ADDR|CONTROL_PLANE_NAME|CONTROL_PLANE_ID)=' "$HOME/.zshrc")"
fi

# ── Colores ───────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

PASS=0; FAIL=0
WAIT=30

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║   🚀  POTTENCIAL KONG WORKSHOP — PRE-DEMO SETUP     ║"
echo "║       Escenarios 00 → 07 (demo 08 será en vivo)    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

if [ ! -f ".deck.yaml" ]; then
  echo -e "${RED}❌ .deck.yaml no encontrado. Ejecuta: bash 00-setup/generate-deck-config.sh${RESET}"
  exit 1
fi

ok()   { echo -e "  ${GREEN}✅ $1${RESET}"; ((PASS++)); }
fail() { echo -e "  ${RED}❌ $1 (esperado: $2, obtenido: $3)${RESET}"; ((FAIL++)); }

check() {
  local desc="$1" expected="$2"
  local got
  got=$(curl -s -o /dev/null -w "%{http_code}" "${@:3}")
  if [ "$got" = "$expected" ]; then ok "$desc"; else fail "$desc" "$expected" "$got"; fi
}

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
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}📦 $1${RESET}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  deck gateway sync "$2" 2>&1 | grep -E "creating|updating|deleting|Summary"
  echo "⏳ Aguardando sincronización Konnect → DP (${WAIT}s)..."
  sleep $WAIT
}

# ─────────────────────────────────────────────────────────────
# STEP 0: Stack de Observabilidad (LGTM) — necesario para E00+
# ─────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Levantando stack de observabilidad (LGTM)..."
docker compose -f observabilidad/docker-compose.yaml down 2>&1 | grep -E "Stopped|Removed|Error" | head -5
docker compose -f observabilidad/docker-compose.yaml up -d 2>&1 | grep -E "Started|Created|Error"
sleep 5
echo -e "  ${GREEN}✅ Stack LGTM listo (Grafana · Prometheus · Loki · Jaeger · Promtail)${RESET}"

# ─────────────────────────────────────────────────────────────
# STEP 1: Backend Mock (Prism) — puerto 8080
# ─────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Levantando backend mock Prism (puerto 8080)..."
docker rm -f prism_mock 2>/dev/null || true
docker run -d --platform linux/amd64 --name prism_mock -p 8080:4010 \
  -v "$(pwd)/insomnia/flights-api.yaml:/tmp/flights-api.yaml" \
  stoplight/prism:5 mock -h 0.0.0.0 /tmp/flights-api.yaml -m false 2>&1 | tail -1
sleep 3
echo -e "  ${GREEN}✅ Prism mock listo en http://localhost:8080${RESET}"

# ─────────────────────────────────────────────────────────────
# STEP 2: Backend httpbin — puerto 8081
# ─────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Levantando httpbin (puerto 8081)..."
docker rm -f httpbin 2>/dev/null || true
docker run -d --name httpbin -p 8081:80 kennethreitz/httpbin 2>&1 | tail -1
sleep 3
echo -e "  ${GREEN}✅ httpbin listo en http://localhost:8081${RESET}"

# ─────────────────────────────────────────────────────────────
# ESCENARIO 00 — Setup / Observabilidad
# ─────────────────────────────────────────────────────────────
apply "ESCENARIO 00 — Setup Observabilidad" "00-setup/kong.yaml"
check "GET / → 404 (sin rutas aún)" "404" http://localhost:8000/

# ─────────────────────────────────────────────────────────────
# ESCENARIO 01 — Routing base
# ─────────────────────────────────────────────────────────────
apply "ESCENARIO 01 — Routing base" "01-base/kong.yaml"
check "GET /flights → 200" "200" http://localhost:8000/flights
check "GET /customers → 200" "200" http://localhost:8000/customers

# ─────────────────────────────────────────────────────────────
# ESCENARIO 02 — Key Auth
# ─────────────────────────────────────────────────────────────
apply "ESCENARIO 02 — Key Auth" "02-seguridad-auth/kong.yaml"
check_retry "Sin key → 401" "401" http://localhost:8000/flights
check "Key externa → 200" "200" -H "apikey: my-external-key" http://localhost:8000/flights
check "Key interna → 200 (sin ACL aún)" "200" -H "apikey: my-internal-key" http://localhost:8000/flights

# ─────────────────────────────────────────────────────────────
# ESCENARIO 03 — Restricción de métodos HTTP
# ─────────────────────────────────────────────────────────────
apply "ESCENARIO 03 — Restricción de métodos" "03-metodos-opcional/kong.yaml"
check "GET /flights → 200" "200" -H "apikey: my-external-key" http://localhost:8000/flights
check "POST /flights → 404 (método no permitido)" "404" -X POST -H "apikey: my-external-key" http://localhost:8000/flights

# ─────────────────────────────────────────────────────────────
# ESCENARIO 04 — ACL
# ─────────────────────────────────────────────────────────────
apply "ESCENARIO 04 — ACL" "04-seguridad-acl-opcional/kong.yaml"
check "External → 200" "200" -H "apikey: my-external-key" http://localhost:8000/flights
check "Internal → 403 (ACL bloqueado)" "403" -H "apikey: my-internal-key" http://localhost:8000/flights

# ─────────────────────────────────────────────────────────────
# ESCENARIO 05 — Rate Limiting
# ─────────────────────────────────────────────────────────────
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
[ "$ok_count" -eq 5 ] && ok "5 requests con 200" || fail "requests con 200" "5" "$ok_count"
[ "$rl_count" -ge 2 ] && ok "2+ requests con 429 (rate limit activo)" || fail "requests con 429" "2" "$rl_count"

# ─────────────────────────────────────────────────────────────
apply "ESCENARIO 06 — Transformaciones" "06-transformaciones-opcional/kong.yaml"
headers=$(curl -si -H "apikey: my-external-key" http://localhost:8000/flights 2>/dev/null)
echo "$headers" | grep -qi "x-perceptiva"     && ok "Header x-perceptiva presente"     || fail "Header x-perceptiva" "presente" "ausente"

# ─────────────────────────────────────────────────────────────
# ESCENARIO 07 — Correlation ID
# ─────────────────────────────────────────────────────────────
apply "ESCENARIO 07 — Correlation ID" "07-correlation-id/kong.yaml"
headers=$(curl -si -H "apikey: my-external-key" http://localhost:8000/flights 2>/dev/null)
echo "$headers" | grep -qi "x-correlation-id" && ok "Header x-correlation-id presente" || fail "Header x-correlation-id" "presente" "ausente"

# ─────────────────────────────────────────────────────────────
# RESUMEN FINAL
# ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}📊 RESULTADO: ${GREEN}✅ $PASS pasaron${RESET}${BOLD} | ${RED}❌ $FAIL fallaron${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════${RESET}"

if [ $FAIL -eq 0 ]; then
  echo ""
  echo -e "${BOLD}${GREEN}🎉 ENTORNO LISTO — Puedes comenzar la demo del escenario 08!${RESET}"
  echo ""
  echo -e "${YELLOW}📋 PRÓXIMO PASO (demo en vivo):${RESET}"
  echo "   deck gateway sync 08-observabilidad/kong.yaml"
  echo ""
  echo -e "${YELLOW}🔗 URLs útiles para la demo:${RESET}"
  echo "   Kong Proxy:  http://localhost:8000"
  echo "   Grafana:     http://localhost:3000  (admin / admin)"
  echo "   Prometheus:  http://localhost:9090"
  echo "   Jaeger:      http://localhost:16686"
  echo "   Loki:        http://localhost:3100"
  echo ""
else
  echo ""
  echo -e "${RED}⚠️  Hay $FAIL fallo(s) — revisar antes de hacer la demo.${RESET}"
fi
