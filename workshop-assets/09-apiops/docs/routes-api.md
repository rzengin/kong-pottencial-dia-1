# Routes API

> Catálogo de rutas aéreas disponibles en la red de la aerolínea

---

## Descripción General

La **Routes API** expone el catálogo completo de rutas aéreas operadas por la plataforma. Una **ruta** define la conexión entre dos aeropuertos (origen → destino), incluyendo la distancia, duración estimada del vuelo, frecuencia de operación y restricciones vigentes.

Este servicio es utilizado por el motor de búsqueda de vuelos para filtrar disponibilidad y calcular opciones de conexión en itinerarios de múltiples escalas.

---

## Autenticación

Esta API requiere autenticación mediante **API Key**:

```http
GET /routes HTTP/1.1
Host: api.workshop.demo
apikey: <tu-api-key>
```

---

## Endpoints

### `GET /routes`

Retorna el listado completo de rutas disponibles en la red de la aerolínea.

**Parámetros de query opcionales:**

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `origin` | string | Código IATA del aeropuerto de origen (ej: `GRU`) |
| `destination` | string | Código IATA del aeropuerto de destino (ej: `JFK`) |
| `active` | boolean | `true` para mostrar solo rutas activas |
| `min_frequency` | integer | Frecuencia mínima de vuelos por semana |

**Ejemplo de solicitud:**

```bash
curl -X GET "https://api.workshop.demo/routes?origin=GRU&active=true" \
  -H "apikey: my-external-key"
```

**Ejemplo de respuesta `200 OK`:**

```json
[
  {
    "id": "RT-GRU-LIS",
    "origin": {
      "code": "GRU",
      "name": "Aeroporto Internacional de Guarulhos",
      "city": "São Paulo",
      "country": "BR"
    },
    "destination": {
      "code": "LIS",
      "name": "Aeroporto Humberto Delgado",
      "city": "Lisboa",
      "country": "PT"
    },
    "distance_km": 9475,
    "avg_duration_minutes": 660,
    "frequency_per_week": 7,
    "aircraft_types": ["Airbus A330-900", "Boeing 787-9"],
    "active": true
  },
  {
    "id": "RT-GRU-JFK",
    "origin": {
      "code": "GRU",
      "name": "Aeroporto Internacional de Guarulhos",
      "city": "São Paulo",
      "country": "BR"
    },
    "destination": {
      "code": "JFK",
      "name": "John F. Kennedy International Airport",
      "city": "New York",
      "country": "US"
    },
    "distance_km": 7661,
    "avg_duration_minutes": 570,
    "frequency_per_week": 14,
    "aircraft_types": ["Boeing 777-300ER"],
    "active": true
  }
]
```

### `GET /routes/{id}`

Retorna los detalles de una ruta específica por su identificador.

```bash
curl -X GET "https://api.workshop.demo/routes/RT-GRU-LIS" \
  -H "apikey: my-external-key"
```

### `GET /routes/connections`

Busca rutas con escalas entre dos ciudades cuando no existe vuelo directo.

**Query params requeridos:** `origin` + `destination`

```bash
curl -X GET "https://api.workshop.demo/routes/connections?origin=POA&destination=CDG" \
  -H "apikey: my-external-key"
```

---

## Códigos de Respuesta

| Código | Significado |
|--------|-------------|
| `200` | Éxito — lista de rutas retornada |
| `400` | Parámetros inválidos — verifica los códigos IATA |
| `401` | No autorizado — API Key inválida o ausente |
| `404` | Ruta no encontrada |
| `429` | Rate limit excedido |

---

## Codificación de Aeropuertos

Todos los aeropuertos se identifican con su código **IATA de 3 letras**. Algunos de los aeropuertos más frecuentes en la red:

| Código | Aeropuerto | Ciudad |
|--------|-----------|--------|
| `GRU` | Guarulhos International | São Paulo, BR |
| `LIS` | Humberto Delgado | Lisboa, PT |
| `JFK` | John F. Kennedy | New York, US |
| `MIA` | Miami International | Miami, US |
| `CDG` | Charles de Gaulle | París, FR |
| `MAD` | Adolfo Suárez Barajas | Madrid, ES |

---

## Cache de Rutas

Las respuestas de este endpoint son cacheadas a nivel del Kong Gateway durante **60 segundos**. Las actualizaciones al catálogo de rutas pueden tardar hasta 1 minuto en propagarse.

---

## Soporte

Contacta al equipo de Platform Engineering: **platform@workshop.demo**
