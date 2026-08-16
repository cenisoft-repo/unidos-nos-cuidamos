# Estado pre-deploy · Unidos Nos Cuidamos

Fecha: 2026-08-16 · Loop de validación, limpieza y productización.
Entorno de verificación: build de producción (`next build` + `next start`) contra Supabase local con base reiniciada.

---

## Resultado de la verificación

| Suite | Resultado |
|---|---|
| Preflight local | ok (URLs loopback, sin service_role, sin enlaces remotos) |
| Lint (`eslint .`) | PASS |
| TypeScript (`tsc --noEmit`) | PASS |
| Unitarias (Vitest) | **21/21** (13 previas + 8 nuevas) |
| pgTAP (`supabase test db`) | **94/94** |
| RLS (`verify-rls.mjs`) | PASS |
| Concurrencia (`verify-intake-concurrency.mjs`) | PASS |
| Build de producción | PASS (14 rutas) |
| E2E Playwright (chromium + móvil) | **24/24** |

P0 abiertos: **0** · P1 abiertos: **0**

---

## Iteraciones ejecutadas

### ITERACIÓN 01 — KPI fabricado en portada · P1
**Problema:** `src/app/page.tsx` mostraba `dashboard?.units_delivered ?? 113`. Si la métrica faltaba, publicaba el número 113 (valor del seed) como cifra real, contradiciendo el principio de falla segura del propio producto y el LOOP §18.
**Cambio:** helper `metricValue()`; sin corte, se muestra `—`. Ninguna cifra se inventa.
**Prueba:** portada verificada en navegador con datos reales (5 / 153 / 9).
**Resultado:** PASS.

### ITERACIÓN 02 — Divulgación de datos no productivos por entorno · P1
**Problema:** los avisos de "sandbox / simulación / datos sintéticos" estaban incrustados en 8 superficies. Quitarlos sin más habría presentado registros ficticios de donaciones y movimientos financieros como genuinos ante directivos, aliados y entidades.
**Cambio:** `src/lib/environment.ts` con `NEXT_PUBLIC_APP_ENV`. La divulgación se concentra en **un** indicador y desaparece automáticamente al declarar `production`. El valor por defecto es `sandbox`: la advertencia solo se oculta por declaración explícita, nunca por omisión.
**Prueba:** `src/lib/environment.test.ts` — production oculta, sandbox advierte, valor desconocido falla de forma segura.
**Resultado:** PASS.

### ITERACIÓN 03 — Fuga de errores de Postgres a la interfaz · P1
**Problema:** 14 puntos hacían `setError(actionError.message)`, mostrando texto interno de Postgres/PostgREST (nombres de tabla, políticas RLS, códigos PGRST) a la persona usuaria. Contradice LOOP §35.
**Cambio:** `src/lib/user-errors.ts`. Los mensajes de regla de negocio (`errcode 22023`, ya redactados para la persona usuaria) se muestran tal cual; cualquier otra falla se traduce a un mensaje operativo y el detalle técnico queda solo en consola.
**Prueba:** `src/lib/user-errors.test.ts` (5 casos) + E2E de moderación de teléfonos.
**Resultado:** PASS.

### ITERACIÓN 04 — Credenciales precargadas en el ingreso · P0
**Problema:** `/ingresar` venía con `defaultValue` de correo y contraseña de administrador, y listaba las cinco cuentas con su contraseña común en el HTML.
**Cambio:** campos vacíos siempre; la lista de cuentas de práctica solo existe fuera de producción. Se retiró la contraseña de la interfaz.
**Prueba:** E2E de ingreso por rol (admin, bodega, aliado) sigue en verde.
**Resultado:** PASS.

### ITERACIÓN 05 — Ruido explicativo y jerga técnica · P3
**Problema:** la interfaz explicaba su propia construcción ("Supabase RLS aísla…", "Eventos Supabase", "proyección separada", "fórmulas inyectadas", "fixture", "append-only", "Validamos el formato y evitamos duplicados", bloque "Falla segura").
**Cambio:** reescritura a lenguaje operativo. La funcionalidad permanece; la explicación se movió a documentación. También se neutralizaron las notas de auditoría que escribían la palabra "sandbox" en la base de datos y los marcadores de posición que pedían datos ficticios.
**Resultado:** PASS.

### ITERACIÓN 06 — Mapa sin WebGL colgado en carga · P2
**Problema:** sin WebGL el mapa quedaba indefinidamente en "Preparando cartografía real…".
**Cambio:** comprobación previa de WebGL; si no está disponible se pasa directamente al mapa alternativo sin esperar el temporizador.
**Resultado:** PASS.

---

## Hallazgos abiertos (no bloqueantes de este loop)

| # | Hallazgo | Prioridad | Nota |
|---|---|---|---|
| 1 | **Sin `Content-Security-Policy`.** El resto de cabeceras está completo (nosniff, DENY, COOP, CORP, Referrer-Policy, Permissions-Policy, HSTS en producción). | P2 | Requiere validar contra MapLibre, Leaflet, Suparealtime e inline styles antes de activarla. No se implementó a ciegas para no romper el mapa. |
| 2 | **Las pruebas E2E mutan los datos sembrados.** El despacho demo pasa de "En tránsito" a "Validada" y la suite deja de ser reproducible. | P2 | Ejecutar `npm run db:reset` antes de `test:e2e`. Conviene añadirlo al script `verify` y al workflow de CI. |
| 3 | **Modo serial:** un fallo bloquea las 18 pruebas restantes y oculta el estado real del resto. | P3 | Considerar aislamiento por prueba o `fullyParallel` con datos propios. |
| 4 | **En modo dev las pruebas compiten con la hidratación** y pueden fallar por carrera (formularios que se vacían). La suite es fiable contra el build de producción. | P3 | Preferir `next build` + `next start` para E2E, como ya se hizo aquí. |
| 5 | **Adaptador de pago sandbox.** Persisten `reconcile_sandbox_payment` y el prefijo `SANDBOX-` en la referencia (contrato del backend, no interfaz). | P1 para G2 | Bloqueo ya registrado: exige proveedor financiero real. |
| 6 | **Gate E (visual) parcial.** Se unificó el lenguaje y se eliminó el ruido, pero no se ejecutó una pasada completa de sistema visual (tipografía, spacing, sombras, iconografía). | P3 | Pendiente si se busca cierre total del gate. |

---

## Gates

| Gate | Estado |
|---|---|
| A · Core (build, API, DB, auth) | **PASS** |
| B · Aportes (crear, consultar, actualizar, historial) | **PASS** |
| C · Privacidad (API pública vs interna, RBAC, sin filtraciones) | **PASS** |
| D · UX (navegación, formularios, feedback, errores, responsive) | **PASS** |
| E · Visual (sistema, consistencia, jerarquía, iconografía) | **PARCIAL** — ver hallazgo 6 |
| F · Producción (env, secretos, migraciones, logs, seguridad, build) | **PARCIAL** — ver hallazgo 1 (CSP) |

---

## Human Gate

**No se ha ejecutado ningún despliegue ni operación remota.** No existe enlace activo a Supabase remoto ni a Vercel; `preflight:local` lo confirma.

Antes de desplegar se requiere:

1. Declarar `NEXT_PUBLIC_APP_ENV=production` **solo** cuando la instancia sirva información operativa real. Mientras la base contenga datos de práctica, debe permanecer en `sandbox`.
2. Resolver los bloqueos ya registrados en `docs/STATUS.md` y firmar `docs/PILOT_APPROVAL_PACKET.md`: operador jurídico, DPIA y políticas aprobadas, proveedor financiero real, WAF y monitoreo externo, respaldos remotos/PITR, autorización de marca.
3. Decidir sobre la CSP (hallazgo 1).
4. Ejecutar `npm run preflight:deploy` (verifica; no despliega).

---

## Respaldo

Antes de reiniciar la base para obtener pruebas deterministas se generó un respaldo verificado en:

`.local-backups/20260816-100211/`

Contiene el estado previo, incluida la necesidad creada manualmente "Requerimos colchonetas para un albergue · Quibdó, Chocó". Restauración documentada en `docs/OPERATIONAL_READINESS.md` (`npm run db:restore:local`).
