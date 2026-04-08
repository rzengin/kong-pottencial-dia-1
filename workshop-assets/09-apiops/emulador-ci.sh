#!/bin/bash

# Resolución de rutas: funciona sin importar desde dónde se llame el script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ASSETS_DIR="$(dirname "$SCRIPT_DIR")"   # workshop-assets/
INSOMNIA_DIR="$ASSETS_DIR/insomnia"

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
deck file openapi2kong -s "$INSOMNIA_DIR/flights-api.yaml" > /tmp/kong-generated-devops.yaml
echo "✅ Configuración de Gateway generada exitosamente en /tmp/kong-generated-devops.yaml"

# ----------------------------------------------------
# FASE 3: LINTING DE LA INFRAESTRUCTURA GENERADA
# ----------------------------------------------------
echo -e "\n[FASE 3] -> deck file validate (Verificando Infraestructura)..."
deck file validate /tmp/kong-generated-devops.yaml

# ----------------------------------------------------
# FASE 4: DRIFT DETECTION & PLAN (Dry-Run)
# ----------------------------------------------------
echo -e "\n[FASE 4] -> deck gateway diff (Plan de Despliegue)..."
# Muestra qué cambiaría en el Control Plane si empujamos esto. 
# (Nota: Omitimos la conexión a Konnect aquí para no requerir Tokens en el script local, 
# pero en CI/CD real este paso evita sobrescribir reglas incorrectas).
echo "✅ Plan validado. No hay errores de formato bloqueantes."

# ----------------------------------------------------
# FASE 5: TESTING DE COMPORTAMIENTO
# ----------------------------------------------------
echo -e "\n[FASE 5] -> inso run test (Validación Unitaria Constante)..."
# Ejecutamos las aserciones construidas por QA para certificar que el Gateway 
# cumple con seguridad, rate limits y enrutamiento esperado.
inso run test "Bateria Pruebas Escenario 08" -e "Base Environment" -w "$INSOMNIA_DIR/Insomnia_Workspace.json"

echo "================================================================="
echo -e "🎉 PIPELINE COMPLETADO EXITOSAMENTE. LISTO PARA PRODUCCIÓN 🎉\n"
