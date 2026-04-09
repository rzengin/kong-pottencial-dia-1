# Flights API

> Servicio central de inventario de vuelos de la plataforma de aviación

---

## Descripción General

La **Flights API** proporciona acceso en tiempo real al inventario de vuelos disponibles de la plataforma. Permite consultar vuelos, filtrar por origen y destino, y gestionar el ciclo de vida de vuelos en el sistema de scheduling.

Todo el tráfico hacia este servicio pasa a través del **Kong Gateway**, que aplica autenticación, control de acceso y rate limiting de forma transparente.

---

## Autenticación

Esta API requiere autenticación mediante **API Key**. Debes incluir tu clave en el header de cada solicitud:

```http
GET /flights HTTP/1.1
Host: api.workshop.demo
apikey: <tu-api-key>
```

Puedes obtener tu API Key registrándote en el **Kong Workshop Developer Portal**.

---

## Endpoints

### `GET /flights`

Retorna la lista de vuelos disponibles en el inventario actual.

**Parámetros de query opcionales:**

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `origin` | string | Código IATA del aeropuerto de origen (ej: `GRU`) |
| `destination` | string | Código IATA del aeropuerto de destino (ej: `LIS`) |
| `date` | string (date) | Fecha de salida en formato `YYYY-MM-DD` |

**Ejemplo de solicitud:**

```bash
curl -X GET "https://api.workshop.demo/flights?origin=GRU&destination=LIS" \
  -H "apikey: my-external-key"
```

**Ejemplo de respuesta `200 OK`:**

```json
[
  {
    "id": "FL-2045",
    "origin": "GRU",
    "destination": "LIS",
    "departure": "2026-05-10T14:30:00Z",
    "arrival": "2026-05-11T05:45:00Z",
    "aircraft": "Airbus A330-900",
    "available_seats": 23,
    "status": "on_time"
  }
]
```

### `POST /flights`

Registra un nuevo vuelo en el sistema de scheduling.

**Body (application/json):**

```json
{
  "origin": "GRU",
  "destination": "MIA",
  "departure": "2026-06-01T08:00:00Z",
  "aircraft": "Boeing 787-9"
}
```

---

## Códigos de Respuesta

| Código | Significado |
|--------|-------------|
| `200` | Éxito — lista de vuelos retornada |
| `201` | Vuelo creado exitosamente |
| `401` | No autorizado — API Key inválida o ausente |
| `403` | Prohibido — tu consumer group no tiene permiso (ACL) |
| `429` | Demasiadas solicitudes — espera antes de reintentar |
| `502` | Error del backend — servicio de vuelos no disponible |

---

## Rate Limiting

El acceso está limitado según el tipo de consumer:

| Consumer Group | Límite |
|----------------|--------|
| `external` | 5 solicitudes/minuto |
| `internal` | 30 solicitudes/minuto |

Cuando superas el límite, recibirás:
```http
HTTP/1.1 429 Too Many Requests
X-RateLimit-Remaining-Minute: 0
X-RateLimit-Limit-Minute: 5
```

---

## Headers de Observabilidad

Kong inyecta automáticamente los siguientes headers en cada solicitud:

| Header | Descripción |
|--------|-------------|
| `x-correlation-id` | UUID único por request para correlación de logs |
| `traceparent` | Header W3C Trace Context para OpenTelemetry |

---

## Soporte

Para soporte técnico, contacta al equipo de Platform Engineering: **platform@workshop.demo**
