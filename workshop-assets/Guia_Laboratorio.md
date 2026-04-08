# Guía del Laboratorio: Kong Konnect

Este laboratorio tiene como objetivo demostrar las capacidades de control, seguridad, transformación y observabilidad usando Kong Konnect como Control Plane y un Data Plane local, administrado de forma completamente declarativa a través de `deck`.

---

## 1. Preparación del Entorno (Local y Konnect)

### A. Requisitos Básicos
1. Tener cuenta activa en **Kong Konnect**.
2. Tener instalado en tu equipo la CLI de **decK** (versión v1.40+), la herramienta **curl**, y la aplicación de escritorio **Insomnia** (versión gratuita).
3. El Data Plane local de Kong ya se encuentra levantado de forma permanente para este laboratorio.

### B. Identificación y Obtención de Credenciales
Dado que tu Data Plane ya se encuentra preconfigurado y operativo, sólo necesitas obtener y configurar tus credenciales de acceso a Konnect para gestionar las políticas remotamente:
1. Identifica tu **Control Plane** asignado en Kong Konnect (tendrá el formato `cp-local-tu.nombre`).
2. Ve a tus preferencias de perfil en Kong Konnect y genera un **Personal Access Token (PAT)** para usar con `decK`.

### C. Verificación del Entorno
Antes de comenzar el laboratorio, valida que todo funcione correctamente y tengas plena conectividad:
1. **Sincronización Konnect:** Ve a la interfaz de tu Control Plane en Kong Konnect (sección *Data Plane Nodes*) y verifica que tu nodo (Data Plane) aparezca conectado en estado **"In Sync"**.
2. **Conectividad CLI decK:** Configura las variables en tu terminal y realiza un comando `ping` para validar que `decK` se conecta exitosamente:
   ```bash
   export KONNECT_TOKEN="<tu-token-pat>"
   export CONTROL_PLANE_NAME="cp-local-tu.nombre" # Reemplaza con tu nombre exacto
   deck gateway ping --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
   ```
   *El comando debe completarse correctamente, lo que confirma que las credenciales son válidas y tienes conexión a Konnect.*

Si el Data Plane está en Sync y el comando inicial responde correctamente, ¡estás listo para empezar!

---

## Fase 0: Diseño, Pruebas y Mocking de API (Insomnia)

Antes de exponer la API a través del Gateway, es fundamental elaborarla y simular su comportamiento. En esta actividad el equipo de QA es protagonista.
1. **Importar la Colección:** Haz clic en **Import** e importa la colección `workshop-assets/insomnia/Insomnia_Workspace.json`. Esto cargará los requests probatorios en la sección "Collections" de la barra lateral.
2. **Importar el Diseño OpenAPI:** Vuelve a hacer clic en **Import** en el home, y ahora importa el archivo `workshop-assets/insomnia/flights-api.yaml`. Esto aparecerá como un nuevo archivo bajo la sección **"Documents"**. Ábrelo. Notarás que la pestaña inferior "Ruleset" te marca **1 Error** en rojo (porque en la ruta `/customers` falta la propiedad obligatoria `description` dentro de la respuesta `200`).
   * **Ejercicio de QA:** Para solucionar este error estructural, ubícate en el bloque de código YAML de `/customers`, justo debajo de la línea que dice `'200':`. Inserta una nueva línea respetando la indentación, y escribe `description: "Lista de clientes"`. El error desaparecerá instantáneamente validando tu especificación al 100%.
3. **Levantar el Simulador (Mock Server):** Dado que estás en un "Local Vault", Insomnia requiere un "Self Hosted Mock". Esto significa que usaremos nuestro servidor Mock confiable para que responda las peticiones automáticas. En tu terminal, en la raíz del proyecto, ejecuta este comando para levantar Prism en el puerto `8080`:
```bash
docker rm -f prism_mock || true
docker run -d --platform linux/amd64 --name prism_mock -p 8080:4010 -v $(pwd)/workshop-assets/insomnia/flights-api.yaml:/tmp/flights-api.yaml stoplight/prism:5 mock -h 0.0.0.0 /tmp/flights-api.yaml -m false
```
* **Prueba el Mock:** Comprueba que el servidor esté respondiendo correctamente ejecutando `curl http://localhost:8080/flights` en tu terminal. ¡Deberías ver un JSON con datos de vuelos inmediatamente!
*(Opcionalmente, en la sección Mock de Insomnia puedes configurar el "Self Hosted URL" apuntando a esta misma `http://localhost:8080` para tenerlo documentado)*.
4. **Baterías de Pruebas:** Tanto en los pre-scripts de los requests como en la pestaña "Runner", hemos configurado validaciones de ciclo de vida. ¡Las usaremos al final del laboratorio!

---

## 2. Ejecución del Laboratorio con `deck`

A continuación gestionaremos las políticas aplicando los archivos `kong.yaml` ubicados dentro de cada carpeta de escenario.

*Nota: Asegúrate de mantener activas en tu sesión de terminal las variables exportadas `KONNECT_TOKEN` y `CONTROL_PLANE_NAME` definidas en el paso de validación.*

### Ejercicio 0: Preparación y Limpieza del entorno
**Qué queremos lograr:** Asegurarnos de que el Control Plane esté en un estado completamente en blanco, eliminando cualquier configuración previa, e iniciar la infraestructura de observabilidad necesaria para el laboratorio.

**Cómo se hace:**
Primero, levantamos los contenedores del stack LGTM (Grafana, Jaeger, Prometheus, Loki) y el servidor mock de backend (Prism):
```bash
# Stack de observabilidad
cd workshop-assets/observabilidad && docker compose up -d && cd ..

# Backend mock (Prism) en puerto 8080
docker rm -f prism_mock 2>/dev/null || true
docker run -d --platform linux/amd64 --name prism_mock -p 8080:4010 \
  -v $(pwd)/insomnia/flights-api.yaml:/tmp/flights-api.yaml \
  stoplight/prism:5 mock -h 0.0.0.0 /tmp/flights-api.yaml -m false
```

Luego, limpiamos el entorno de Konnect y establecemos la base de observabilidad (escenario 0):
```bash
deck gateway reset --force --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
deck gateway apply 00-setup/kong.yaml --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
```

**Impacto (Validación):**
Llama a cualquier ruta en el puerto 8000:
```bash
curl -i http://localhost:8000/
# Deberías ver: 404 Not Found ({"message":"no Route matched with those values"})
```

### Ejercicio 1: Base de Enrutamiento y Observabilidad (01-base.yaml)
**Qué queremos mostrar:** La creación de rutas directas hacia el backend mock (Prism), encapsulando la red local y exponiéndola de forma segura, al mismo tiempo que los plugins globales de observabilidad registran silenciosamente toda la actividad.

**Cómo se hace:**
```bash
deck gateway ping --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
deck gateway apply 01-base/kong.yaml --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
```

**Impacto (Validación y Generación de Tráfico):**
Llama a la ruta expuesta en el puerto 8000 generando tráfico de forma sostenida para recolectar telemetría temprana:
```bash
echo "Generando tráfico inicial..."
for i in {1..20}; do curl -s -o /dev/null -w "Code: %{http_code}\n" http://localhost:8000/flights; sleep 0.2; done
```
*Este comando inyectará múltiples peticiones. En los próximos ejercicios las peticiones generarán rechazos (401, 403, 429) que también enriquecerán nuestros dashboards.*

### Ejercicio 2: Control de exposición por método (02-metodos.yaml)
**Qué queremos mostrar:** Reducir la superficie de ataque aceptando únicamente solicitudes de tipo GET en una ruta.

**Cómo se hace:**
```bash
deck gateway apply 02-metodos/kong.yaml --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
```

**Impacto (Validación):**
```bash
curl -i http://localhost:8000/flights
# Retorna 200 OK

curl -i -X POST http://localhost:8000/flights
# Retorna 404 No Route Matched
```

### Ejercicio 3: Autenticación con Key Auth y Consumers (03-seguridad-auth.yaml)
**Qué queremos mostrar:** Centralizar la autenticación a nivel de gateway sin modificar el código del backend, identificando a diferentes "Consumidores".

**Cómo se hace:**
```bash
deck gateway apply 03-seguridad-auth/kong.yaml --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
```

**Impacto (Validación):**
```bash
# Sin llave rechaza la petición:
curl -i http://localhost:8000/flights
# Retorna 401 Unauthorized

# Con la llave externa, permite el paso:
curl -i http://localhost:8000/flights -H "apikey: my-external-key"
# Retorna 200 OK
```

### Ejercicio 4: Autorización con ACL (04-seguridad-acl.yaml)
**Qué queremos mostrar:** Además de saber quién eres (autenticación), el gateway valida si tienes permiso (grupo ACL `external` o `internal`) para acceder a un recurso específico.

**Cómo se hace:**
```bash
deck gateway apply 04-seguridad-acl/kong.yaml --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
```

**Impacto (Validación):**
```bash
# El usuario externo tiene acceso a /flights
curl -i http://localhost:8000/flights -H "apikey: my-external-key"
# Retorna 200 OK

# El usuario interno es rechazado
curl -i http://localhost:8000/flights -H "apikey: my-internal-key"
# Retorna 403 Forbidden
```

### Ejercicio 5: Rate Limiting diferenciado (05-rate-limiting.yaml)
**Qué queremos mostrar:** Proteger el backend de abuso con cuotas diferenciadas por consumidor: el usuario externo tiene un límite de 5 requests/minuto (demostrable), el interno de 3 (pero adicionalmente bloqueado por ACL al intentar acceder a `/flights`).

**Cómo se hace:**
```bash
deck gateway apply 05-rate-limiting/kong.yaml --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
```

**Impacto (Validación):**
Ejecuta el siguiente ciclo para el consumidor **externo** (límite de 5 requests/minuto):
```bash
for i in {1..7}; do curl -s -o /dev/null -w "Code: %{http_code}\n" http://localhost:8000/flights -H "apikey: my-external-key"; done
```
*Observarás que los primeros 5 requests devuelven `200 OK` y a partir del 6º cambian a `429 Too Many Requests`.*

### Ejercicio 6: Transformaciones y Observabilidad (06-transformaciones.yaml)
**Qué queremos mostrar:** Enriquecer las peticiones hacia el backend y las respuestas al cliente alterando cabeceras al vuelo, e inyectar un ID de Correlación para facilitar el troubleshooting moderno.

**Cómo se hace:**
```bash
deck gateway apply 06-transformaciones/kong.yaml --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
```

**Impacto (Validación):**
Prueba la ruta de flights, revisando las cabeceras de respuesta (Response Transformers):
```bash
curl -i http://localhost:8000/flights -H "apikey: my-external-key"
```
*Deberás observar una cabecera nueva `x-perceptiva: true` y la aparición de `X-Kong-Request-Id` o `x-correlation-id` generado por el gateway.*

### Ejercicio 7: Exploración de la Observabilidad Integral Remota
**Qué queremos mostrar:** Visualizar cómo las configuraciones globales que inyectamos silenciosamente en el Ejercicio 0 (File Log, Prometheus y OpenTelemetry) en combinación con agentes nativos de recolección (Promtail y Loki), han estado capturando la telemetría de todo el laboratorio en tiempo real.

**Entendiendo la captura pasiva:**
1. **Logs en File System:** Usando la variable previamente definida, inspecciona los logs directamente en el contenedor con:
   ```bash
   docker exec -it $KONNECT_DATA_PLANE_NAME tail -f /tmp/kong-access.log
   ```
   *(Presiona `Ctrl+C` para salir).*
2. **Trazas y Logs Centralizados:** Los envíos están automatizados por red hacia el stack LGTM.
3. **Métricas en Prometheus:** Kong tiene expuesto el endpoint en `http://localhost:8100/metrics`.

**Cómo visualizar los resultados en el Stack Externo (Grafana, Jaeger, Loki, Prometheus):**
Como ya iniciamos el stack integrado en el Ejercicio 0, tan solo debes asegurarte de haber generado el tráfico de prueba y luego:
1. **Jaeger (Trazas):** Entra a [http://localhost:16686](http://localhost:16686). En el panel principal, en "Service", selecciona `kong-api-gateway` y haz clic en "Find Traces". Podrás ver el ciclo de vida completo de cada petición red y los tiempos de latencia del upstream gracias al plugin OpenTelemetry.
2. **Grafana (Logs y Métricas):** Entra a [http://localhost:3000](http://localhost:3000) (Usuario/Clave: `admin` / `admin`).
    - Ve a la sección **Explore** (ícono de brújula en el panel izquierdo).
    - Selecciona el Data Source **Loki** en la esquina superior izquierda.
    - En el panel de consulta (pestaña **Builder**), bajo **Label filters**, selecciona el label `job`, y en `Select value` escoge `kong-gateway`.
    - Haz clic en el botón azul **Run query** arriba a la derecha. ¡Deberás ver un listado con todos los logs JSON de tus peticiones!
    - Mude el Data Source a **Prometheus** para graficar métricas en tiempo real explorando métricas como `kong_http_status` o `kong_latency_bucket`.

---

### Ejercicio 08: Ejecución Automática de Batería de Pruebas en Insomnia
**Qué queremos mostrar:** Ejecutar los Unit Tests automáticos programados por el equipo de QA, validando empíricamente que el Gateway de Kong protege la infraestructura en cada escenario exigido.

**Configurando los Tests (Ejemplo de Script):**
Para que Runner funcione y no te diga *"No test was detected"*, se deben parametrizar *scripts de comprobación*. Ve a cualquiera de tus peticiones, abre la pestaña **Scripts** -> **After Response** (o "Tests") e inserta código validativo. Por ejemplo, para tu `GET Flights (No Auth)`:

```javascript
insomnia.test("El Gateway debe bloquear la petición exitosamente", () => {
    insomnia.expect(insomnia.response.code).to.eql(401);
    const body = insomnia.response.json();
    insomnia.expect(body.message).to.eql("No API key found in request");
});
```

**Cómo se ejecuta la Colección completa:**
1. En la barra lateral izquierda, haz clic en el nombre de tu colección/carpeta (`Kong QA Workshop`) para desplegar sus opciones.
2. Selecciona **Run**, lo cual abrirá la vista **Collection Runner**.
3. Asegúrate de que el Entorno seleccionado arriba a la izquierda siga siendo `Base Environment`.
4. Haz clic en el botón morado **Run**.
5. ¡Éxito! Verás cómo automáticamente Insomnia dispara las APIs y comprobará todas las aserciones, pintando el reporte con colores verdes (Passed) al confirmar que las reglas del Gateway de Kong responden tal cual espera el script de QA.

**Alternativa CI/CD: Ejecución por consola (inso CLI)**
Para demostrarle al equipo de Arquitectura o DevOps cómo estas políticas de Kong se integran nativamente en pipelines automatizados (GitHub Actions, GitLab CI, etc.), puedes correr la misma suite sin necesidad de la interfaz gráfica usando el CLI oficial:

```bash
inso run test "Bateria Pruebas Escenario 08" \
  -e "Base Environment" \
  -w insomnia/Insomnia_Workspace.json
```
Visualizarás un hermoso reporte en la terminal donde las tres pruebas validan el flujo en verde en solo unos milisegundos.

---

### Ejercicio 09: APIOps (El ciclo de vida del API Automatizado)
**Qué queremos mostrar:** Demostrar cómo los equipos de Platform Engineering y DevOps pueden automatizar el ciclo de vida completo de un API usando diseño *Contract-First* y pruebas CI/CD usando el ecosistema de Kong (`inso` + `decK`).

**Cómo se hace:**
1. En tu terminal (Mac/Linux), abre la carpeta de este repositorio.
2. Ejecuta el emulador de Integración Continua que preparamos para el taller:
   ```bash
   ./09-apiops/emulador-ci.sh
   ```
3. Observa la salida en la consola. El pipeline ejecuta de forma totalmente autónoma las **7 fases** del ciclo DevOps de APIs:

   | Fase | Herramienta | Propósito |
   |------|-------------|-----------|
   | FASE 1 | `inso lint spec` | Design-First QA — valida el contrato OpenAPI antes de tocar la infra |
   | FASE 2 | `deck file openapi2kong` | Specs-to-Kong — compila el diseño a configuración declarativa |
   | FASE 3 | `deck file validate` | Valida el YAML de infraestructura generado |
   | FASE 4 | `deck gateway diff` | Drift Detection — qué cambiaría en producción |
   | FASE 5 | `inso run test` | Testes de comportamiento sobre el gateway activo |
   | FASE 6 ★ | Konnect API Catalog | Publica la spec OpenAPI en el catálogo interno de la organización |
   | FASE 7 ★ | Konnect Dev Portal | Publica la API para consumidores externos con auto-registro |

   > ★ Las fases 6 y 7 requieren `KONNECT_TOKEN` y un Dev Portal activo en `cloud.konghq.com/portals`.

4. Muestra a la audiencia el archivo `workshop-assets/09-apiops/github-actions-demo.yml` para evidenciar cómo este script emulador se transcribe exactamente igual en componentes reales de Github Actions listos para usarse.

---

### Ejercicio 10: Clustering, Escalabilidad y Auto-Descubrimiento
**Qué queremos mostrar:** Demostrar la robustez e inmutabilidad de la Infraestructura de Kong. Lanzaremos un nuevo Data Plane (nodo) simulando un evento de "Auto-Scaling" (escalado por alto tráfico) y demostraremos que obtiene su configuración automáticamente y que hereda toda la observabilidad del Control Plane sin intervención manual.

**Cómo se hace:**
1. Abre una terminal y lanza el **segundo Data Plane** (que se enlazará al mismo clúster en la nube pero en un puerto destino diferente `8010` para no chocar con el nodo original local):
   ```bash
   ./10-clustering/dp2.sh
   ```
   *(Este comando usará los mismos certificados mTLS pero levantará un contenedor llamado `kong_local_dp2`).*
2. **Prueba la Replicación Base:** Envía una petición probando el nuevo puerto `8010`:
   ```bash
   curl -i http://localhost:8010/flights
   ```
   Recibirás un error `401 Unauthorized`. ¡Inmediatamente heredó las reglas de seguridad sin que tocaras un solo archivo de configuración!
3. **Prueba de Observabilidad:** 
   - Entra a **Jaeger** (http://localhost:16686). Busca trazas frescas. Verás que las peticiones al puerto `8010` ya enviaron sus trazas de OpenTelemetry.
   - Entra a **Grafana** -> **Explore** -> **Loki** (http://localhost:3000). Busca `{job="kong-gateway"}` y verás registros frescos JSON escupidos por tu nuevo nodo secundario.

---

## 3. Cierre y Revisión en Konnect Analytics
Ingresa a **Kong Konnect -> Analytics -> Explorer**. 
Filtra por los últimos 15 o 30 minutos y podrás observar todo el tráfico generado de manera agregada:
- Cantidad de solicitudes.
- Desglose de errores (401, 403, 404, 429).
- Métricas de latencia de Kong vs Latencia del backend, evidenciando el mínimo impacto del Gateway y la visibilidad universal obtenida sin tocar una línea de código del backend.

---

## Anexo: Anatomía de la Observabilidad en Kong

A continuación, analizaremos los datos en crudo que Kong genera para entender la riqueza del contexto que aporta a la observabilidad.

### 1. Ejemplo de un Log de Acceso (JSON)
Este es el registro en crudo que Kong graba usando el plugin `file-log` (y que Promtail envía a Loki). Está formateado en JSON estructurado, lo cual lo hace perfecto para ser indexado y consultado en Grafana:

```json
{
  "request": {
    "method": "GET",
    "uri": "/flights",
    "url": "http://localhost:8000/flights",
    "headers": {
      "user-agent": "curl/8.7.1",
      "x-consumer-username": "App-External",
      "x-correlation-id": "76dd9197-afbc-489f-a75c-ca02ac99b027",
      "traceparent": "00-3a226e00876e9040af48d73dcb05105a-15e8880040e4b6fc-00"
    }
  },
  "response": {
    "status": 200,
    "size": 814,
    "headers": {
      "x-kong-upstream-latency": "4",
      "x-kong-proxy-latency": "1"
    }
  },
  "latencies": {
    "proxy": 4,
    "kong": 1,
    "request": 5
  },
  "consumer": {
    "username": "App-External"
  },
  "trace_id": {
    "w3c": "3a226e00876e9040af48d73dcb05105a"
  }
}
```

**Explicación de sus partes:**
- **`request` & `response`**: Contienen toda la información L7 (HTTP) interceptada. Destacan el `x-consumer-username` (identidad de quien hace la llamada tras evaluar el API Key) y el `x-correlation-id` inyectado por nuestro plugin de transformación.
- **`latencies`**: Desglosa matemáticamente el tiempo de vida de la petición. `kong` (1ms) es el tiempo que Kong procesó plugins, `proxy` (4ms) es el tiempo de espera hacia el backend. El total (`request`) fue de 5ms.
- **`trace_id`**: Contiene el ID del estándar W3C (`3a226e0087...`), que Kong envía idéntico hacia OTLP (Jaeger), garantizando que este log se pueda cruzar 1:1 con la traza de red gráfica.

### 2. Anatomía de una Traza (OpenTelemetry)
Al explorar en Jaeger asumiendo ese mismo exacto `trace_id` (`3a226e00876e9040af48d73dcb05105a`), observarás un grafo temporal (diagrama de Gantt) estructurado en "Spans" (Intervalos).

Debajo del capó, lo que Kong Gateway le despachó al recolector OTLP de Jaeger fue un bloque JSON idéntico a este, correlacionándose visualmente con el log:

```json
{
  "traceID": "3a226e00876e9040af48d73dcb05105a",
  "spans": [
    {
      "spanID": "94429ad510ac4134",
      "operationName": "kong",
      "duration": 5000,
      "tags": [
        { "key": "http.status_code", "type": "int64", "value": 200 },
        { "key": "http.url", "type": "string", "value": "http://localhost/flights" },
        { "key": "span.kind", "type": "string", "value": "server" }
      ]
    },
    {
      "spanID": "7bb591986f4c57a0",
      "operationName": "kong.access.plugin.key-auth",
      "duration": 570,
      "tags": [ { "key": "span.kind", "type": "string", "value": "internal" } ]
    },
    {
      "spanID": "a1ca33afbccca6fc",
      "operationName": "kong.balancer",
      "duration": 4000,
      "tags": [
        { "key": "peer.service", "type": "string", "value": "flights" },
        { "key": "net.peer.name", "type": "string", "value": "host.docker.internal" }
      ]
    }
  ],
  "processes": {
    "p1": { "serviceName": "kong-api-gateway" }
  }
}
```

Cada traza de Kong se divide típicamente en estos componentes visuales en la interfaz gráfica:
1. **Span Principal (Root):** Representa el ciclo completo desde que el cliente tocó Kong hasta que Kong devolvió la respuesta de vuelta (`duration`: ~5ms).
2. **Span de Gateway (Kong Process):** Un segmento que evidencia cuánto tiempo invirtió Kong ejecutando plugins (`key-auth`, `correlation-id`, etc.) antes de retransmitir (ej: 1ms).
3. **Span de Upstream:** El segmento (`kong.balancer`) que muestra la conexión de red y el procesamiento final en el backend host (ej: 4ms). 

Gracias a esto, si un servicio tarda 5 segundos en responder, la traza y el log mostrarán inmediatamente si el bloqueo provino de una política compleja dentro del Gateway o si fue lentitud pura del microservicio, eliminando todo el "finger-pointing" (disputas) entre equipos de desarrollo y arquitectura.
