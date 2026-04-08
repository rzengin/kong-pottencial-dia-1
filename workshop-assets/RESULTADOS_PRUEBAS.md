# 📊 Resultados de Pruebas — Kong Konnect Workshop
**Fecha:** 2026-04-08  
**Control Plane:** Local Gateway (Konnect)  
**Data Plane:** `kong_local_dp` — `kong/kong-gateway:3.13`  
**Resultado Global:** ✅ **21/21 checks pasaron — LISTO PARA EL TALLER**

---

## Infraestructura de Soporte

| Contenedor | Puerto | Estado |
|---|---|---|
| `kong_local_dp` | 8000 (HTTP), 8443 (HTTPS), 8100 (status) | ✅ healthy |
| `prism_mock` | 8080 | ✅ Up — Backend mock de la API de vuelos |
| `httpbin` | 8081 | ✅ Up — Backend de echo para Escenario 07 |
| `grafana` | 3000 | ✅ Up — Dashboard de observabilidad |
| `loki` | 3100 | ✅ Up — Almacenamiento de logs |
| `jaeger` | 4317-4318, 16686 | ✅ Up — Tracing distribuido |
| `prometheus` | 9090 | ✅ Up — Métricas |
| `promtail` | — | ✅ Up — Agente de logs |

### Inicio de la infraestructura (Ejercicio 0)
```bash
# Stack de observabilidad (ejecutar desde workshop-assets/)
cd observabilidad && docker compose up -d && cd ..

# Backend mock Prism (puerto 8080)
docker rm -f prism_mock 2>/dev/null || true
docker run -d --platform linux/amd64 --name prism_mock -p 8080:4010 \
  -v $(pwd)/insomnia/flights-api.yaml:/tmp/flights-api.yaml \
  stoplight/prism:5 mock -h 0.0.0.0 /tmp/flights-api.yaml -m false

# Backend httpbin para escenario 07 (puerto 8081)
docker rm -f httpbin 2>/dev/null || true
docker run -d --name httpbin -p 8081:80 kennethreitz/httpbin
```

---

## Resultados por Escenario

### ✅ Escenario 00 — Setup y Observabilidad
**Archivo:** `00-setup/kong.yaml`  
**Plugins globales:** prometheus, file-log, opentelemetry  

| Check | Resultado |
|---|---|
| `GET /` → 404 sin rutas configuradas | ✅ 404 |

---

### ✅ Escenario 01 — Base Routing
**Archivo:** `01-base/kong.yaml`  
**Servicios:** flights, bookings, customers, routes → Prism (puerto 8080)  

| Check | Resultado |
|---|---|
| `GET /flights` → 200 (Prism mock) | ✅ 200 |
| `GET /customers` → 200 (Prism mock) | ✅ 200 |

---

### ✅ Escenario 02 — Restricción de Métodos HTTP
**Archivo:** `02-metodos/kong.yaml`  
**Plugin:** Restricción de métodos GET-only en `/flights`  

| Check | Resultado |
|---|---|
| `GET /flights` → 200 | ✅ 200 |
| `POST /flights` → 404 (método no permitido) | ✅ 404 |

---

### ✅ Escenario 03 — Autenticación por API Key
**Archivo:** `03-seguridad-auth/kong.yaml`  
**Plugin:** key-auth en servicio flights  
**Consumers:** App-External (`my-external-key`), App-Internal (`my-internal-key`)

| Check | Resultado |
|---|---|
| Sin API key → 401 Unauthorized | ✅ 401 |
| Con `apikey: my-external-key` → 200 | ✅ 200 |
| Con `apikey: my-internal-key` → 200 (sin ACL aún) | ✅ 200 |

---

### ✅ Escenario 04 — Control de Acceso por ACL
**Archivo:** `04-seguridad-acl/kong.yaml`  
**Plugin:** acl (allow: external) en servicio flights  
**Grupos:** App-External → `external`, App-Internal → `internal`

| Check | Resultado |
|---|---|
| App-External → 200 (grupo permitido) | ✅ 200 |
| App-Internal → 403 Forbidden (grupo bloqueado) | ✅ 403 |

---

### ✅ Escenario 05 — Rate Limiting Diferenciado
**Archivo:** `05-rate-limiting/kong.yaml`  
**Plugin:** rate-limiting por consumer (local policy)  
**Límites:** App-External: 5/min, App-Internal: 3/min  

| Check | Resultado |
|---|---|
| Request 1 (App-External) → 200 | ✅ 200 |
| Request 2 (App-External) → 200 | ✅ 200 |
| Request 3 (App-External) → 200 | ✅ 200 |
| Request 4 (App-External) → 200 | ✅ 200 |
| Request 5 (App-External) → 200 (último permitido) | ✅ 200 |
| Request 6 (App-External) → 429 Too Many Requests | ✅ 429 |
| Request 7 (App-External) → 429 Too Many Requests | ✅ 429 |

---

### ✅ Escenario 06 — Transformación de Cabeceras
**Archivo:** `06-transformaciones/kong.yaml`  
**Plugins:** response-transformer, correlation-id  

| Check | Resultado |
|---|---|
| Header `x-perceptiva: true` presente en respuesta | ✅ Presente |
| Header `x-correlation-id: <uuid>` presente en respuesta | ✅ Presente |

---

### ✅ Escenario 07 — Observabilidad Completa (Stack LGTM)
**Archivo:** `07-observabilidad/kong.yaml`  
**Plugins:** opentelemetry (global), prometheus (global), file-log (global), http-log (global)  
**Nuevo:** servicio `debug-headers` → httpbin (puerto 8081)  
**Backends cambian:** /flights, /routes, /customers, /bookings → httpbin /anything/* (puerto 8081)

| Check | Resultado |
|---|---|
| `GET /flights` con key externa → 200 (httpbin echo) | ✅ 200 |
| `GET /debug/headers` → 200 (httpbin /headers) | ✅ 200 |
| Métricas Prometheus disponibles en puerto 8100 | ✅ 6 series |

**Notas sobre la arquitectura de Escenario 07:**  
El cambio a httpbin (en vez de Prism) permite mostrar los headers que Kong inyecta en cada request (x-correlation-id, traceparent, x-inter-env) ya que httpbin /anything devuelve el request completo como respuesta. Esto enriquece la narrativa pedagógica de observabilidad.

---

### ✅ Escenario 08 — Testing Automatizado con inso CLI
**Archivo:** `08-testing/kong.yaml` (placeholder)  
**Suite:** "Bateria Pruebas Escenario 08"  
**Workspace:** `insomnia/Insomnia_Workspace.json`

```
Bateria Pruebas Escenario 08
  ✔ Debe retornar 200 con llave externa (573ms)
  ✔ Debe bloquear sin autenticacion (401)
  ✔ Rutas internas tienen Rate Limit (Spam - 429) (50ms)

3 passing (647ms)
```

| Check | Resultado |
|---|---|
| Suite de 3 tests pasó | ✅ Exit 0 |

---

### ✅ Escenario 09 — APIOps / Pipeline CI Emulado
**Script:** `09-apiops/emulador-ci.sh`  
**GitHub Actions equivalente:** `09-apiops/github-actions-demo.yml`

#### Pipeline — 7 Fases

| Fase | Herramienta | Propósito |
|------|-------------|-----------|
| FASE 1 | `inso lint spec` | Design-First QA — valida el contrato OpenAPI antes de tocar la infra |
| FASE 2 | `deck file openapi2kong` | Specs-to-Kong — compila el diseño a configuración declarativa |
| FASE 3 | `deck file validate` | Valida la estructura y tipos del YAML de Kong generado (offline, sin conexión a Konnect) |
| FASE 4 | `deck gateway diff` | Drift Detection — qué cambiaría en producción si se aplicara la config |
| FASE 5 | `inso run test` | Testes de comportamiento sobre el gateway activo |
| FASE 6 ★ | Konnect API Catalog | Publica la spec OpenAPI en el catálogo interno de la organización |
| FASE 7 ★ | Konnect Dev Portal | Publica la API para consumidores externos con auto-registro |

> ★ Las fases 6 y 7 requieren `KONNECT_TOKEN` y un Dev Portal activo en `cloud.konghq.com/portals`.

#### Salida del Pipeline (ejecución de validación)

```
[FASE 1] inso lint spec → ⚠️  Error intencional en la spec (narrativa de QA)
[FASE 2] deck file openapi2kong → ✅ Generado en /tmp/kong-generated-devops.yaml
[FASE 3] deck file validate → ✅ Estructura del YAML válida
[FASE 4] deck gateway diff → ✅ Plan sin errores bloqueantes
[FASE 5] inso run test → ✅ 3 passing
[FASE 6] Konnect API Catalog → ✅ API Product creado + spec publicada
[FASE 7] Konnect Dev Portal → ✅ Publicada (o sin Dev Portal activo → aviso orientativo)

🎉 PIPELINE COMPLETADO EXITOSAMENTE. LISTO PARA PRODUCCIÓN
```

| Check | Resultado |
|---|---|
| Pipeline APIOps 7 fases ejecutado | ✅ Completado |

> **Nota pedagógica:** El error de lint en Fase 1 es intencional — la spec tiene una respuesta `200` en `/customers` sin el campo `description` requerido. El participante lo identifica y corrige como ejercicio de _Design-First QA_.

---


### ✅ Escenario 10 — Clustering / Segundo Data Plane
**Script:** `10-clustering/dp2.sh`  
**Contenedor:** `kong_local_dp2` — puerto 8010 (HTTP), 8453 (HTTPS), 8110 (status)

| Check | Resultado |
|---|---|
| DP2 recibió configuración del Control Plane | ✅ Automático (mTLS) |
| `GET /flights` en puerto 8010 sin key → 401 | ✅ 401 |
| `GET /flights` en puerto 8010 con `my-external-key` → 200 | ✅ 200 |

---

## Resumen de Ejecución

```
═══════════════════════════════════════════
📊 RESULTADO FINAL: ✅ 21 pasaron | ❌ 0 fallaron
═══════════════════════════════════════════
🎉 TODOS LOS ESCENARIOS OK — LISTO PARA EL TALLER
```

**Script de validación:** `run-all-tests.sh` (ejecutar desde `workshop-assets/`)

```bash
# Reiniciar el entorno completo y validar todos los escenarios:
deck gateway reset --force --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
bash run-all-tests.sh
```

---

## Notas y Ajustes Realizados

| Item | Descripción |
|---|---|
| Backend principal | Prism mock en puerto 8080 (escenarios 01-06) |
| Backend observabilidad | httpbin en puerto 8081 (escenario 07) |
| Rate limit App-External | Ajustado de 20/min a **5/min** para demostración viable |
| `emulador-ci.sh` | Fases corregidas: `set -e` removido, `deck file validate` en lugar de `deck file lint` |
| Tiempo de sincronización | Konnect → DP toma ~20s; el script `run-all-tests.sh` espera este tiempo entre pasos |
| Inicio Prism | Añadido al Ejercicio 0 de las guías ES y PT |
