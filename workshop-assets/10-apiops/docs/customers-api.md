# Customers API

> Gestión de perfiles y datos de clientes de la plataforma de aviación

---

## Descripción General

La **Customers API** es el servicio de identidad y perfil de pasajeros de la plataforma. Centraliza la información de los clientes registrados, incluyendo datos personales, historial de vuelos, preferencias de asiento y membresías de programas de fidelidad.

Esta API es consumida principalmente por los servicios de Bookings y Flights para validar la identidad del pasajero durante el proceso de reserva.

---

## Autenticación

Esta API requiere autenticación mediante **API Key**:

```http
GET /customers HTTP/1.1
Host: api.workshop.demo
apikey: <tu-api-key>
```

> ℹ️ Los endpoints de lectura (`GET`) son accesibles por consumers `external`. Los endpoints de escritura (`POST`, `PATCH`) están reservados para consumers `internal`.

---

## Endpoints

### `GET /customers`

Retorna la lista de clientes registrados en la plataforma.

**Parámetros de query opcionales:**

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `name` | string | Búsqueda parcial por nombre o apellido |
| `email` | string | Búsqueda exacta por email |
| `membership` | string | Filtrar por nivel: `standard`, `gold`, `platinum` |
| `page` | integer | Número de página (paginación, default: 1) |
| `limit` | integer | Registros por página (max: 100, default: 20) |

**Ejemplo de solicitud:**

```bash
curl -X GET "https://api.workshop.demo/customers?membership=gold&limit=10" \
  -H "apikey: my-external-key"
```

**Ejemplo de respuesta `200 OK`:**

```json
{
  "data": [
    {
      "id": "CUST-00142",
      "name": "María Fernández",
      "email": "maria.fernandez@example.com",
      "nationality": "BR",
      "membership_level": "gold",
      "total_flights": 47,
      "created_at": "2021-03-15T10:00:00Z"
    },
    {
      "id": "CUST-00289",
      "name": "João Alves",
      "email": "joao.alves@example.com",
      "nationality": "BR",
      "membership_level": "gold",
      "total_flights": 31,
      "created_at": "2022-07-20T08:30:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 10,
    "total": 284
  }
}
```

### `GET /customers/{id}`

Retorna el perfil detallado de un cliente específico.

```bash
curl -X GET "https://api.workshop.demo/customers/CUST-00142" \
  -H "apikey: my-external-key"
```

### `POST /customers`

Registra un nuevo cliente en la plataforma (**requiere consumer `internal`**).

```json
{
  "name": "Carlos Russo",
  "email": "carlos.russo@example.com",
  "document_type": "passport",
  "document_number": "BR123456789",
  "nationality": "BR",
  "date_of_birth": "1985-06-15"
}
```

---

## Códigos de Respuesta

| Código | Significado |
|--------|-------------|
| `200` | Éxito — lista o perfil de cliente retornado |
| `201` | Cliente registrado exitosamente |
| `400` | Solicitud inválida — datos faltantes o mal formateados |
| `401` | No autorizado — API Key inválida o ausente |
| `403` | Prohibido — permisos insuficientes para esta operación |
| `404` | Cliente no encontrado |
| `409` | Conflicto — ya existe un cliente con ese email o documento |

---

## Datos Sensibles y Privacidad

La Customers API maneja datos personales bajo las regulaciones de la **LGPD (Lei Geral de Proteção de Dados)**. Los campos `document_number` y `date_of_birth` son cifrados en reposo y enmascarados en los logs:

```
document_number: "BR****6789"  (en respuestas de listing)
document_number: "BR123456789" (solo en GET por ID con permiso interno)
```

---

## Soporte

Contacta al equipo de Platform Engineering: **platform@workshop.demo**
