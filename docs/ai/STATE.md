# Estado actual

- Puerta/hito: G1 local alcanzada para demostración controlada; G2/G3 bloqueadas.
- Último resultado comprobado: reset reproducible, 65 pruebas SQL, RLS de mapa/logística/tenant, 6 unitarias, 18 web, lint, typecheck y build verdes.
- Recorrido activo: experiencia amigable pública y operacional en sandbox; no hay regresiones P0/P1 conocidas.
- Próxima acción exacta: obtener operador y políticas aprobadas antes de diseñar el piloto G2.
- Bloqueos reales: operador, autoridad, DPIA, política de bienes/datos/evidencias, proveedor real, marcas e infraestructura externa.

## Delta último ciclo

- Cambios públicos: portada humana, catálogo “Hoy hace falta”, mapa cartográfico real, centros y despachos aproximados en vivo, métricas conciliadas, dashboard accesible y exportación Excel pública segura.
- Cambios de aporte: flujo accesible de cinco pasos, centro preferido, perfil del donante, destinación, beneficiarios declarados, canal de entrega, valor estimado por artículo, campos internos privados y ticket imprimible con QR sin PII.
- Cambios complementarios: categorías visuales en reporte, lanzador operativo por rol, MapLibre/OpenFreeMap con fallback cartográfico Leaflet/OpenStreetMap y recuperación de sesiones locales obsoletas tras un reset.
- Datos: migraciones `202608140004_friendly_ux.sql`, `202608140005_reporting_analytics.sql` y `202608140006_realtime_logistics_map.sql`; proyección pública logística derivada, RLS y Supabase Realtime.
- Pruebas ejecutadas: `npm run db:reset`, `npm run db:test`, `npm run verify`, `npm run test:e2e` e inspección visual en escritorio/móvil.
- Resultado: 65 SQL + 1 verificación RLS + 6 unitarias + 18 web; aplicación sana en `http://127.0.0.1:3000` y Studio en `http://127.0.0.1:54323`.

## Contexto que debe cargarse

- Archivos: `AGENTS.md`, este archivo, `docs/UX_MAP.md` y la sección activa de `docs/ai/PLAN.md`.
- Decisiones: ADR-001 a ADR-003 en `docs/DECISIONS.md`.
- Riesgos: R-001 a R-006 en `docs/RISK_REGISTER.md`.
