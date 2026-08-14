# Puerta Cero · Acta de preparación

Fecha: 2026-08-13 · Alcance: repositorio local vacío y especificación V3.0.

## Cinco rondas

1. Evidencia/legado: no hay producto, snapshot ni PII en el repositorio. El sistema vivo no fue tocado; migración queda como playbook y fixtures adversariales.
2. Producto/operación: actores, estados, superficies, RACI y ocho E2E están cubiertos por la constitución y la matriz inicial.
3. Seguridad/privacidad/fraude: controles de diseño definidos: RLS, proyección pública, contenido monetario bloqueado, Storage privado, segregación, idempotencia y auditoría.
4. Arquitectura/operabilidad: Supabase local + Next.js PWA decidido; migraciones y reset reproducible son la base de recuperación sandbox.
5. Testabilidad/red team: cada riesgo crítico tiene prueba SQL, unidad o E2E prevista; servicios externos quedan detrás de adaptadores sandbox.

## Veredicto

- P0 abiertos de especificación: 0.
- P1 abiertos de especificación: 0.
- P2: seis, con responsable/decisión en `docs/GAP_LEDGER.md`.
- Puerta: G0 aprobada exclusivamente para desarrollo local/sandbox.

No se afirma que los riesgos del producto vivo estén contenidos ni que exista preparación para piloto/producción.

## Revalidación G1 local · 2026-08-14

- Reset completo aplica cinco migraciones y seed de Auth/datos sintéticos.
- Escenarios A–H: 26 afirmaciones E2E SQL; total pgTAP 37/37.
- RLS: anonimato público, aislamiento de tenant y elevación de privilegio bloqueada.
- Web: 5/5 Playwright; unitarias 4/4; lint, typecheck y build verdes.
- QA visual: portada escritorio/móvil; sin overflow en 320, 375, 768, 1024 y 1440 px.
- Lint del esquema `public`: cero hallazgos. Avisos del lint general pertenecen a funciones de la extensión PostGIS administrada.

Veredicto: G1 local apta para demostración controlada. No autoriza G2/G3.
