# Estado pre-deploy · Unidos Nos Cuidamos

Fecha: 2026-08-16 · Loop de validación, limpieza y productización.
Entorno de verificación: build de producción (`next build` + `next start`) contra Supabase local con base reiniciada.

---

## Resultado de la verificación

| Suite | Resultado |
|---|---|
| Preflight local | **FAILED** — el sandbox quedó enlazado a Vercel (ver hallazgo 0) |
| Lint (`eslint .`) | PASS |
| TypeScript (`tsc --noEmit`) | PASS |
| Unitarias (Vitest) | **26/26** (13 previas + 13 nuevas) |
| pgTAP (`supabase test db`) | **94/94** |
| RLS (`verify-rls.mjs`) | PASS |
| Concurrencia (`verify-intake-concurrency.mjs`) | PASS |
| Build de producción | PASS (14 rutas) |
| E2E Playwright (chromium + móvil) | **24/24** (con CSP aplicada) |
| Accesibilidad (`audit:a11y`) | 0 problemas reales; 3 falsos positivos documentados |
| Métricas visuales (`audit:visual`) | 30 combinaciones, sin desbordes ni regresiones |

P0 abiertos: **0** en el código · **1 de proceso** (hallazgo 0, enlace a Vercel).

La suite E2E solo es reproducible tras `npm run db:reset`; ya quedó encadenado en el script `verify`.

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

### ITERACIÓN 07 — El middleware nunca se ejecutaba · P1
**Problema:** `proxy.ts` estaba en la raíz del repositorio, pero la aplicación vive en `src/`. Next.js busca ese archivo junto a `app/`, de modo que `middleware-manifest.json` quedaba vacío y **el refresco de sesión de Supabase nunca corrió**.
**Cambio:** `git mv proxy.ts src/proxy.ts`. El build ahora reporta `ƒ Proxy (Middleware)`.
**Resultado:** PASS.

### ITERACIÓN 08 — Content-Security-Policy con nonce · P2
**Problema:** era la única cabecera de seguridad ausente.
**Cambio:** `src/lib/security-headers.ts` genera la política y `src/proxy.ts` la emite con un nonce por petición. `script-src` usa `'nonce-…' 'strict-dynamic'` sin `'unsafe-inline'` ni `'unsafe-eval'` fuera de desarrollo. Los orígenes de Supabase y de cartografía se derivan de la configuración, no se escriben a mano. `sw.js` queda fuera del middleware para no pagar una consulta de autenticación por descarga.
**Prueba:** 5 pruebas unitarias de la política + suite E2E completa (24/24) con la política aplicada + verificación en Chromium real: hidratación, mapa, service worker y **cero errores de consola**.
**Resultado:** PASS.

### ITERACIÓN 09 — Sistema visual: radios y elevación · P3
**Problema:** medido sobre la hoja de estilos, había **16 radios distintos, 26 tamaños de fuente, 28 valores de `gap` y 17 sombras** — incluidas dos sombras idénticas escritas de forma diferente. Cada pantalla estaba diseñada por separado (LOOP §26).
**Cambio:** escala de tokens en `:root` (radio, espaciado, elevación, anillos de foco). Radios y sombras migrados por completo: **0 radios en píxeles sueltos**, 17 sombras → 7 tokens. Se conservó la asimetría decorativa del hero.
**Prueba:** `scripts/visual-metrics.mjs` compara 30 combinaciones (6 páginas × 5 anchos: 1440/1280/1024/768/390) antes y después → **sin regresiones, sin desbordes horizontales**.
**Resultado:** PASS.

### ITERACIÓN 10 — Accesibilidad comprobable · P3
**Problema:** el contraste y la estructura de encabezados no estaban verificados.
**Cambio:** `scripts/accessibility-audit.mjs` mide contraste, etiquetas de formulario, texto alternativo, orden de encabezados y botones sin nombre. Corregidos: contraste insuficiente en la nota de exportación (4.36 → sobre 4.5 con `--muted-strong`), salto de nivel de encabezado en transparencia (`h1 → h3`) mediante un `h2` accesible pero no visible, y el crédito fotográfico de 9px → 11px.
**Prueba:** problemas reales 2 → **0**. Los 3 restantes son falsos positivos documentados: texto sobre el degradado de la fotografía, que el script no puede medir porque el fondo no es un nodo del DOM.
**Resultado:** PASS.

---

## Hallazgos abiertos

| # | Hallazgo | Prioridad | Nota |
|---|---|---|---|
| 0 | **El sandbox local quedó enlazado a Vercel.** Existe `.vercel/project.json` (proyecto `unidos-nos-cuidamos`) y `.env.local` recibió un `VERCEL_OIDC_TOKEN`. No lo generó este loop. | **P0 de proceso** | `.env.local` y `.vercel/` **sí** están en `.gitignore`, por lo que el token no se versiona. `preflight:local` lo detecta y sale con código 1, de modo que `npm run verify` se detiene. Contradice `docs/STATUS.md` ("no existe enlace vigente a Vercel"): hay que confirmar si el enlace fue intencional y autorizado, o retirarlo con `rm -rf .vercel` y rotar el token. |
| 3 | **Modo serial:** un fallo bloquea las 18 pruebas restantes y oculta el estado real del resto. | P3 | Considerar aislamiento por prueba o `fullyParallel` con datos propios. |
| 4 | **En modo dev las pruebas compiten con la hidratación** y pueden fallar por carrera (formularios que se vacían). La suite es fiable contra el build de producción. | P3 | Preferir `next build` + `next start` para E2E, como ya se hizo aquí. |
| 5 | **Adaptador de pago sandbox.** Persisten `reconcile_sandbox_payment` y el prefijo `SANDBOX-` en la referencia (contrato del backend, no interfaz). | P1 para G2 | Bloqueo ya registrado: exige proveedor financiero real. |
| 6 | **Escala tipográfica y de espaciado sin unificar.** Radios, sombras y anillos ya usan tokens; siguen dispersos **26 tamaños de fuente y 28 valores de `gap`**. | P3 | Los tokens `--space-*` ya existen. Las diferencias de 1–2 px son imperceptibles y no justifican el riesgo; las perceptibles (35/40/45/54/70 px) exigen criterio visual humano, que no puede ejercerse sin ver la pantalla. Recomendado hacerlo con revisión de diseño delante. |
| 7 | **Los dos proyectos de Playwright comparten una sola base.** `chromium` y `mobile` ejecutan las mismas pruebas mutantes contra los mismos datos sembrados; una de cada cuatro corridas completas falló en "aporte económico" por contención (pasa aislada). | P3 | Aislar los datos por proyecto, o que las pruebas mutantes creen su propio aporte en lugar de consumir el sembrado. |
| 8 | **La iconografía ya es consistente** (solo Lucide, sin emojis ni mezclas) y el responsive no desborda en 1440/1280/1024/768/390. Sin acción. | — | Verificado con `npm run audit:visual`. |

---

## Gates

| Gate | Estado |
|---|---|
| A · Core (build, API, DB, auth) | **PASS** |
| B · Aportes (crear, consultar, actualizar, historial) | **PASS** |
| C · Privacidad (API pública vs interna, RBAC, sin filtraciones) | **PASS** |
| D · UX (navegación, formularios, feedback, errores, responsive) | **PASS** |
| E · Visual (sistema, consistencia, jerarquía, iconografía) | **PARCIAL** — tokens, radios, elevación, jerarquía, iconografía, responsive y accesibilidad verificados; tipografía y espaciado pendientes (hallazgo 6) |
| F · Producción (env, secretos, migraciones, logs, seguridad, build) | **PASS en código** — cabeceras completas con CSP; bloqueado por el hallazgo 0 |

---

## Human Gate

**No se ha ejecutado ningún despliegue ni operación remota.** No existe enlace activo a Supabase remoto ni a Vercel; `preflight:local` lo confirma.

Antes de desplegar se requiere:

0. **Resolver el enlace a Vercel (hallazgo 0).** `preflight:local` falla mientras exista. Confirmar si fue intencional; si no, retirar `.vercel/` y rotar el `VERCEL_OIDC_TOKEN` de `.env.local`.
1. Declarar `NEXT_PUBLIC_APP_ENV=production` **solo** cuando la instancia sirva información operativa real. Mientras la base contenga datos de práctica, debe permanecer en `sandbox`.
2. Resolver los bloqueos ya registrados en `docs/STATUS.md` y firmar `docs/PILOT_APPROVAL_PACKET.md`: operador jurídico, DPIA y políticas aprobadas, proveedor financiero real, WAF y monitoreo externo, respaldos remotos/PITR, autorización de marca.
3. Decidir sobre la CSP (hallazgo 1).
4. Ejecutar `npm run preflight:deploy` (verifica; no despliega).

---

## Respaldo

Antes de reiniciar la base para obtener pruebas deterministas se generó un respaldo verificado en:

`.local-backups/20260816-100211/`

Contiene el estado previo, incluida la necesidad creada manualmente "Requerimos colchonetas para un albergue · Quibdó, Chocó". Restauración documentada en `docs/OPERATIONAL_READINESS.md` (`npm run db:restore:local`).
