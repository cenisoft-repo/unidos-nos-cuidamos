# Estado actual

- Puerta/hito: G1 sandbox alcanzada para demostración controlada local/remota; G2/G3 bloqueadas.
- Último resultado comprobado: reset reproducible, 67 pruebas SQL, RLS de mapa/logística/tenant/funciones, 6 unitarias, 18 web, lint, typecheck y build verdes.
- Recorrido activo: experiencia amigable pública y operacional en sandbox; no hay regresiones P0/P1 conocidas.
- Próxima acción exacta: obtener operador y políticas aprobadas antes de diseñar el piloto G2.
- Bloqueos reales: operador, autoridad, DPIA, política de bienes/datos/evidencias, proveedor real, marcas e infraestructura externa.

## Delta último ciclo

- Cambios públicos: portada humana, catálogo “Hoy hace falta”, mapa cartográfico real, centros y despachos aproximados en vivo, métricas conciliadas, dashboard accesible y exportación Excel pública segura.
- Cambios de aporte: flujo accesible de cinco pasos, centro preferido, perfil del donante, destinación, beneficiarios declarados, canal de entrega, valor estimado por artículo, campos internos privados y ticket imprimible con QR sin PII.
- Cambios complementarios: categorías visuales en reporte, lanzador operativo por rol, MapLibre/OpenFreeMap con fallback cartográfico Leaflet/OpenStreetMap y recuperación de sesiones locales obsoletas tras un reset.
- Datos: migraciones hasta `202608140008_authenticated_donation_intake.sql`; proyección pública logística derivada, RLS, privilegios explícitos de funciones y Supabase Realtime.
- Pruebas ejecutadas: `npm run db:reset`, `npm run db:test`, `npm run verify`, `npm run test:e2e` e inspección visual en escritorio/móvil.
- Resultado: 67 SQL + 1 verificación RLS + 6 unitarias + 18 web; aplicación local sana y Supabase remoto sandbox migrado con fixtures sintéticos.

## Contexto que debe cargarse

- Archivos: `AGENTS.md`, este archivo, `docs/UX_MAP.md` y la sección activa de `docs/ai/PLAN.md`.
- Decisiones: ADR-001 a ADR-006 en `docs/DECISIONS.md`.
- Riesgos: R-001 a R-006 en `docs/RISK_REGISTER.md`.
