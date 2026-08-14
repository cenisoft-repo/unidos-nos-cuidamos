# Registro de decisiones

## ADR-001 · 2026-08-13 · Supabase como backend transaccional

Decisión: usar Supabase local (PostgreSQL 17, Auth, Storage y Realtime) con migraciones versionadas, RLS y funciones SQL transaccionales. Next.js App Router/TypeScript será PWA y BFF cuando sea necesario.

Motivo: cubre base relacional, geoespacial, autenticación, almacenamiento privado y desarrollo reproducible con Docker, reduciendo piezas operativas sin renunciar a invariantes de datos.

Consecuencia: lógica crítica vive en PostgreSQL/RPC; el cliente nunca recibe `service_role`. Una futura cola robusta/observabilidad administrada deberá validarse antes de piloto.

## ADR-002 · 2026-08-13 · Sandbox estricto y proyecciones públicas

Decisión: usar exclusivamente datos sintéticos, proveedor financiero simulado y vistas/RPC públicas con lista explícita de campos. Evidencia privada en bucket no público.

Motivo: no existe autorización de operador, tratamiento, marcas, recaudo, migración o despliegue.

Consecuencia: G0/G1 pueden avanzar; G2/G3 permanecen bloqueadas hasta aprobación humana.

## ADR-003 · 2026-08-13 · Interfaz operativa de calma

Decisión: jerarquía sobria, alto contraste, listas equivalentes al mapa, estados textuales además del color, rojo solo para riesgo crítico y movimiento reducido.

Motivo: operadores y ciudadanía actuarán bajo presión, en móvil y con conectividad limitada.

## ADR-004 · 2026-08-14 · Centro territorial local y privacidad geoespacial

Decisión: usar MapLibre GL JS con una base cartográfica local de Natural Earth y puntos aproximados servidos por una RPC PostGIS `security invoker`. La proyección pública participa en Supabase Realtime bajo su RLS existente.

Motivo: ofrecer zoom, agrupación, intensidad territorial y actualización en vivo sin llaves propietarias ni dependencia de un proveedor de teselas. PostGIS permite encuadres indexados a medida que crezca el volumen.

Consecuencia: el mapa público nunca recibe direcciones o rutas operacionales; solo renderiza coordenadas ya aprobadas en `public_need_projections`. Una futura cartografía detallada deberá incluir licencia, caché y evaluación de conectividad antes del piloto.

## ADR-005 · 2026-08-14 · Cartografía real dual y logística aproximada

Decisión: sustituir la silueta Natural Earth de ADR-004 por MapLibre/OpenFreeMap y añadir Leaflet/OpenStreetMap cuando WebGL no esté disponible. Centros y despachos se publican desde `public_logistics_projections`, derivada por triggers y disponible en Realtime bajo RLS.

Motivo: una cartografía útil necesita calles y topónimos reales incluso en navegadores limitados, sin convertir el mapa público en GPS ni exponer la operación.

Consecuencia: la base cartográfica depende de servicios externos sin SLA para este sandbox y conserva atribución. Los endpoints son configurables. Antes de G2 se deberá escoger un proveedor con contrato/cuota o infraestructura propia; las claves no se infieren, no se versionan y no se exponen si son privilegiadas. La línea de despacho solo representa origen-destino aproximado.
