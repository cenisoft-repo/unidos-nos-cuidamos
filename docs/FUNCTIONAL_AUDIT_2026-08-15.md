# Auditoría funcional integral · ciclo 2026-08-15

Alcance: aplicación Next.js y Supabase local con datos 100 % sintéticos. Esta auditoría no autoriza producción, datos vivos, recaudo, marcas institucionales ni despliegues. El proyecto no está enlazado actualmente a Supabase remoto ni a Vercel; por tanto, los resultados remotos anteriores no se consideran evidencia vigente en este ciclo.

## Veredicto

- Resultado posterior a la alineación: **G1 local apta para demostración controlada de aportes en especie y económicos, con datos sintéticos**.
- P0 abiertos: **0**.
- P1 abiertos: **0**. Los cuatro P1 detectados en la primera pasada quedaron cerrados en la migración `20260815200619_align_donation_flow.sql`.
- Las rutas en especie y económica funcionan de UI a ticket, revisión, operación, proyección pública, dashboard y Excel.
- El rate limiting transaccional local está implementado y probado; permanecen como condiciones de salida a piloto el WAF/rate limiting de borde, las aprobaciones humanas/institucionales y los enlaces remotos controlados.
- G2/G3 continúan bloqueadas.

## Historia auditada

Un aliado autenticado registra un aporte en `/donar`; el navegador llama una RPC transaccional de Supabase; operación revisa, recibe y entrega bienes o concilia dinero; únicamente las proyecciones autorizadas alimentan seguimiento, transparencia, mapas, dashboards y Excel.

## Evidencia reproducible

| Límite | Ejecución | Resultado |
|---|---|---|
| Infraestructura local | Docker Desktop + `npm run db:start` | Supabase API, PostgreSQL y Studio disponibles |
| Reconstrucción | `npm run db:reset` | 14 migraciones y seed sintético aplicados desde cero |
| Contratos PostgreSQL | `npm run db:test` | 94/94 pgTAP |
| Concurrencia real | `npm run test:concurrency` | 2 envíos simultáneos → 1 intake + 1 reintento, sin error |
| Calidad y build | `npm run verify` | preflight, lint, TypeScript, 13/13 unitarias, SQL, RLS, concurrencia, build y navegador |
| Navegador automatizado | `npm run test:e2e` con servidor propio en `127.0.0.1` | 24/24, escritorio y móvil; incluye conciliación monetaria, bodega, salud y cabeceras |
| Salud HTTP | `GET /api/health` | 200, `checks.database: connected`, `no-store`, request ID y Server-Timing |
| Recuperación | `npm run db:backup` + `scripts/restore-local.ps1` | checksums SHA-256, reconstrucción, restauración y 94 pgTAP; RTO local medido 57,1 s |
| Páginas públicas | `GET /` y `GET /transparencia` | 200 |
| Dependencias productivas | `npm audit --omit=dev` | 0 vulnerabilidades |
| Linter PostgreSQL | `supabase db lint --local --schema public` | 0 errores de esquema |
| Advisors locales | `npx supabase db advisors --local --type all` | 0 hallazgos de seguridad o rendimiento |
| Supabase/Vercel remoto | inspección de enlaces locales | No verificable: no existe `supabase/.temp/project-ref` ni `.vercel/project.json` |

La primera ejecución E2E reutilizó un servidor iniciado como `localhost`, mientras Playwright usa `127.0.0.1`. Next.js bloqueó los módulos de desarrollo por origen y las dos variantes del test de mapa fallaron antes de hidratar. Se detuvo ese servidor y se hizo una sola repetición con el comando definido en `playwright.config.ts`; el resultado limpio fue 18/18. El incidente es reproducible como configuración de arranque, no como defecto del mapa.

El navegador integrado no permitió recargar `127.0.0.1` por su política interna de URL. No se intentó eludir el control; la evidencia de navegador de este ciclo procede del Playwright del repositorio.

## Estado por frontera

| Frontera | Estado | Evidencia |
|---|---|---|
| UI pública y autenticación | Verde | portal, login, formulario, ticket QR, transparencia y Excel pasan E2E |
| Cliente → RPC de aporte | Verde | PostgreSQL replica el contrato obligatorio y las restricciones de catálogo |
| RPC → persistencia | Verde | inserción atómica, huella de payload y prueba concurrente real |
| Aporte en especie → entrega | Verde | recorrido SQL y navegador completo probado |
| Aporte económico → conciliación | Verde | cola segura, fondo verificado, transacción vinculada, recibo y publicación conciliada |
| Entrega → dashboard | Verde | proyección por `donation_item_id`; cantidades permanecen junto a su unidad |
| Privacidad pública | Verde | matriz visible, RLS, RPC sin PII y allowlists de dashboard/Excel |
| Remoto | No verificado | no hay enlace local a proyectos Supabase/Vercel |

## Hallazgos

### A15-001 · P1 · La RPC acepta cargas que el formulario rechaza

**Estado: cerrado.** La última firma ejecutable valida identidad privada, contacto, atribución, estado declarado, contexto, centro, catálogos, descripción, cantidad, unidad, condición y coherencia por tipo. pgTAP incluye rechazo directo de un payload que omite el nombre.

**Evidencia dinámica:** dentro de una transacción revertida se invocó `submit_donation_intake` con nombre vacío, `contact_private` como arreglo y un artículo con categoría y descripción vacías. PostgreSQL creó un intake `pending_verification`.

**Causa:** `src/components/donation-intake-form.tsx` valida nombre, correo, categoría y descripción, mientras la función base de `supabase/migrations/202608130001_initial_schema.sql` solo valida autenticación, rol, idempotencia, cantidad/unidad, monto y condición restringida. Los wrappers posteriores validan centro y contexto, pero no duplican el contrato completo.

**Cierre requerido:** concentrar el contrato autoritativo en PostgreSQL: forma de contactos, longitudes, correo, catálogo de unidades/categorías, descripción, atribución no anónima y coherencia por tipo. Mantener validación cliente para UX y añadir pruebas negativas directas de RPC.

### A15-002 · P1 · La idempotencia falla bajo concurrencia real

**Estado: cerrado.** La inserción usa `ON CONFLICT DO NOTHING RETURNING`, guarda una huella SHA-256 del payload y rechaza la reutilización conflictiva. `npm run test:concurrency` comprueba dos conexiones simultáneas.

**Evidencia dinámica:** dos sesiones enviaron simultáneamente el mismo `organization_id` e `idempotency_key`. La primera devolvió el intake; la segunda terminó con `duplicate key value violates unique constraint donation_intakes_organization_id_idempotency_key_key`.

**Causa:** la función ejecuta `SELECT` y después `INSERT`. La restricción única preserva integridad, pero la segunda sesión no recupera el resultado ya creado.

**Cierre requerido:** `INSERT ... ON CONFLICT DO NOTHING RETURNING`, recuperación posterior de la fila y comparación de un hash del payload para distinguir reintento legítimo de reutilización conflictiva. Añadir prueba automatizada con dos conexiones.

### A15-003 · P1 · El aporte económico no completa el ciclo

**Estado: cerrado.** `reconcile_money_donation` enlaza donación, fondo y transacción; obtiene el monto desde el intake aprobado, emite recibo y crea la proyección pública únicamente después de conciliar. Existe prueba SQL y Playwright de extremo a extremo.

**Evidencia dinámica:** un intake monetario de COP 250.000 fue aprobado dentro de una transacción revertida. Resultado: `donation_status = promised`, `operational_items = 0`, `public_rows = 0`.

**Causa:** `review_donation_intake` crea una donación y copia `donation_intake_items`; un aporte monetario no tiene ítems. `reconcile_sandbox_payment` no referencia intake/donación y la única creación operacional de `public_donation_projections` ocurre al validar una entrega física.

**Cierre requerido:** enlazar intake monetario aprobado → fondo/transacción → conciliación → proyección pública con `reconciled_amount`, manteniendo proveedor y referencia privada, idempotencia, segregación de funciones y auditoría.

### A15-004 · P1 · Una proyección por donación puede sumar unidades incompatibles

**Estado: cerrado.** La proyección en especie es única por `donation_item_id`; el dashboard cuenta registros por categoría y presenta cada cantidad con su unidad. La proyección monetaria usa una restricción parcial separada.

**Evidencia estructural:** `public_donation_projections.donation_id` es único. `validate_delivery` resuelve conflictos sumando `verified_quantity`, pero conserva categoría y unidad de la primera fila.

**Impacto:** si una donación entrega artículos con unidades distintas, el dashboard puede sumar cantidades no comparables bajo una sola etiqueta.

**Cierre requerido:** proyectar por `donation_item_id` o por tupla donación/categoría/unidad/destino. Prohibir agregaciones de unidades distintas y añadir prueba con al menos dos artículos y dos unidades.

### A15-005 · P2 · Donante y persona reportante están semánticamente mezclados

**Estado: cerrado para G1.** La UI distingue nombre del donante, responsable que registra, organización derivada de membresía y estado declarado seleccionable, sin alterar el estado operacional verificado.

El formulario etiqueta `donor_name_private` como “Nombre de quien reporta”. El flujo de referencia separa organización gestora, donante real, responsable y contacto. Además, `declared_status` siempre se envía como `comprometida`.

**Cierre requerido:** campos separados para identidad privada del donante y persona que diligencia; estado declarado seleccionable (`comprometido`, `en tránsito`, `entregado por validar`) sin confundirlo con estado operacional verificado.

### A15-006 · P2 · Falta contrato visible y probado de campos públicos/privados

**Estado: cerrado para G1.** La confirmación muestra bloques “Se podrá publicar tras verificar” y “Permanece privado”; dashboard y Excel solo consumen proyecciones con allowlist.

La proyección pública y los Excel usan allowlists explícitas y no exponen PII conocida. Sin embargo, la revisión final solo muestra contacto privado y atribución pública, no la clasificación completa. Tampoco existe una prueba de contrato que recorra todos los campos privados y falle si cualquiera aparece en RPC, HTML o Excel público.

**Cierre requerido:** resumen “Se podrá publicar / Solo equipo autorizado”, indicadores `required`/`aria-required`, errores por campo y prueba exhaustiva de no filtración.

### A15-007 · P2 · Protección antiabuso pendiente para entrada anónima

**Estado: cerrado en aplicación local; parcial para G2.** La firma pública anterior fue revocada, el formulario usa un honeypot y PostgreSQL limita atómicamente cinco reportes exitosos por origen/evento cada diez minutos. El origen se resume con SHA-256 y la tabla de contadores no es legible ni escribible por `anon`. El WAF/rate limiting de borde continúa pendiente antes de cualquier piloto remoto.

El aporte requiere membresía, por lo que no necesita abrirse a `anon`. El reporte ciudadano sí es anónimo y no tiene CAPTCHA/honeypot ni rate limiting de aplicación habilitado. Si se desea un aporte “sin cuenta”, debe usarse invitación o magic link de un solo uso, nunca una apertura directa de la RPC privada.

### A15-008 · P3 · Cinco conjuntos de políticas RLS permisivas duplicadas

**Estado: cerrado.** Las políticas equivalentes se consolidaron y el advisor local devuelve `No issues found`, sin cambiar los recorridos de RLS.

El advisor local reportó políticas `SELECT` múltiples para `allocations`, `donation_intake_items`, `donation_intakes`, `emergency_events` e `intake_verification_decisions`. No constituye una exposición: son advertencias de rendimiento porque PostgreSQL evalúa más de una política permisiva.

**Cierre requerido:** consolidar predicados equivalentes sin ampliar filas visibles y repetir RLS/advisors.

## Controles confirmados

- Todas las tablas operacionales expuestas conservan RLS.
- Las mutaciones críticas usan RPC con actor y verificación de rol.
- Las funciones `SECURITY DEFINER` fijan `search_path` y no conservan `EXECUTE` para `PUBLIC`.
- `anon` no puede registrar aportes privados ni ejecutar mutaciones operativas.
- Organización y evento se derivan o validan contra membresía; el test RLS bloquea IDOR y escalamiento.
- Auditoría append-only bloquea actualización y borrado.
- El cliente no usa `service_role` ni `user_metadata` para autorización.
- La publicación está separada del intake; una promesa no aparece como impacto.
- Los códigos públicos aleatorios evitan enumeración secuencial.
- Excel público y operativo fallan cerrados y neutralizan fórmulas.

## Cambios de plataforma revisados

- El cambio de Supabase que deja de exponer automáticamente nuevas tablas a Data/GraphQL API refuerza la necesidad de mantener `GRANT` y RLS explícitos; no corrige por sí solo ninguno de los hallazgos.
- La transición Kong → Envoy solo afecta self-hosting personalizado; el entorno local usa Supabase CLI sin `kong.yml` propio.
- Las migraciones no fijan versiones de extensiones, por lo que la deprecación de version pinning no las afecta.
- TypeScript 5.9.3 cubre el requisito futuro de `supabase-js` 5+.

## Orden de cierre ejecutado

1. A15-001 y A15-002: contrato RPC completo e idempotencia concurrente.
2. A15-003: recorrido monetario conciliado de extremo a extremo.
3. A15-004: granularidad segura para dashboards y Excel.
4. A15-005 y A15-006: semántica donante/reportante y visualización público/privado.
5. A15-007 y A15-008: antiabuso y optimización RLS.
6. Restablecer enlaces controlados a Supabase/Vercel y ejecutar auditoría remota sin desplegar datos reales.

## Puerta de salida

A15-001 a A15-008 están cerrados para el alcance local y la demostración puede cubrir ambos tipos de aporte. Esto no autoriza piloto, producción ni despliegue: siguen pendientes operador, autoridad, DPIA, política de aceptación, proveedor real, WAF de borde, protección de contraseñas filtradas, marcas y enlaces remotos verificables.
