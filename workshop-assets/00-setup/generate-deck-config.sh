#!/bin/bash
# Genera .deck.yaml desde las variables de entorno KONNECT_TOKEN y CONTROL_PLANE_NAME.
# Ejecutar desde: workshop-assets/
# Uso: bash 00-setup/generate-deck-config.sh

if [ -z "$KONNECT_TOKEN" ] || [ -z "$CONTROL_PLANE_NAME" ]; then
  echo "❌ Faltan variables de entorno:"
  [ -z "$KONNECT_TOKEN" ]       && echo "   export KONNECT_TOKEN='tu-token'"
  [ -z "$CONTROL_PLANE_NAME" ] && echo "   export CONTROL_PLANE_NAME='nombre-del-cp'"
  exit 1
fi

cat > .deck.yaml << EOF
# Kong Konnect — decK Configuration
# Auto-generado el $(date '+%Y-%m-%d %H:%M') — NO COMMITEAR (está en .gitignore)

konnect-token: "$KONNECT_TOKEN"
konnect-control-plane-name: "$CONTROL_PLANE_NAME"
konnect-addr: "https://us.api.konghq.com"
analytics: false
timeout: 30
EOF

echo "✅ .deck.yaml generado en $(pwd)/.deck.yaml"
echo "   A partir de ahora todos los comandos 'deck' en este directorio"
echo "   usarán la configuración automáticamente — sin parámetros extra."
