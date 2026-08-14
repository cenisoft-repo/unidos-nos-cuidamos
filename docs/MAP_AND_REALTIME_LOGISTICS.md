# Mapa real y logística en tiempo real

## Motores cartográficos

La aplicación usa dos motores para que el mapa sea real incluso cuando WebGL no está disponible:

1. MapLibre GL + estilo vectorial OpenFreeMap, con datos de OpenStreetMap.
2. Leaflet + teselas raster OpenStreetMap como modo compatible.

Los endpoints se configuran con `NEXT_PUBLIC_MAP_STYLE_URL` y `NEXT_PUBLIC_RASTER_TILE_URL`. La atribución permanece visible en ambos modos.

## Proyección pública segura

`public_logistics_projections` es una tabla derivada y protegida por RLS. Los triggers sincronizan:

- centros activos desde `inventory_locations`, usando únicamente nombre, zona y coordenadas públicas;
- despachos desde `shipments` y `shipment_items`, derivando el origen del centro y el destino de `public_need_projections`.

La RPC `public_logistics_map(event_id)` no devuelve dirección exacta, transportador, custodio, evidencia ni datos personales. La tabla está añadida a `supabase_realtime`, por lo que el navegador refresca puntos, líneas y estados cuando cambia una operación publicable.

## Qué significa “tiempo real”

Es actualización de eventos operacionales —despachado, en tránsito, entregado o validado—, no rastreo GPS. La línea del mapa conecta origen y destino aproximados y no pretende ser una ruta vial calculada.

Para incorporar GPS o rutas reales se requieren, antes de G2: proveedor identificado, contrato/licencia, retención, consentimiento/base legal, precisión por rol, geocercas, frecuencia, presupuesto, gestión de incidentes y DPIA aprobada.

## Claves externas

No se debe inferir el proveedor a partir del texto de una credencial. Antes de usar una clave se documentan proveedor y producto, se rota después de haber sido compartida, se restringe por dominio/origen y cuota, y se almacena únicamente en `.env.local` o un gestor de secretos. Nunca se agrega a `NEXT_PUBLIC_*` si concede acceso privilegiado.
