# Estado actual

- Puerta/hito: G1 local apta para demostración controlada de aportes en especie y económicos; G2/G3 bloqueadas.
- Último resultado comprobado: 14 migraciones, 94/94 SQL, RLS, concurrencia, 13/13 unitarias, 24/24 web/móvil, lint, typecheck, build, health, dashboards y Excel verdes.
- Recorrido activo: portal, aportes en especie/dinero, seguimiento, operación, tesorería, mapas, dashboards y exportaciones con datos sintéticos.
- Hallazgos: A15-001 a A15-008 cerrados para G1. G-015 conserva solo la capa WAF/Supabase remota; G-018 a G-020 cerradas localmente.
- Próxima acción exacta: conservar el entorno local y obtener autoridad/operador antes de enlazar proyectos remotos o avanzar a G2.
- Bloqueos reales: operador, autoridad, DPIA, política de aceptación, proveedor real, WAF/monitoreo externo, backups remotos/PITR, HIBP, marcas y enlaces Supabase/Vercel.

## Delta último ciclo

- Seguridad: migración `20260815224447_harden_local_operations.sql` agrega cuota atómica 5/10 min sin IP en claro; Auth bloquea altas libres, endurece contraseñas y acota sesiones.
- Observabilidad: logs JSON sin PII, hook de error, request ID, Server-Timing y salud no cacheable; cabeceras HTTP reforzadas, HSTS solo en producción.
- Recuperación: backup público sintético con manifiesto SHA-256; restore real desde migraciones + datos, 94 pgTAP y RTO 57,1 s.
- Operación: `npm run preflight:local` impide enlaces remotos accidentales; `npm run preflight:deploy` solo informa bloqueos y no muta servicios.
- Offline/UX: cola estricta sin PII, TTL/capacidad, búsqueda de recepción, etapas y compatibilidad de lote/necesidad.
- Entrega G2: CI y runbooks de incidente, datos, WAF y aprobación quedan listos para revisión humana.
- Evidencia verde: 94 SQL, RLS, concurrencia, 13 unitarias, 24 web/móvil y build.
- Remoto: no verificable porque no hay `supabase/.temp/project-ref` ni `.vercel/project.json`.
- Resultado: detalle en `docs/FUNCTIONAL_AUDIT_2026-08-15.md` y `docs/OPERATIONAL_READINESS.md`.

## Contexto que debe cargarse

- Archivos: `AGENTS.md`, este archivo, `docs/UX_MAP.md` y `docs/ai/PLAN.md`.
- Decisiones: ADR-001 a ADR-006 en `docs/DECISIONS.md`.
- Riesgos: `docs/RISK_REGISTER.md` y `docs/GAP_LEDGER.md`.
