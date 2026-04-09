#!/bin/bash
# ============================================================================
# cleanup.sh — Limpieza COMPLETA del entorno del workshop
#
# Borra TODO lo creado durante el laboratorio:
#   1. Plataforma Konnect (terraform destroy):
#      · Catalog Services · Catalog APIs · API Products · Dev Portal
#   2. Gateway Konnect (deck gateway reset):
#      · Servicios · Rutas · Plugins · Consumers · Credenciales
#   3. Contenedores Docker locales
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# ── Cargar KONNECT_TOKEN desde ~/.zshrc si no está en el entorno ─────────────
if [ -z "${KONNECT_TOKEN:-}" ] && [ -f "$HOME/.zshrc" ]; then
  eval "$(grep -E '^export (KONNECT_TOKEN)=' "$HOME/.zshrc" 2>/dev/null)" || true
fi

# ── Validar que el token existe — fallo rápido, sin colgar ───────────────────
if [ -z "${KONNECT_TOKEN:-}" ]; then
  echo ""
  echo "❌  KONNECT_TOKEN no está definido."
  echo ""
  echo "   Opciones para solucionarlo:"
  echo "   1) Exportarlo antes de correr el script:"
  echo "      export KONNECT_TOKEN='kpat_xxxxxxxxxxxxxxxxxx'"
  echo "      bash cleanup.sh"
  echo ""
  echo "   2) Agregarlo a ~/.zshrc para que persista:"
  echo "      echo \"export KONNECT_TOKEN='kpat_xxxxxxxxxxxxxxxxxx'\" >> ~/.zshrc"
  echo "      source ~/.zshrc && bash cleanup.sh"
  echo ""
  echo "   3) Obtener un nuevo token en:"
  echo "      https://cloud.konghq.com → Personal Access Tokens"
  echo ""
  exit 1
fi

# Pasar el token a Terraform sin prompts interactivos
export TF_VAR_konnect_token="$KONNECT_TOKEN"

# ── Helpers ──────────────────────────────────────────────────────────────────

# Colores
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# Spinner de progreso con contador de tiempo
_spinner_pid=""
start_spinner() {
  local msg="$1"
  local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0
  local secs=0
  (
    while true; do
      printf "\r   ${CYAN}%s${RESET} %s  [%ds]  " "${spin[$i]}" "$msg" "$secs"
      i=$(( (i+1) % ${#spin[@]} ))
      sleep 0.2
      # incrementa segundos cada 5 ticks (~1s)
      if (( i % 5 == 0 )); then secs=$((secs+1)); fi
    done
  ) &
  _spinner_pid=$!
}

stop_spinner() {
  if [[ -n "$_spinner_pid" ]]; then
    kill "$_spinner_pid" 2>/dev/null || true
    wait "$_spinner_pid" 2>/dev/null || true
    _spinner_pid=""
    printf "\r\033[K"   # limpia la línea del spinner
  fi
}

log_step() { echo -e "\n${BOLD}${CYAN}── $1${RESET}"; }
log_ok()   { echo -e "   ${GREEN}✅ $1${RESET}"; }
log_info() { echo -e "   ${YELLOW}ℹ️  $1${RESET}"; }
log_err()  { echo -e "   ${RED}❌ $1${RESET}"; }

elapsed() {
  local start=$1
  echo $(( SECONDS - start ))
}

# Limpieza del spinner si el script es interrumpido o termina
_cleanup_trap() {
  stop_spinner
}
trap '_cleanup_trap; echo -e "\n${RED}⚠️  Interrumpido por el usuario (Ctrl+C)${RESET}"; exit 130' INT TERM
trap '_cleanup_trap' EXIT

# ── Cabecera ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}🧹 LIMPIEZA COMPLETA DEL ENTORNO${RESET}"
echo "================================="
echo "   Inicio: $(date '+%H:%M:%S')"

TOTAL_START=$SECONDS

# ══════════════════════════════════════════════════════════════════════════════
# PASO 1 — Catalog Services + Catalog APIs (REST API de Konnect)
# ══════════════════════════════════════════════════════════════════════════════
log_step "Paso 1/4 — Catalog Services + Catalog APIs (REST API)"
echo "   Recursos: Catalog Services · Catalog APIs · API Products · Dev Portal"

T0=$SECONDS
CLEANUP_KONNECT="$SCRIPT_DIR/00-setup/cleanup-konnect.sh"
if [ -f "$CLEANUP_KONNECT" ]; then
  bash "$CLEANUP_KONNECT" 2>&1 | sed 's/^/   /' || true
  log_ok "Catalog limpiado en $(elapsed $T0)s"
else
  log_info "cleanup-konnect.sh no encontrado en 00-setup/ — omitiendo"
fi

# ══════════════════════════════════════════════════════════════════════════════
# PASO 2 — Terraform: Plataforma Konnect (API Products + Dev Portal)
# ══════════════════════════════════════════════════════════════════════════════
log_step "Paso 2/4 — Plataforma Konnect (Terraform destroy)"
echo "   Recursos: Catalog Services · Catalog APIs · API Products · Dev Portal"

TERRAFORM_DIR="$SCRIPT_DIR/09-apiops/terraform"

if [ -f "$TERRAFORM_DIR/terraform.tfstate" ]; then

  # ── Detectar y limpiar lock file huérfano ──────────────────────────────────
  LOCK_FILE="$TERRAFORM_DIR/.terraform.tfstate.lock.info"
  if [ -f "$LOCK_FILE" ]; then
    log_info "Lock file huérfano detectado — eliminando antes de continuar..."
    rm -f "$LOCK_FILE"
    log_ok "Lock file eliminado"
  fi

  # ── Contar recursos en el state ────────────────────────────────────────────
  RESOURCE_COUNT=$(grep -c '"type":' "$TERRAFORM_DIR/terraform.tfstate" 2>/dev/null || echo "?")
  echo "   Recursos detectados en tfstate: ${BOLD}${RESOURCE_COUNT}${RESET}"
  echo "   Esto puede tardar 1-3 minutos dependiendo de la API de Konnect..."

  echo "   Token: ${KONNECT_TOKEN:0:12}... ✓"
  T1=$SECONDS
  start_spinner "Destruyendo recursos Konnect vía Terraform..."

  TF_LOG_FILE="/tmp/cleanup_terraform_$$.log"
  set +e
  terraform -chdir="$TERRAFORM_DIR" destroy -auto-approve -no-color \
    2>&1 | tee "$TF_LOG_FILE" | \
    grep --line-buffered -E "Destroying|Destruction complete|destroyed|Error|No changes|Plan:" | \
    while IFS= read -r line; do
      stop_spinner
      echo "   → $line"
      start_spinner "Destruyendo recursos Konnect vía Terraform..."
    done
  TF_EXIT=${PIPESTATUS[0]}
  set -e

  stop_spinner

  if [ $TF_EXIT -eq 0 ]; then
    log_ok "Plataforma Konnect limpiada en $(elapsed $T1)s"
  else
    log_err "Terraform terminó con errores (exit $TF_EXIT)"
    echo "   Últimas líneas del log:"
    tail -5 "$TF_LOG_FILE" | sed 's/^/      /'
  fi
  rm -f "$TF_LOG_FILE"

else
  log_info "Sin estado Terraform previo (terraform.tfstate no existe) — omitiendo"
fi

# ══════════════════════════════════════════════════════════════════════════════
# PASO 2 — decK: Gateway Konnect
# ══════════════════════════════════════════════════════════════════════════════
log_step "Paso 3/4 — Gateway Konnect (deck gateway reset)"
echo "   Recursos: Servicios · Rutas · Plugins · Consumers · Credenciales"
echo "   Contactando Control Plane de Konnect..."

T2=$SECONDS
start_spinner "Ejecutando deck gateway reset..."

DECK_LOG_FILE="/tmp/cleanup_deck_$$.log"
set +e
deck gateway reset --force 2>&1 | tee "$DECK_LOG_FILE" | \
  grep --line-buffered -E "Deleted|deleting|Summary|Error|Total|connecting|Resetting" | \
  while IFS= read -r line; do
    stop_spinner
    echo "   → $line"
    start_spinner "Ejecutando deck gateway reset..."
  done
DECK_EXIT=${PIPESTATUS[0]}
set -e

stop_spinner

if [ $DECK_EXIT -eq 0 ]; then
  log_ok "Gateway Konnect limpiado en $(elapsed $T2)s"
else
  log_err "deck terminó con errores (exit $DECK_EXIT)"
  echo "   Últimas líneas del log:"
  tail -5 "$DECK_LOG_FILE" | sed 's/^/      /'
fi
rm -f "$DECK_LOG_FILE"

# ══════════════════════════════════════════════════════════════════════════════
# PASO 3 — Docker: contenedores locales
# ══════════════════════════════════════════════════════════════════════════════
log_step "Paso 4/4 — Contenedores Docker locales"

T3=$SECONDS

# prism_mock
echo "   → Deteniendo prism_mock..."
docker rm -f prism_mock 2>/dev/null \
  && log_ok "prism_mock eliminado" \
  || log_info "prism_mock no estaba corriendo"

# Stack LGTM (observabilidad)
echo "   → Deteniendo stack LGTM (Loki, Grafana, Prometheus, Jaeger, Promtail)..."
docker compose -f "$SCRIPT_DIR/observabilidad/docker-compose.yaml" down 2>&1 \
  | grep --line-buffered -E "Stopped|Removed|Removing|Container|Network|Error" \
  | sed 's/^/      /' || true
log_ok "Stack LGTM detenido en $(elapsed $T3)s"

# DP2 (Terraform Docker) — opcional
DP2_TF="$SCRIPT_DIR/10-clustering/terraform"
if [ -f "$DP2_TF/terraform.tfstate" ]; then
  echo "   → Destruyendo DP2 (Terraform Docker)..."
  T_DP2=$SECONDS
  start_spinner "Destruyendo DP2..."
  set +e
  terraform -chdir="$DP2_TF" destroy -auto-approve -no-color 2>&1 | \
    grep --line-buffered -E "destroyed|Destroying|Error" | \
    while IFS= read -r line; do
      stop_spinner; echo "      → $line"; start_spinner "Destruyendo DP2..."
    done || true
  set -e
  stop_spinner
  log_ok "DP2 eliminado en $(elapsed $T_DP2)s"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Resumen final
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "================================="
echo -e "${GREEN}${BOLD}🎉 Entorno limpiado por completo.${RESET}"
echo "   Tiempo total: ${BOLD}$(elapsed $TOTAL_START) segundos${RESET}"
echo "   Fin: $(date '+%H:%M:%S')"
echo ""
echo "   Puedes volver a ejecutar: bash run-all-tests.sh"
echo "================================="
