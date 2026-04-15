# Bookings API

> Gestión del ciclo completo de reservas de vuelos

---

## Descripción General

La **Bookings API** es el servicio responsable de gestionar las reservas de vuelos de los pasajeros. Permite registrar nuevas reservas, consultar el estado de reservas existentes y procesar cancelaciones o modificaciones.

Todas las operaciones se realizan de forma síncrona y los cambios se propagan en tiempo real al sistema de gestión de inventario de vuelos.

---

## Autenticación

Esta API requiere una **API Key** válida emitida por el Developer Portal:

```http
GET /bookings HTTP/1.1
Host: api.workshop.demo
apikey: <tu-api-key>
```

> ⚠️ Solo consumers del grupo `external` tienen acceso a este endpoint. Consumers internos sin el grupo correcto recibirán `403 Forbidden`.

---

## Endpoints

### `GET /bookings`

Retorna la lista de reservas activas registradas en el sistema.

**Parámetros de query opcionales:**

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `status` | string | Filtrar por `confirmed`, `pending` o `cancelled` |
| `flight_id` | string | Filtrar reservas de un vuelo específico (ej: `FL-2045`) |
| `passenger_name` | string | Búsqueda parcial por nombre del pasajero |

**Ejemplo de solicitud:**

```bash
curl -X GET "https://api.workshop.demo/bookings?status=confirmed" \
  -H "apikey: my-external-key"
```

**Ejemplo de respuesta `200 OK`:**

```json
[
  {
    "id": "b7e2c1d4-9f3a-4e8b-a012-654321fedcba",
    "flight_id": "FL-2045",
    "passenger_name": "Ana García",
    "seat": "14C",
    "class": "economy",
    "status": "confirmed",
    "created_at": "2026-04-01T09:15:00Z"
  },
  {
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "flight_id": "FL-2045",
    "passenger_name": "Pedro Silva",
    "seat": "22A",
    "class": "business",
    "status": "pending",
    "created_at": "2026-04-02T14:22:00Z"
  }
]
```

### `POST /bookings`

Crea una nueva reserva de vuelo para un pasajero.

**Body (application/json):**

```json
{
  "flight_id": "FL-2045",
  "passenger_name": "Carlos Mendes",
  "seat_preference": "window",
  "class": "economy",
  "contact_email": "carlos@example.com"
}
```

**Respuesta `201 Created`:**

```json
{
  "id": "f3a1b2c4-9d8e-4f5a-b6c7-d8e9f0a1b2c3",
  "status": "pending",
  "confirmation_code": "KW-2026-9842",
  "estimated_confirmation": "2026-05-01T08:00:00Z"
}
```

---

## Códigos de Respuesta

| Código | Significado |
|--------|-------------|
| `200` | Éxito — lista de reservas retornada |
| `201` | Reserva creada exitosamente |
| `400` | Solicitud inválida — verifica los campos requeridos |
| `401` | No autorizado — API Key inválida o ausente |
| `403` | Prohibido — tu consumer group no tiene acceso |
| `404` | Reserva no encontrada |
| `409` | Conflicto — asiento ya ocupado |
| `429` | Rate limit excedido |

---

## Rate Limiting

| Consumer Group | Límite |
|----------------|--------|
| `external` | 5 solicitudes/minuto |
| `internal` | 30 solicitudes/minuto |

---

## Políticas de Gateway Kong

La Bookings API está protegida por las siguientes políticas:

- **Autenticación**: `key-auth` — valida la API Key en el header
- **Autorización**: `acl` — restringe el acceso al grupo `external`
- **Rate Limiting**: límites por consumer group y ruta
- **Trazabilidad**: `correlation-id` + `opentelemetry` activos en todas las rutas

---

## Soporte

Contacta al equipo de Platform Engineering: **platform@workshop.demo**
