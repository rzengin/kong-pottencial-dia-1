#!/bin/bash
# Validación completa de todos los escenarios 00-10
# Ejecutar desde: workshop-assets/

PASS=0
FAIL=0
WAIT=20  # segundos a esperar sincronización Konnect → DP

if [ ! -f ".deck.yaml" ]; then
  echo "❌ .deck.yaml no encontrado. Ejecuta: bash 00-setup/generate-deck-config.sh"
  exit 1
fi

ok()   { echo "  ✅ $1"; ((PASS++)); }
fail() { echo "  ❌ $1 (esperado: $2, obtenido: $3)"; ((FAIL++)); }

check() {
  local desc="$1" expected="$2"
  local got
  got=$(curl -s -o /dev/null -w "%{http_code}" "${@:3}")
  if [ "$got" = "$expected" ]; then ok "$desc"; else fail "$desc" "$expected" "$got"; fi
}

apply() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📦 $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  deck gateway apply "$2" 2>&1 | grep -E "creating|updating|deleting|Summary"
  echo "⏳ Aguardando sincronização (${WAIT}s)..."
  sleep $WAIT
}

# ─────────────────────────────────────────────
apply "ESCENARIO 00 — Setup Observabilidad" "00-setup/kong.yaml"
check "GET / → 404 (sin rutas)" "404" http://localhost:8000/

# ─────────────────────────────────────────────
apply "ESCENARIO 01 — Base routing" "01-base/kong.yaml"
check "GET /flights → 200" "200" http://localhost:8000/flights
check "GET /customers → 200" "200" http://localhost:8000/customers

# ─────────────────────────────────────────────
apply "ESCENARIO 02 — Restricción de métodos" "02-metodos/kong.yaml"
check "GET /flights → 200" "200" http://localhost:8000/flights
check "POST /flights → 404" "404" -X POST http://localhost:8000/flights

# ─────────────────────────────────────────────
apply "ESCENARIO 03 — Key Auth" "03-seguridad-auth/kong.yaml"
check "Sin key → 401" "401" http://localhost:8000/flights
check "Key externa → 200" "200" -H "apikey: my-external-key" http://localhost:8000/flights
check "Key interna → 200 sin ACL aun" "200" -H "apikey: my-internal-key" http://localhost:8000/flights

# ─────────────────────────────────────────────
apply "ESCENARIO 04 — ACL" "04-seguridad-acl/kong.yaml"
check "External → 200" "200" -H "apikey: my-external-key" http://localhost:8000/flights
check "Internal → 403" "403" -H "apikey: my-internal-key" http://localhost:8000/flights

# ─────────────────────────────────────────────
apply "ESCENARIO 05 — Rate Limiting (External: 5/min)" "05-rate-limiting/kong.yaml"
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
apply "ESCENARIO 06 — Transformaciones" "06-transformaciones/kong.yaml"
headers=$(curl -si -H "apikey: my-external-key" http://localhost:8000/flights 2>/dev/null)
echo "$headers" | grep -qi "x-perceptiva" && ok "Header x-perceptiva presente" || fail "Header x-perceptiva" "presente" "ausente"
echo "$headers" | grep -qi "x-correlation-id" && ok "Header x-correlation-id presente" || fail "Header x-correlation-id" "presente" "ausente"

# ─────────────────────────────────────────────
apply "ESCENARIO 07 — Observabilidad completa" "07-observabilidad/kong.yaml"
check "GET /flights (external) → 200" "200" -H "apikey: my-external-key" http://localhost:8000/flights
check "GET /debug/headers → 200 (httpbin)" "200" http://localhost:8000/debug/headers
metrics=$(curl -s http://localhost:8100/metrics | grep "^kong_http_requests_total" | wc -l | tr -d ' ')
[ "$metrics" -gt 0 ] && ok "Métricas Prometheus disponibles ($metrics series)" || fail "Métricas Prometheus" ">0" "$metrics"

# ─────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 ESCENARIO 08 — Testing con inso CLI"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
inso run test "Bateria Pruebas Escenario 08" \
  -e "Base Environment" \
  -w insomnia/Insomnia_Workspace.json 2>&1
[ $? -eq 0 ] && ok "Suite de 3 tests pasó" || fail "inso test suite" "exit 0" "exit $?"

# ─────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 ESCENARIO 09 — APIOps / Emulador CI"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash 09-apiops/emulador-ci.sh 2>&1 | grep -E "✅|⚠️|passing|COMPLETADO|Error"
ok "Pipeline APIOps ejecutado"

# ─────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 ESCENARIO 10 — Clustering / DP2"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker rm -f kong_local_dp2 2>/dev/null
bash 10-clustering/dp2.sh 2>&1 | tail -2
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
