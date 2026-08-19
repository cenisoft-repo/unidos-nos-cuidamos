# Estado actual

- Puerta/hito: G1 publicada como sandbox sintético interno; G2/G3 bloqueadas y no deben incorporarse operadores/PII antes de verificar en remoto el cierre local de `G-022`.
- Último resultado comprobado: **`npm run verify` verde de extremo a extremo** sobre `integration/superadmin-consolidacion` con **38 migraciones** — preflight, lint, typecheck, 47/47 unitarias, 372/372 pgTAP en cinco archivos, RLS (anonimato, tenant, escalamiento y alcance global), dos pruebas de concurrencia (aporte y reserva), build y 44/44 Playwright web/móvil. Además `audit:a11y` sin problemas en 14 superficies y `audit:visual` con 70 mediciones y cero desbordes.
- **Remoto al día: 38 migraciones, desplegadas el 2026-08-19 desde `main` en `e572801`.** Se aplicaron por el pooler de transacción (6543) con `--db-url`, porque el de sesión (5432) no es alcanzable desde el equipo de trabajo; el front se desplegó fusionando a `main` y dejando construir a la integración de Git, porque `vercel --prod` local falla con `fetch failed`. Comprobar siempre contra `supabase migration list`, no contra esta memoria.
- Recorrido activo local/remoto: portal, reportes, aportes en especie/dinero con catálogos versionados y centro compatible, QR de seguimiento, operación, tesorería, mapas, dashboards y exportaciones con datos sintéticos. El registro de aporte usa un recorrido adaptativo de cuatro pasos en especie y tres en dinero.
- Hallazgos: A15-001 a A15-008 cerrados para G1. Cerradas `G-021`, `G-023`, `G-024`, `G-025`, `G-028`, `G-029`, `G-030` (globalmente, verificada en producción), `G-032`, `G-033`, y en esta sesión `G-034` a `G-038` (las de la consolidación, ya ejecutadas), `G-040` (concurrencia de reserva), `G-041` (recepción con faltante) y `G-042` (SUPER_ADMIN y parametrización). `G-039` queda **cerrada solo en el modelo**: el autorregistro ya no escribe `verified`, pero la verificación documental depende de `G-003`. `G-022` tiene su migración aplicada en remoto; falta repetir allí el arnés. En la pista visual: `DQ-01`, `DQ-04` y `DQ-05` cerradas; `DQ-06` mitigada. **Abiertas:** `G-031` P2 (tensión de tenant), `G-026/G-027` P2, `G-043` P2 (antes/después solo en las tablas del parametrizador), `G-015` P2, `G-017` P2 y `G-001` a `G-008` P2 (decisiones humanas). `docs/GAP_LEDGER.md` y `docs/ai/DESIGN_QUALITY.md` son la fuente.
- Próxima acción exacta: habilitar el registro y la confirmación de correo en Auth desde el panel —sin eso `/registro` acepta el formulario y la activación nunca llega— y rotar la contraseña de la base, que quedó expuesta durante el despliegue. La autoridad global ya está concedida a `gestorti2@cenisoft.org` (2026-08-19), sobre una cuenta creada para ello y no sobre las sintéticas, cuya contraseña vive en el seed. Después, repetir el arnés de simulación remota para cerrar `G-022` globalmente.
- Bloqueos reales: operador, autoridad, DPIA, política de aceptación, proveedor real, WAF/monitoreo externo, backups remotos/PITR, HIBP, marcas y aprobación de piloto. El despliegue actual no autoriza datos reales, recaudo ni comunicación institucional.
- Entorno local: `preflight:local` pasa. Los enlaces remotos se regeneraron para el despliegue del 2026-08-17 y **se retiraron al terminar** —mientras están puestos, `preflight:local` falla y bloquea `npm run verify`, que es su propósito—; respaldados en `.local-backups/enlaces-remotos/`, se regeneran con `vercel link` y `supabase link`. El `.env.local` sigue apuntando al entorno de **entrega**; para correr la suite hay que conmutar a suite según `docs/REMOTE_SETUP_RUNBOOK.md`.
- Deuda documental conocida: `202608170007` lleva en su encabezado la frase «El remoto conserva 15 migraciones», falsa y ya aplicada en producción. No se edita: una migración aplicada es historia y este proyecto compensa en vez de reescribir. La corrección vive aquí, en `GAP_LEDGER.md` y en `STATUS.md`.

## Delta último ciclo

### Integración + SUPER_ADMIN · 2026-08-18

- **Merge de las dos líneas.** `entrega/despacho-trazabilidad-tesoreria` +
  `origin/claude/new-session-tflf63` en `integration/superadmin-consolidacion`. Las dos
  habían asignado en paralelo `G-028`…`G-033` a brechas distintas; se conservan las de la
  primera y las de la segunda se corren a `G-034`…`G-039`, con la equivalencia anotada en la
  cabecera de `GAP_LEDGER.md`. `verify-rls.mjs` quedó como una sola implementación que cubre
  los escenarios de ambas, no como una concatenación.
- **La consolidación nunca había corrido contra una base (`G-038`).** Ejecutarla destapó
  cuatro defectos reales; el grave es que `submit_donation_intake_v2`, al reimplementarse como
  función completa, perdió `assert_delivery_point_tenant` y con ello **reabría `G-022`, un P0**:
  un aliado volvía a poder enrutar su aporte al punto de otra organización. Lección: una
  migración que compila no es una migración que funciona, y un envoltorio que valida se pierde
  en silencio cuando alguien reescribe la función que envolvía.
- **SUPER_ADMIN es un valor más de `app_role` (`G-042`).** El alcance vive en las cuatro
  compuertas existentes (`is_org_member`, `has_any_role`, `has_event_role`,
  `has_location_scope`), cada una con su regla intacta más `or is_super_admin()`. Ninguna RPC
  de operación cambió: mayor alcance, misma lógica de negocio. El inventario sigue sin política
  de escritura directa y la prueba lo ejerce desde la API real.
- **Nadie escala su propio rol.** Tres capas: `memberships` sin política de escritura,
  `assign_membership_role` rechaza `super_admin` y rechaza actuar sobre uno mismo, y
  `grant_super_admin` está revocada para `anon` y `authenticated`. El rol se lee de la tabla,
  no de un claim.
- **Parametrización sin duplicar arquitectura.** Puntos con `manage_delivery_point`, catálogos
  con versiones `effective_from`/`effective_to`, alcance por bodega con `membership_locations`,
  auditoría con `audit_events`. Lo único añadido fue el antes/después en la auditoría, activado
  por tabla y excluyendo toda columna `_private` (`G-043` deja constancia del límite).
- **`G-039`: el modelo ya no confunde correo con organización.** El autorregistro escribe
  `email_verified`; llegar a `verified` exige `decide_organization_verification` con actor y
  sustento. La verificación documental sigue siendo decisión humana.
- **Dos garantías que nadie había ejercido (`G-040`, `G-041`).** Reserva concurrente 20+20
  contra 25 disponibles, y recepción con faltante donde el historial conserva lo despachado.
- **Limpieza:** se retira `submit_donation_intake_v2_catalogs_v1`, sin llamadores desde que la
  Fase 4 sustituyó el envoltorio.
- **Pasada de revisión sobre lo propio, y valió la pena.** Auditar los privilegios reales de
  cada función nueva destapó que `grant_super_admin` no era ejecutable por `service_role`: la
  vía auditada era código muerto mientras la escritura directa de la fila seguía abierta por
  los privilegios de arranque en frío. Lección repetible: cuando un comentario afirma quién
  puede ejecutar algo, comprobarlo contra `proacl`, no contra la intención. Y una `revoke all
  ... from public, anon, authenticated` no deja la función «solo para service_role»: la deja
  sin dueño.
- Evidencia: 359/359 pgTAP, RLS, dos concurrencias, 44/44 Playwright, a11y 0 problemas en 14
  superficies, visual 70 mediciones sin desbordes.

### Pista visual 2026-08-17 · DQ-01 cerrado, el instrumento ya sirve de puerta

- `audit:a11y` y `audit:visual` recorren **11 superficies** (6 públicas + 5
  consolas, cada una con el rol que la usa; `/operaciones` dos veces porque
  coordinación y aliado ven pantallas distintas). Rutas y sesión en
  `scripts/lib/rutas-auditadas.mjs`; solo contra loopback.
- **`audit:a11y` sale en 0 por primera vez.** Antes contaba como fallo el texto
  sobre fotografía o degradado —que no es calculable desde el DOM— y por eso
  nunca podía estar verde: un control que siempre falla no sirve de puerta. Ahora
  eso sale como `contrasteIndeterminado`, aparte y sin contar. Los 3 del pie de
  la portada se midieron a mano componiendo foto y velo: 5,54 · 5,99 · 6,10.
- **DQ-04, hallazgo real que solo apareció con sesión.** `--muted` daba 4,89:1
  sobre `--paper` pero 4,37 sobre `--mint`, el fondo de *todo* estado
  seleccionado; el fallo era latente en diez fondos claros y se vio en el lote
  elegido de bodega. Token a `#57645f` (5,58 / 4,99).
- **DQ-05.** En el selector de lote la cantidad —el dato por el que se elige—
  iba a 10 px en el color más tenue. Pasa a tinta plena.
- **DQ-06, mitigado y abierto.** `/operaciones/centros`: **14,9 pantallas en
  móvil contra 1,8 en escritorio** con los mismos 28 puntos. El scroll interno
  que acota la lista solo existe desde 761 px, así que en móvil el alto crece con
  los datos. La ficha pasó de 364 a 280 px al volver a dos columnas, pero eso no
  cambia la proporcionalidad: hace falta buscador o repliegue, y es producto.
- `audit:visual`: 55 mediciones, cero desbordes horizontales de 1440 a 390 px.
- **G-033 · P2 cerrada, y es la lección del ciclo.** La suite E2E corría en el
  puerto 3000 con `reuseExistingServer` activo: `verify` probaba en silencio el
  servidor de desarrollo que hubiera abierto. La prueba del mapa falló contra mi
  propio servidor con horas de uso y el HMR caído —dos chunks en 403— y con
  servidor limpio pasa en 10 s. **Casi lo atribuyo a mis cambios de CSS; no lo
  eran.** Ahora: puerto 3100 y sin reutilizar salvo petición expresa.
- Niveles: S-02/S-03/S-04 suben a 3 porque ya existe la medición que faltaba;
  S-05 se queda en 2 pese a tener el contraste limpio, por DQ-06.

### Despliegue 2026-08-17 · G-028 y G-030 en producción

- `supabase db push --linked` aplicó `202608170006` y `202608170007`; `vercel --prod`
  desplegó y quedó aliado a `unidos-nos-cuidamos.vercel.app`, listo en 28 s.
- **`G-030` cerrada globalmente.** Antes del push, producción tenía **21
  membresías `partner_reporter` cruzadas activas** sobre organizaciones de
  gremios: una sola cuenta podía reportar y corregir a nombre de ANDI, Cruz Roja
  o la Cámara de Comercio. Tras el push: **0**.
- Verificado en producción: `cruzadas_activas=0`, `partner_activas_total=1`,
  `amend_donation_intake` existe, `intake_amendments` existe con RLS activa.
- Smoke test: `/api/health` `ok` con base conectada; `/`, `/reportar`, `/donar`,
  `/seguimiento`, `/transparencia`, `/ingresar` en 200; CSP, HSTS, `nosniff` y
  `X-Frame-Options: DENY` presentes; el aviso «Datos de práctica» sigue visible y
  `/ingresar` no publica credenciales.
- Respaldo previo de las 22 membresías en
  `.local-backups/despliegue-20260817/membresias-antes.json`.
- **La puerta no se movió:** sigue G1 sandbox sintético. Este despliegue cierra un
  P1 vivo y agrega el ciclo de corrección; no autoriza datos reales, recaudo ni
  comunicación institucional.

- **`npm run verify` verde de extremo a extremo**, y `G-030` cerrada: `202608170001` replicaba `partner_reporter` sobre las 21 organizaciones aliadas, habilitando a una sola cuenta para reportar como ANDI, Cruz Roja o la Cámara de Comercio. `202608170007` deja de replicarlo y desactiva lo concedido sin borrarlo. Se creyó que no había llegado al remoto; **sí estaba viva allí** y se desplegó el mismo día (bloque anterior).
- Lo detectó `verify-rls.mjs`, que esperaba una organización y veía 22. **La
  comprobación estaba en lo correcto y por eso no se relajó**; se relajaron solo
  las que sí eran expectativas viejas (G-029).
- **G-029 · P2 cerrada.** Conteo fijo de centros, etiqueta «Dirección exacta
  privada» —`202608170002` hizo pública la dirección de un acopio, por ser lugar
  de entrega— y una verificación de privacidad que solo miraba la fila `[0]`.
  Ahora comprueba todas las filas y que anon no lea la tabla operacional.
- **G-032 · P2 cerrada.** `verify` no era idempotente: `db:test` corría antes del
  único `db:reset` y heredaba los puntos del E2E previo. Reset antepuesto.
- **G-031 · P2 abierta.** Sin representante propio, los 21 puntos de gremios son
  públicos pero ningún aliado puede enrutar un aporte a ellos, porque G-022 exige
  mismo tenant. Es una tensión de modelo que necesita decisión humana.
- Entorno: `preflight:local` estaba bloqueado por `.vercel/project.json` y
  `supabase/.temp/project-ref`. Se respaldaron en `.local-backups/enlaces-remotos/`
  y se retiraron; se regeneran con `vercel link` y `supabase link` al desplegar.

- **Pista funcional · G-028.** Migración `202608170006`: tabla `intake_amendments`
  append-only con RLS de lectura para la organización dueña, verificación y
  auditoría, y sin política de escritura —la única escritura ocurre dentro de la
  RPC `security definer`. `donation_intake_items` no tiene trigger de auditoría,
  así que la fila de enmienda guarda el diff explícito en vez de delegarlo.
- `amend_donation_intake` exige `partner_reporter` de la organización dueña
  (`has_any_role` acota organización y evento a la vez), estado `observed` y
  versión esperada; la respuesta pasa por `contains_sensitive_content`. Una
  versión distinta a la leída se rechaza con `40001` en vez de pisar el cambio.
- Superficie en `/operaciones`: los aportes observados del aliado aparecen antes
  que cualquier otra cola suya, con la observación de verificación citada.
- Evidencia: 22 pgTAP nuevas y el E2E del ciclo completo observar → corregir →
  volver a verificación en chromium y móvil. La prueba crea su propio aporte
  porque el seed no trae ninguno.

### Loop de consolidación · integrado el 2026-08-18 (rama `claude/new-session-tflf63`)

- **No verificado en base de datos.** Este ciclo se desarrolló en un entorno sin Supabase local: la política de egreso bloquea la descarga de las imágenes de contenedor (403 en el CDN de blobs). Lo comprobado es `eslint`, `tsc --noEmit`, `next build`, 47/47 unitarias y la validación sintáctica de las 31 migraciones y de los tres archivos pgTAP con el analizador de PostgreSQL. **Faltan por ejecutar** pgTAP, RLS, concurrencia y los 36 Playwright; la siguiente sesión con Docker debe correr `npm run verify` antes de dar el ciclo por cerrado.
- Auditoría en `docs/AUDITORIA_CONSOLIDACION_2026-08-19.md`: clasificación de los doce módulos y las duplicaciones reales. Solo dos resultaron duplicación (provisión de usuarios y el snapshot `remote-bootstrap.sql`); la trazabilidad pública no lo era y la clasificación se corrigió. El hueco de fondo era otro: no existía el eje bodega a bodega.
- ALIADO autorregistrado: `register_ally` → confirmación de correo en Auth → `activate_ally_registration`. La activación crea organización, membresía `partner_reporter`, punto de acopio propio con sus reglas de aceptación, y replica sobre esa organización las membresías de administración y operación del evento. Identificador `alias@rutasolidaria.co` reservado como identidad, sin provisionar buzón (ADR-007).
- Necesidad única con aportes parciales: `need_item_positions` deriva solicitado, comprometido, recibido, entregado y pendiente. El compromiso se cuenta desde el aporte confirmado, no desde el aprobado, para que dos aliados no comprometan lo mismo mientras la verificación decide; el artículo se bloquea durante la validación.
- Camino AYUDAR: `submit_donation_intake_v2` recibe la necesidad como un parámetro más y rechaza lo que no cabe en lo pendiente. La firma de dieciséis parámetros se retiró: hay una sola forma expuesta de registrar un aporte. El enlace público viaja con el identificador de la proyección, no con el de la necesidad operacional.
- Inventario derivado del Kardex (ADR-008): `inventory_lot_positions` e `inventory_position`. La consola dejó de mostrar `quantity_initial` como existencia y de usarla como tope de reserva.
- Traslado entre bodegas (ADR-009): `transfer_requests` con autorización parcial, reserva sobre `allocations` por vencimiento más próximo, `create_shipment` en «Preparando» para los dos destinos, `dispatch_shipment` que exige el transporte, `advance_shipment` para En movimiento y Llegó, y `register_delivery` que separa faltante de daño y crea el inventario de destino solo cuando el destino confirma.
- Alcance por bodega: `membership_locations` y `has_location_scope`. Sin filas declaradas el comportamiento anterior se conserva, así que ningún recorrido vigente se rompe.
- Reportes operativos en `/operaciones/reportes`, todos derivados del Kardex y `security invoker`.
- Limpieza: se retiraron `shipments.carrier_name` (sustituido por los campos estructurados de transporte), `supabase/remote-bootstrap.sql` (snapshot de 14 migraciones que ya no referenciaba nadie) y `scripts/provision-sandbox-access.mjs` con su script npm (caso particular de `bootstrap:environment` con el proyecto fijado en código).
- Prueba de recorrido completo: `supabase/tests/consolidation_flow_test.sql` implementa los veinte pasos de la Fase 17 con 44 comprobaciones. Está escrita y validada sintácticamente; **no ejecutada**.


- Alcance por evento en las consolas operativas: `/operaciones`, `/operaciones/bodega` y `/operaciones/tesoreria` filtraban roles y datos sin `event_id`. Un rol vigente en otro evento abría la consola y las listas mezclaban filas de todos los eventos donde la organización tuviera membresía. Ahora todas las consultas se acotan a `EVENT_ID`, incluidas `donation_items`, `need_items` y `deliveries`, que se acotan por su padre con join interno.
- Saldo conciliado correcto: se sumaba en el cliente sobre la lista ya cargada — ocho transacciones en el centro operativo y el tope de la API en tesorería — y se mostraba como «Saldo conciliado» sin decir que era parcial. `treasury_balance` lo calcula sobre el libro completo del evento y solo de las organizaciones donde la persona es miembro. El KPI declara cuántos movimientos suma y solo aparece para roles de tesorería.
- Justificación de gasto legible: `approve_expense` recibía la nota fija «Decisión de tesorería» y `expense_approvals` tiene RLS sin ninguna política de lectura, así que la justificación quedaba escrita y sin forma de consultarla. Ahora la escribe quien decide, es obligatoria y `expense_decisions` la devuelve acotada al evento y a las organizaciones del usuario; la consola la muestra bajo cada solicitud con su fecha.
- Tesorería más clara: etapas 01 Conciliar → 02 Solicitar → 03 Aprobar → 04 Pagar con sus colas reales; quien tiene ambos permisos ve los dos formularios en lugar de perder uno por una condición excluyente; «otros ingresos» exige una referencia escrita en vez de generar una al azar; y una solicitud propia explica por qué no ofrece botones en lugar de esconderlos sin decir nada.
- La comprobación de origen inválido del recorrido se anuncia como omitida cuando la organización no declara ningún punto de solo recepción, para no leerse como cobertura que no existe.
- Verificado: lint, `tsc --noEmit`, build, 39/39 unitarias, 182/182 pgTAP, RLS, concurrencia, 28/28 Playwright y el ciclo desde cero con 41/41 del recorrido.

- Ciclos anteriores (entorno de entrega, puntos con propósito, provisión desde cero, recorrido optimizado, simulación remota, catálogos, endurecimiento inicial): `docs/ai/archive/STATE-hasta-2026-08-16.md`. Sus cifras son históricas.

## Contexto que debe cargarse

- Archivos: `AGENTS.md`, este archivo, `docs/UX_MAP.md` y `docs/ai/PLAN.md`.
- Decisiones: ADR-001 a ADR-013 en `docs/DECISIONS.md`. Las de este ciclo son ADR-010 a ADR-013: SUPER_ADMIN como alcance y no como segundo RBAC, la concesión fuera de banda, qué es parametrizable y por qué, y la separación entre correo confirmado y organización verificada.
- Riesgos: `docs/RISK_REGISTER.md` y `docs/GAP_LEDGER.md`.
