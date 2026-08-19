# Estado comprobado

Fecha: 2026-08-18 · Puerta: **G1**, sandbox con datos 100 % sintéticos.
G2 y G3 siguen bloqueadas: no deben incorporarse operadores, PII, dinero ni
comunicación institucional.

**Desplegado en producción el 2026-08-19.** `main` quedó en `e572801` con la
entrega de despacho, trazabilidad y tesorería fusionada con la consolidación de
logística, más SUPER_ADMIN y la parametrización. El remoto pasó de 28 a **38
migraciones**; el front se desplegó por la integración de Git de Vercel y el alias
de producción apunta al build nuevo.

## Lo verificado

`npm run verify` pasa de extremo a extremo sobre las 38 migraciones integradas:

| Comprobación | Resultado |
|---|---|
| `preflight:local` | ok · sin enlaces activos a proyectos remotos |
| Lint · TypeScript · build | verdes |
| Unitarias (Vitest) | 47/47 |
| SQL (pgTAP) | 372/372 sobre 38 migraciones, en cinco archivos |
| RLS (`verify-rls.mjs`) | ok · anonimato, aislamiento de tenant, escalamiento bloqueado y alcance global |
| Concurrencia de aporte | ok · doble envío produce un solo aporte |
| Concurrencia de reserva | ok · 25 disponibles, dos reservas de 20 a la vez, una sola completa |
| Playwright web + móvil | 44/44 · servidor propio y limpio (`G-033`) |
| `audit:a11y` | **0 problemas** en 14 superficies · 3 indeterminados medidos a mano |
| `audit:visual` | 70 mediciones · cero desbordes horizontales |


## Qué se cerró en este ciclo

**`G-038` · P1 — la consolidación nunca había tocado una base de datos.** Las seis
migraciones del 19 de agosto se escribieron y se validaron sintácticamente, pero
ningún entorno pudo ejecutarlas. Al correrlas sobre el árbol fusionado aparecieron
cuatro defectos reales, no hipotéticos:

- `activate_ally_registration` abortaba con `42702` en la primera activación. La
  función devuelve una tabla con la columna `organization_id`, así que ese nombre
  también es una variable PL/pgSQL y sus dos `on conflict (user_id,
  organization_id, ...)` eran ambiguos. Ningún aliado podía activarse, y con eso
  38 de las 44 comprobaciones del recorrido completo ni siquiera llegaban a correr.
- `submit_donation_intake_v2` había perdido la validación de tenant del punto de
  entrega. La Fase 4 la reimplementó como función completa en lugar de conservar
  el envoltorio de `202608160003`, y con él se fueron `assert_delivery_point_tenant`
  —que es el cierre de `G-022`, un P0—, la validación del aliado de referencia y la
  escritura de `reporting_ally_code`. **Un aliado volvía a poder enrutar su aporte
  al punto de otra organización.**
- Una prueba invocaba la RPC con dieciséis argumentos cuando la firma ya exigía
  diecisiete: fallaba por «function does not exist», no por lo que pretendía probar.
- La prueba de AYUDAR tomaba con `.first()` la llamada general del encabezado en vez
  del enlace de la ficha, y esperaba con `toHaveURL(/\/donar$/)` —que la URL de
  partida `/ingresar?next=/donar` ya satisface—, así que la navegación siguiente
  salía sin sesión.

Las seis migraciones no están aplicadas en ningún entorno, así que las dos primeras
correcciones se hicieron sobre ellas en vez de añadir una migración de parche.

**`G-040` y `G-041` · P1 — dos garantías que nadie había ejercido.** La reserva
concurrente estaba escrita en la transacción (`select ... for update` sobre el lote
y recálculo del disponible ya con el bloqueo puesto) pero no había prueba: ahora
`verify-reservation-concurrency.mjs` monta 25 unidades por el recorrido real y lanza
dos reservas de 20 a la vez contra la API; una sola completa, la otra recibe
«Existencia insuficiente» y el Kardex cierra en 5. Y el traslado entre bodegas solo
estaba probado cuando el destino confirma exactamente lo despachado: el caso con
faltante, que es el que puede perder producto del historial, ahora tiene su
comprobación —salen 5 kg, el destino confirma 3, el inventario crece en 3, la
conciliación queda en NOVEDAD y los 2 kg siguen contados en lo despachado.

**`G-042` · P1 — SUPER_ADMIN, sin un segundo sistema de permisos.** El rol es un
valor más de `app_role` y se concede con una fila en `memberships`, como cualquier
otro. Lo que cambia no es la forma del permiso sino su alcance, y ese alcance vive
donde ya vivía: en `is_org_member`, `has_any_role`, `has_event_role` y
`has_location_scope`, que son las cuatro compuertas que usan todas las políticas y
todas las RPC. Cada una conserva su regla y le suma el alcance global.

No es un bypass. RLS sigue habilitada, el inventario sigue sin ninguna política de
escritura directa y ninguna RPC de operación cambió: la autoridad global recorre las
mismas transiciones y deja el mismo Kardex. La prueba lo ejerce desde la API real —un
intento de editar `inventory_lots` con sesión de SUPER_ADMIN no toca ninguna fila.

Y nadie puede escalar su propio rol: `memberships` no tiene política de INSERT ni de
UPDATE, `assign_membership_role` rechaza el rol `super_admin` y rechaza actuar sobre
uno mismo, y conceder SUPER_ADMIN solo es posible por `grant_super_admin`, revocada
para `anon` y `authenticated`. El rol se lee de la tabla, nunca de un claim del token.

**Parametrización.** `/operaciones/parametrizacion` reutiliza lo que ya existía en vez
de duplicarlo: los puntos se siguen administrando con `manage_delivery_point`, los
catálogos siguen versionados con `effective_from`/`effective_to`, el alcance por bodega
sigue en `membership_locations` y la auditoría sigue siendo `audit_events`. A esa
auditoría solo le faltaba el valor anterior y el nuevo; se activa por tabla y excluye
toda columna `_private`, porque copiarlas convertiría el registro en una fuga (`G-043`).

Quedan fuera de lo parametrizable los catálogos que son contrato: los estados
declarados alimentan el mapeo de estados operativos dentro de la RPC de aporte, y los
departamentos son referencia DIVIPOLA.

**Pasada de revisión sobre lo entregado.** Antes de darlo por cerrado se auditaron los
privilegios reales de cada función nueva, y dos cosas estaban dichas pero no hechas:

- `grant_super_admin` afirmaba en su comentario ser «alcanzable con `service_role`» y no
  lo era. Al revocarla de `public`, `anon` y `authenticated` quedó sin ninguna concesión
  explícita, de modo que solo la ejecutaba el superusuario: la función auditada era código
  muerto. Y lo que `service_role` sí podía hacer era peor —`202608160004` le concede INSERT
  y UPDATE sobre `memberships` para el arranque en frío, así que podía escribirse la
  autoridad global a mano, sin motivo, sin actor y sin auditoría. La vía sancionada estaba
  cerrada y la silenciosa abierta. Se corrigen las dos mitades: la función se concede a
  `service_role` y un disparador bloquea escribir o alterar una fila `super_admin` fuera de
  ella. `seed.sql` la siembra por esa misma vía, así que cada `db:reset` ejercita el camino
  real.
- Cada cambio de catálogo dejaba tres registros de auditoría y guardaba `values_json` dos
  veces. Se conserva el registro de negocio —el único que empareja el antes con el después
  y trae el motivo y las versiones— y se retira el disparador de tabla, porque
  `catalog_versions` no tiene más escritor que esa función.

También se corrigió el ayudante de sesión de la suite E2E, que esperaba con una expresión
de sufijo sobre la URL: `/ingresar?next=/operaciones` ya la satisface, así que la espera se
cumplía antes de que existiera cookie. Es el mismo defecto que había en la prueba de AYUDAR.

**`G-039` · P2 — confirmar un correo no es verificar una organización.** El
autorregistro escribía `organization_verifications.state = 'verified'` en cuanto la
persona confirmaba su buzón, de modo que una organización comprobada documentalmente
y otra que solo abrió un correo quedaban escritas igual. Ahora el autorregistro deja
`email_verified`, existe `document_pending`, y llegar a `verified` exige una decisión
humana con actor y sustento. **La verificación documental en sí sigue pendiente**: es
política de aceptación (`G-003`), no código.

**`G-028` · P1 — el aporte observado ya no queda atrapado.** El verificador podía
marcar «Con observaciones» y no existía ninguna función ni superficie para que el
aliado corrigiera: el ingreso se quedaba ahí para siempre. `202608170006` agrega
`intake_amendments` —append-only, con el antes y el después de cada campo— y
`amend_donation_intake`, que exige rol de la organización dueña, estado `observed`
y versión esperada, corrige cantidades y monto, y devuelve el aporte a la cola sin
sobrescribir historia. El aliado responde desde `/operaciones`.

**`G-030` · P1 — autoridad cruzada entre organizaciones.** `202608170001`
replicaba `partner_reporter` sobre las 21 organizaciones aliadas que crea: una
sola cuenta quedaba habilitada para reportar y corregir a nombre de ANDI, Cruz
Roja o la Cámara de Comercio. Es la suplantación que la plataforma existe para
impedir, concedida como autoridad real en la base. `202608170007` deja de
replicar el rol y desactiva lo concedido sin borrarlo.

**Estaba viva en producción.** Al cerrarla se dio por hecho que no había llegado
al remoto, porque la memoria interna del proyecto decía que allí quedaban 15
migraciones. Era un dato vencido: el remoto tenía 26, y una consulta a
producción encontró **21 membresías cruzadas activas**. El despliegue del mismo
día las dejó en **0**. La lección quedó anotada donde estaba el error: el estado
del remoto se comprueba con `supabase migration list --linked`, no con la
memoria del repositorio.

Lo detectó `verify-rls.mjs`, que esperaba una organización visible para el aliado
y veía 22. La comprobación estaba en lo correcto y por eso no se relajó.

**`G-029` · P2 — comprobaciones desactualizadas.** Un conteo fijo de centros (2
contra 23), la etiqueta «Dirección exacta privada» —`202608170002` decidió que la
dirección de un acopio es pública, por ser lugar de entrega— y una verificación
de privacidad que solo miraba la primera fila. Ahora comprueba todas y que
anónimo no lea la tabla operacional.

**`G-032` · P2 — la puerta no era reproducible.** `db:test` corría antes del único
`db:reset` y heredaba los puntos que crea el E2E, así que la segunda ejecución
seguida fallaba.

**`G-033` · P2 — la puerta probaba lo que hubiera encendido.** Las pruebas de
navegador usaban el puerto 3000, el mismo de desarrollo, y reutilizaban el
servidor que estuviera abierto. Así que `npm run verify` no medía el código del
repositorio: medía el servidor de quien lo ejecutara, en el estado en que
estuviera. Se descubrió porque la prueba del mapa falló contra un servidor con
horas de uso —dos archivos respondían 403 y el mapa nunca cargaba— y con un
servidor limpio pasa en diez segundos. Ahora la suite arranca su propio servidor,
en su propio puerto y con su propio directorio de compilación.

## Qué falta

### Bloquea G2 y depende de decisiones humanas

Ninguna es técnica. Sin ellas no se puede incorporar un solo dato real.

| Brecha | Qué hay que decidir |
|---|---|
| `G-002` | Entidad operadora, RACI y SLA nominales |
| `G-005` | DPIA y base legal · responsable del tratamiento |
| `G-003` | Política de aceptación validada por autoridad humanitaria |
| `G-004` | Proveedor financiero, fondos, AML/KYB y certificados |
| `G-006` | Autorización de marca y fuentes oficiales |
| `G-001` | Snapshot autorizado del legado antes de migrar |

### Bloquea G2 y es técnico o de administración

| Brecha | Qué falta |
|---|---|
| `G-022` | Su migración **ya está aplicada en remoto**; falta repetir allí el arnés de simulación para cerrarla globalmente |
| `G-007` | Habilitar protección de contraseñas filtradas en Supabase Auth |
| `G-015` | WAF y rate limiting de borde |
| `G-017` | Enlaces verificables a remoto sin exponer secretos |
| — | Rotar las credenciales de base expuestas |
| — | Backups remotos y PITR, monitoreo externo y alertas |

### Deuda abierta de producto

| Brecha | Qué falta |
|---|---|
| `G-031` | Sin representante propio, los 21 puntos de gremios son públicos pero ningún aliado puede enrutar un aporte a ellos: `assert_delivery_point_tenant` exige mismo tenant. O cada gremio habilita a su representante, o el modelo admite entregar en un punto de otra organización validando en recepción |
| `G-026` | Cada fila auditada genera una correlación distinta dentro de la misma RPC |
| `G-027` | Las operaciones no generan un corte nuevo de métricas conciliadas |
| `G-039` | El modelo ya distingue correo confirmado de organización verificada, pero **la verificación documental en sí sigue sin implementarse**: depende de `G-003` |
| `G-043` | La auditoría guarda el antes y el después solo en las tablas del parametrizador; en las operativas seguiría llevando PII a `audit_events` |

### Deuda visual

`docs/ai/DESIGN_QUALITY.md` inventaría 16 superficies: **1 en nivel 0**
(Evidencias, sin interfaz), 2 en nivel 2 y 13 en nivel 3. Ninguna en 4.

**Lo que se cerró.** `DQ-01` era una brecha del instrumento, no del producto:
`audit:a11y` y `audit:visual` solo miraban seis rutas públicas, así que las
cinco consolas —donde ocurre el trabajo real— no tenían ninguna evidencia y no
podían declararse por encima de nivel 2. Ahora se auditan catorce superficies
—siete públicas y siete autenticadas, incluidas `/registro`, `/operaciones/reportes`
y `/operaciones/parametrizacion`—, cada una con el rol que la usa. Eso destapó dos defectos reales:

- El color de texto secundario pasaba el mínimo sobre el fondo normal (4,89:1)
  pero no sobre el fondo verde claro que marca **cualquier cosa seleccionada**
  (4,37:1). Estaba latente en diez fondos del diseño y se vio en el lote elegido
  de bodega. Corregido a 5,58 / 4,99.
- En el selector de lote, la cantidad —el dato por el que se elige un lote— era
  lo más pequeño y tenue del control. Ahora se lee.

También se arregló el propio control: contaba como fallo el texto sobre
fotografía, que no se puede calcular desde el código, y por eso **nunca podía
salir en verde**. Un control que siempre falla no es una puerta. Hoy sale en 0.

**Lo que sigue abierto.**

- `DQ-06` — la administración de puntos ocupa **14,9 pantallas en un teléfono y
  1,8 en un computador**, con los mismos 28 puntos. En pantalla grande la lista
  tiene su propio desplazamiento y el alto no depende de cuántos puntos haya; en
  móvil ese límite no existe, así que cada punto nuevo alarga la página. Se
  compactó la ficha, pero el arreglo de fondo —un buscador o fichas que se
  desplieguen— es decisión de producto.
- `DQ-02` — la superficie de evidencias no existe: el bucket es privado y no hay
  interfaz. Es la única en nivel 0 y está condicionada a que exista política de
  consentimiento aprobada (`G-003`, `G-005`).

## Despliegue del 2026-08-17

Local y remoto quedaron **sincronizados en 28 migraciones**. `supabase db push`
aplicó `202608170006` y `202608170007`; `vercel --prod` publicó y quedó aliado a
`unidos-nos-cuidamos.vercel.app` en 28 s.

| Comprobado en producción | Antes | Después |
|---|---|---|
| Membresías `partner_reporter` cruzadas y activas | 21 | **0** |
| `partner_reporter` activas en total | 22 | 1 |
| `amend_donation_intake` | no existía | existe |
| `intake_amendments` | no existía | existe, con RLS activa |

Prueba de humo tras publicar: `/api/health` responde `ok` con la base conectada;
`/`, `/reportar`, `/donar`, `/seguimiento`, `/transparencia` e `/ingresar`
devuelven 200; CSP, HSTS, `nosniff` y `X-Frame-Options: DENY` están presentes; el
aviso «Datos de práctica» sigue visible y `/ingresar` no publica credenciales.

Las 22 membresías previas se respaldaron en
`.local-backups/despliegue-20260817/membresias-antes.json` y la compensación las
desactiva, no las borra.

**La puerta no se movió.** Esto cierra un P1 que estaba vivo y agrega el ciclo de
corrección; sigue siendo G1 con datos sintéticos. No autoriza datos reales,
recaudo ni comunicación institucional.

## Estado del entorno local

- Aplicación `http://127.0.0.1:3000` · Studio `http://127.0.0.1:55323` ·
  Mailpit `http://127.0.0.1:55324`.
- `.env.local` quedó en el entorno de **suite** (`sandbox`, sin
  `NEXT_PUBLIC_EVENT_ID`/`SLUG`), que es el que corresponde a la base actual:
  `npm run verify` incluye dos `db:reset` y volvió a sembrar el seed sintético,
  así que el evento de entrega `entrega-piloto-2026` **ya no está en la base
  local**. Los dos estados son coherentes entre sí y la aplicación funciona.
- Para volver al entorno de entrega: `npm run env:entrega`, luego
  `npm run bootstrap:environment` con `entorno-entrega.json` (vive fuera del
  repositorio), y restaurar las variables desde
  `.local-backups/entorno-entrega/env.local.entrega`. Ver
  `REMOTE_SETUP_RUNBOOK.md`. Nada de esto toca el remoto.
- Los enlaces remotos se regeneraron para desplegar y **se retiraron otra vez al
  terminar**: mientras están puestos, `preflight:local` falla y con él
  `npm run verify`, que es justamente el propósito de esa comprobación —el
  sandbox no debe quedar apuntando a producción. Están respaldados en
  `.local-backups/enlaces-remotos/` y se regeneran con `vercel link` y
  `supabase link` en el próximo despliegue.

## Remoto autorizado

`https://unidos-nos-cuidamos.vercel.app` sirve `NEXT_PUBLIC_APP_ENV=sandbox` con
datos sintéticos y su aviso visible. Es la postura correcta y tiene valor: permite
que la Gobernación y los gremios recorran el flujo y decidan lo que solo ellos
pueden decidir. No autoriza datos reales, recaudo ni comunicación institucional.

## Despliegue del 2026-08-19

Las diez migraciones pendientes se aplicaron y el front se desplegó a continuación.
Comprobado sobre el dominio de producción: `/api/health` responde 200 con la base
conectada, `/registro` —una ruta que solo existe en el código nuevo— responde 200, las
consolas redirigen a ingreso para quien no tiene sesión, y la portada sirve
`/donar?necesidad=` junto a «Solicitado · comprometido · entregado», que se derivan de
`need_item_positions`, una vista creada por `202608190002`. Es decir: esquema nuevo y
front nuevo hablándose.

**Cómo se hizo, porque no fue por el camino previsto.** El pooler de sesión (puerto
5432) no es alcanzable desde el equipo de trabajo: acepta el TCP y muere sin responder
al saludo de Postgres, comprobado también fuera de Docker. Las migraciones se aplicaron
por el pooler de transacción (6543) con `--db-url`, y el front se desplegó fusionando a
`main` y dejando que la integración de Git de Vercel construyera, porque `vercel --prod`
desde el equipo falla con `fetch failed` por la misma red. Queda descrito en
`RELEASE_CHECKLIST.md` junto al workflow de despliegue, que es la vía recomendada para
la próxima.

**Ventana de incompatibilidad.** Entre la aplicación de las migraciones y el despliegue
del front hubo unos minutos con el esquema nuevo y el código viejo: el registro de
aportes y las escrituras de bodega no funcionaban porque las firmas de RPC que ese
código invoca ya no existían. Era inevitable con este conjunto de cambios y por eso el
workflow de despliegue encadena ambos pasos en un solo trabajo.

## Pendiente inmediato tras el despliegue

| Qué | Por qué no lo resuelve el despliegue |
|---|---|
| Habilitar registro y confirmación de correo en el panel de Auth | `db push` no toca la configuración de Auth. Sin esto `/registro` acepta el formulario y la activación nunca llega. **No usar `supabase config push`**: `config.toml` declara `site_url` en localhost |
| Conceder la autoridad global con `grant_super_admin` | No hay vía desde la aplicación (ADR-011) y la escritura directa está bloqueada por disparador. Hasta entonces `/operaciones/parametrizacion` no es alcanzable para nadie |
| Rotar la contraseña de la base | Quedó expuesta durante la operación |
| Repetir el arnés de simulación remota | Cierra `G-022` globalmente |

## Lo que este despliegue no cambia

`G-002` a `G-006` (operador, DPIA, política de aceptación, proveedor financiero, marca)
son decisiones humanas; `G-007`, `G-015` y `G-017` son administración de entorno; no hay
backups remotos con PITR ni monitoreo externo. El entorno sigue siendo **G1 con datos
sintéticos** y no debe recibir datos reales, dinero ni comunicación institucional.
