# Desarrollo local

1. Inicia Docker Desktop.
2. Ejecuta `npm install` y `npm run db:start`.
3. Ejecuta `npm run db:status -- -o env` y crea `.env.local` con la URL y la clave pública local.
4. Ejecuta `npm run db:reset` y `npm run dev`.
5. Abre la app en `http://localhost:3000` y Studio en `http://127.0.0.1:54323`.

El backend local no tiene TLS ni controles perimetrales de producción. No lo expongas a Internet.

## Cartografía

- Con WebGL, MapLibre usa `NEXT_PUBLIC_MAP_STYLE_URL` y por defecto carga el estilo real `https://tiles.openfreemap.org/styles/liberty`.
- Sin WebGL, Leaflet usa `NEXT_PUBLIC_RASTER_TILE_URL` y por defecto carga teselas `https://tile.openstreetmap.org/{z}/{x}/{y}.png`.
- Ambas capas conservan atribución visible. No se permite precarga masiva ni descarga offline de teselas públicas.
- Centros y despachos proceden de `public_logistics_map`; Supabase Realtime notifica cambios de la proyección protegida.
- Una clave comercial debe identificarse por proveedor, restringirse por origen/cuota y permanecer fuera de Git antes de sustituir estos endpoints.

## Credenciales sintéticas

Contraseña común: `RutaSolidaria2026!`

| Correo | Recorrido principal |
|---|---|
| `admin@rutasolidaria.local` | mando, verificación, auditoría y demostración integral |
| `aliado@rutasolidaria.local` | intake de aportes |
| `bodega@rutasolidaria.local` | recepción, inventario y logística |
| `solicita@rutasolidaria.local` | solicitud de gasto |
| `aprueba@rutasolidaria.local` | conciliación, aprobación y pago sandbox |

Rutas: `/operaciones`, `/operaciones/bodega` y `/operaciones/tesoreria`.

Para detener: `npm run db:stop`. Para reconstruir datos sintéticos: `npm run db:reset` (destructivo solo para la base local del proyecto).
