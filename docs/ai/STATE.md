# Estado actual

- Puerta/hito: G1 publicada como sandbox sintético interno; G2/G3 bloqueadas y no deben incorporarse operadores/PII antes de verificar en remoto el cierre local de `G-022`.
- Último resultado comprobado (2026-08-21): **`npm run verify` verde de extremo a extremo** sobre `main` con **43 migraciones locales** — preflight, lint, typecheck, 63/63 unitarias, **532/532 pgTAP en nueve archivos**, RLS, dos pruebas de concurrencia, build y 54/54 Playwright web/móvil. Además `audit:a11y` en 0 sobre 14 superficies —3 indeterminados medidos a mano, 0 rutas con movimiento pese a la preferencia reducida— y `audit:visual` con 70 mediciones y cero desbordes. Servidor de producción reiniciado sobre el build nuevo antes de auditar: auditar contra `npm run dev` no sirve, devuelve 403 en algunos chunks de cliente.
- **Todo desplegado el 2026-08-21.** `main` en `9bba69f`, remoto en **48/48 migraciones, cero pendientes**. Lo público no cambió una fila al desplegar. Los dos P0 de seguridad (`G-071`, `G-069`) van desplegados pero **no se ejercitaron los exploits en producción**: habría exigido la clave `service_role` y escribir datos. El remoto quedó al día el 2026-08-19 desde `main` en `e572801`. Se aplicaron por el pooler de transacción (6543) con `--db-url`, porque el de sesión (5432) no es alcanzable desde el equipo de trabajo; el front se desplegó fusionando a `main` y dejando construir a la integración de Git, porque `vercel --prod` local falla con `fetch failed`. Comprobar siempre contra `supabase migration list`, no contra esta memoria.
- Recorrido activo local/remoto: portal, reportes, aportes en especie/dinero con catálogos versionados y centro compatible, QR de seguimiento, operación, tesorería, mapas, dashboards y exportaciones con datos sintéticos. El registro de aporte usa un recorrido adaptativo de cuatro pasos en especie y tres en dinero.
- Hallazgos: A15-001 a A15-008 cerrados para G1. Cerradas `G-021`, `G-023`, `G-024`, `G-025`, `G-028`, `G-029`, `G-030` (globalmente, verificada en producción), `G-032`, `G-033`, y en esta sesión `G-034` a `G-038` (las de la consolidación, ya ejecutadas), `G-040` (concurrencia de reserva), `G-041` (recepción con faltante), `G-042` (SUPER_ADMIN y parametrización) y, el 2026-08-20, `G-050` (solicitud logística generalizada: multiproducto, entre organizaciones y con los tres modos). El 2026-08-21 se cerró `G-055` (P0): la habilitación operativa de una organización pasa a tener una sola puerta auditada, y su punto de acopio deja de publicarse —lista **y mapa**— hasta que alguien la habilite (ADR-022). `G-039` sigue **cerrada solo en el modelo**: el nivel de comprobación distingue buzón de documentos, pero la verificación documental en sí depende de `G-003`. Abiertas por el cierre de `G-055`: `G-059` (la regla de publicación existe dos veces) y `G-060` (la vía de arranque en frío es poder de una clave, no de una persona). `G-022` tiene su migración aplicada en remoto; falta repetir allí el arnés. En la pista visual: `DQ-01`, `DQ-04` y `DQ-05` cerradas; `DQ-06` mitigada. **Abiertas:** `G-031` P2 (tensión de tenant), `G-051` P2 (pedir un lote concreto a otra organización, límite deliberado de privacidad), `G-026/G-027` P2, `G-043` P2 (antes/después solo en las tablas del parametrizador), `G-015` P2, `G-017` P2 y `G-001` a `G-008` P2 (decisiones humanas). `docs/GAP_LEDGER.md` y `docs/ai/DESIGN_QUALITY.md` son la fuente.
- Próxima acción exacta: **F0 del loop de escala** (`docs/LOOP_MAESTRO_ESCALA.md` §14): escribir `scripts/seed-volumen.mjs` —10⁶ movimientos, 10⁴ solicitudes, 10³ operadores, por las RPC reales— y `scripts/verify-carga.mjs`, que cronometra las 15 consultas del camino caliente y falla si alguna supera su línea base. Sin esa línea base ninguna optimización posterior se puede defender. **En paralelo, y es barato:** los cuatro índices de idempotencia de B5 (`stock_movements`, `reserve_lot_quantity`, `allocate_stock`, `create_shipment`, `reconcile_sandbox_payment` buscan `idempotency_key` sin aportar `organization_id`, y el único índice es `unique (organization_id, idempotency_key)`, sin prefijo aprovechable). Sigue pendiente de administración, no de código: SMTP propio y confirmación de correo en Auth (`G-044`, `G-045`), y rotar la contraseña de la base expuesta durante el despliegue. La autoridad global ya está concedida a `gestorti2@cenisoft.org` (2026-08-19), sobre una cuenta creada para ello y no sobre las sintéticas. Después, repetir el arnés de simulación remota para cerrar `G-022` globalmente.
- Bloqueos reales: operador, autoridad, DPIA, política de aceptación, proveedor real, WAF/monitoreo externo, backups remotos/PITR, HIBP, marcas y aprobación de piloto. El despliegue actual no autoriza datos reales, recaudo ni comunicación institucional.
- Entorno local: `preflight:local` pasa. Los enlaces remotos se regeneraron para el despliegue del 2026-08-17 y **se retiraron al terminar** —mientras están puestos, `preflight:local` falla y bloquea `npm run verify`, que es su propósito—; respaldados en `.local-backups/enlaces-remotos/`, se regeneran con `vercel link` y `supabase link`. El entorno local quedó en **suite** tras el último `db:reset`, que es lo que exige `npm run verify`; para la aceptación del producto entregado hay que volver a `npm run env:entrega` según `docs/REMOTE_SETUP_RUNBOOK.md`.
- Deuda documental conocida: `202608170007` lleva en su encabezado la frase «El remoto conserva 15 migraciones», falsa y ya aplicada en producción. No se edita: una migración aplicada es historia y este proyecto compensa en vez de reescribir. La corrección vive aquí, en `GAP_LEDGER.md` y en `STATUS.md`.

## Delta último ciclo

### F0, F3 a medias, y cinco brechas de veracidad · 2026-08-21

**Desplegado** (`23de036`, 60 archivos): 43/43 migraciones y front publicado, con diff **cero**
sobre lo publico. Verificado con 300 comprobaciones en 6 superficies y un refutador por
hallazgo: de 16 reportados sobrevivieron 9. Una superficie no se comprobo —el barrido de
aislamiento de datos lo bloqueo el clasificador de seguridad—.

**Lo que sigue esperando una mano humana: `G-061`, P0.** La portada de produccion muestra «—»
en sus tres cifras porque `NEXT_PUBLIC_EVENT_SLUG` no esta puesta en Vercel y `EVENT_SLUG` cae
al valor local. La logica es del 14 y 16 de agosto; el despliegue no la toco.

**F0 cerrada.** `seed-volumen.mjs` (980.007 movimientos, **1.031.334 de auditoria** — B8
medido) y `verify-carga.mjs`, que mide 19 consultas con `EXPLAIN ANALYZE`, guarda el plan y
falla si una se sale de su linea base. Con techo por consulta: la primera medida se colgo
veinte minutos, y una puerta que puede colgarse no es una puerta.

**Cerradas.** `G-062` redireccion abierta (`/\` que el navegador lleva a otro dominio);
`G-069` **la idempotencia atravesaba organizaciones** —una recibia el lote de otra y el Kardex
perdia una recepcion en silencio— que el loop tenia anotado como B5, un problema de
rendimiento a resolver con cuatro indices, y resulto ser correccion (ADR-023): acotar por
organizacion lo cierra **y** hace utilizable el indice existente, 74,3 -> 0,49 ms sin anadir
ninguno; `G-063` el Excel prometia «excluye direcciones exactas» y las publicaba; `G-066` la
plataforma publicaba codigos de aporte que despues no reconocia —6 de 11 en produccion—;
`G-065` el boton de codigo de practica cargaba una constante muerta.

**`G-068` mitigada, no cerrada.** `202608220004` materializa el saldo por lote con disparador
desde sus **dos** fuentes (el Kardex y `delivery_items`, porque `register_delivery` no escribe
nada contra el lote de origen). `logistics_requests` pasa de **no terminar en 20 s** a 3.186 ms;
posiciones 213 -> 44 ms; disponibilidad compartida 1.154 -> 810 ms; escritura +15 %, declarado.
`202608220005` reescribe `logistics_requests` en una sola pasada de conjunto. Quedan dos
consultas por encima de 200 ms hasta confirmar esa ultima medida.

**`G-070`, y es lo mas importante de la sesion.** Al materializar, `create or replace view`
**no conserva** `security_invoker` si no se repite. Lo omiti, la vista paso a ser del dueno y
una cuenta de UNA organizacion leia lotes de **23** por la API. Las 552 pruebas verdes no lo
vieron porque `verify-rls.mjs` comprobaba tablas y RPC, **no vistas**. Corregido en tres capas
y el arnes ampliado; validado rompiendolo.

**El patron de la sesion.** De las puertas rotas a proposito, **cuatro destaparon que la propia
asercion no probaba nada**: la guarda estructural de `G-069` miraba el cuerpo entero de la
funcion; el catalogo de carga media la consulta vieja y me hizo reportar un 10 % falso; la
prueba de `G-065` pasaba con el defecto puesto porque en local el codigo sembrado si existe; y
la de la cache describia un diseno que ya no era el correcto. Sin romperlas, cuatro cosas
falsas habrian quedado reportadas como verificadas.

- Evidencia: 72 unitarias · **567 pgTAP en doce archivos** · RLS con vistas · dos concurrencias
  · build · 58 Playwright.
- **Abiertas:** `G-061` P0 (configuracion en Vercel), `G-064` P1 (canal de practica sin secreto
  en produccion), `G-067` en parte (`/operaciones%2f` da 500 en Vercel y **no se reproduce en
  local**), `G-068` P1 (la puerta de F3).


### Desplegado, y F0 + dos deltas de seguridad · 2026-08-21

**Desplegado a produccion** (commit `23de036`, 60 archivos): 43/43 migraciones aplicadas y
front publicado. El diff sobre lo publico fue **cero** —32 proyecciones y 27 acopios,
identicos antes y despues— porque toda organizacion de produccion ya estaba habilitada.
Verificado con 300 comprobaciones sobre 6 superficies, cada hallazgo pasado por un refutador:
de 16 reportados sobrevivieron 9. **Una superficie no se comprobo**: el barrido de
aislamiento de datos lo bloqueo el clasificador de seguridad.

**`G-061` · P0, y es tuyo, no de codigo.** La portada de produccion muestra «—» en sus tres
cifras: `NEXT_PUBLIC_EVENT_SLUG` no esta puesta en Vercel y `EVENT_SLUG` cae al valor local
`simulacion-andina-2026`, que no existe alli. El evento real es
`ejercicio-coordinacion-sandbox-2026`. La logica es del 14 y 16 de agosto; el despliegue no
la toco. El codigo se porta bien —enmudece en vez de inventar— pero la portada lleva dias en
blanco mientras `/transparencia` publica 11 aportes.

**F0 cerrada.** `seed-volumen.mjs` siembra en 125 s: 980.007 movimientos y **1.031.334
eventos de auditoria** —mas auditoria que operacion, que es B8 medido— con cero posiciones de
Kardex negativas. `verify-carga.mjs` mide 19 consultas con `EXPLAIN ANALYZE` y guarda su
plan. Tres incumplen la puerta de 200 ms de F3: `logistics_requests` **no termina en 20 s**,
`shared_stock_availability` 1.233 ms y las posiciones del Kardex 273 ms con `Seq Scan` sobre
326.669 filas. Seis recorren alguna tabla entera. Hubo que ponerle techo al arnes: la primera
medida se colgo veinte minutos, y una puerta que puede colgarse no es una puerta.

**`G-062` · P1 cerrada.** Redireccion abierta: `next` se validaba con `startsWith("//")` y
dejaba pasar la barra invertida, que el navegador resuelve a otro dominio. Ahora se resuelve
con el analizador de URL contra un origen centinela, en vez de enumerar ataques. 9 unitarias
y un E2E que ingresa de verdad con un destino hostil.

**`G-069` · P0 cerrada, y cambia el diagnostico de B5 (ADR-023).** El loop anotaba las cuatro
busquedas de idempotencia como un problema de rendimiento a resolver con cuatro indices. Al
ir a ponerlos aparecio que la unicidad es **por organizacion** y las cuatro busquedas son la
primera sentencia de su funcion: buscaban en todas. Comprobado: la organizacion 2 recibe 7
litros con una clave que la 1 ya uso, se le devuelve **el lote de la 1**, queda un movimiento
de Kardex donde deberian ser dos y su inventario real es 0. `reconcile_sandbox_payment` hacia
lo mismo sobre el libro financiero. Acotar por organizacion cierra la colision **y** hace
utilizable el indice que ya existia: **no se añadio ningun indice**.

**Dos veces se rompio una puerta a proposito y valio la pena las dos.** En `G-069` la ruptura
destapo que la guarda estructural que habia escrito no servia: buscaba `organization_id` en
el cuerpo entero, donde aparece igualmente mas abajo, asi que pasaba tambien con el defecto
puesto. Hubo que afilarla para que mirase solo dentro de la sentencia.

- Evidencia: 72 unitarias · **543 pgTAP en diez archivos** · lint y typecheck verdes.
- **Abiertas nuevas:** `G-061` P0 (portada muda en produccion, es configuracion),
  `G-063` P1 (el Excel publico promete lo que no cumple), `G-064` P1 (el canal de practica no
  tiene secreto en produccion), `G-065`/`G-066`/`G-067` P2 de superficie publica, `G-068` P1
  (las tres consultas que incumplen la puerta de F3).


### La habilitación de una organización tiene una sola puerta · 2026-08-21 (G-055, ADR-022)

- **El autorregistro se concedía a sí mismo la confianza.** `activate_ally_registration`
  escribía `organizations.verified = true` (`202608190001:352-353`), la columna de la que
  dependen registrar aportes y publicar el punto de acopio. Y `decide_organization_verification`
  —la vía que ADR-013 declara obligatoria— **sólo sabía poner esa columna en `false`** al
  rechazar: nunca la concedía. La única puerta que habilitaba era la que no dejaba rastro.
- **Se midió antes de tocar nada.** Registrando un aliado sintético contra la base local:
  organización `verified = true`, y un visitante **anónimo** viendo «Acopio Fundacion Fantasma
  Sintetica · Calle Falsa 123» en la lista pública de acopios. Con `enable_confirmations = false`
  (`G-045`) ni siquiera hubo comprobación del buzón.
- **Matiz sobre lo que decía el ledger:** G-055 afirmaba que el defecto «contradice ADR-013».
  Estrictamente no: ADR-013 habla del *nivel de comprobación* y ése el autorregistro sí lo
  respetaba —nace `email_verified`, G-039 hizo su parte—. Lo roto era la otra columna, la del
  permiso, que ADR-013 dio por conservada y nadie custodiaba.
- **Y el ledger tampoco nombraba la mitad más expuesta.** `public_collection_centers` no
  consultaba la organización **en absoluto**: filtraba por punto activo, que reciba y con
  coordenada. Arreglar sólo `verified` habría dejado la publicación abierta.
- **La regla estaba duplicada, y la segunda copia apareció atacando lo ya arreglado.**
  Barriendo con el nombre del impostor las diez superficies legibles por `anon`, nueve daban
  cero y `public_logistics_projections` —la tabla del mapa— daba uno: etiqueta, dirección,
  coordenadas y `published = true`, escritos por `sync_public_collection_projection`, que tenía
  las mismas tres condiciones y tampoco miraba la organización. Como es una tabla y no una
  vista, hizo falta además repropagarla cuando cambia la habilitación: sin eso, habilitar
  dejaría el punto invisible y rechazar lo dejaría publicado.
- **El disparador no puede ser `security definer`, y se escribió así primero.** Con derechos
  del definidor `current_user` es siempre el dueño, así que la segunda condición de la puerta
  no distinguía nada y era decorativa. Lo destapó la prueba que pone la marca de transacción a
  mano desde `service_role`. Con derechos del invocador sí distingue, y el dueño se lee del
  catálogo en vez de incrustarse.
- **Lo que se cerró:** el autorregistro nace sin habilitar; `decide_organization_verification`
  concede con actor y sustento; `bootstrap_organization_habilitation` cubre el arranque en frío
  con motivo y sólo desde `service_role`; `manage_organization` pierde la facultad de conceder
  —conserva crear, renombrar y suspender—; y la escritura directa queda bloqueada aunque
  `service_role` tenga INSERT/UPDATE e ignore RLS.
- **El recorrido gana un paso humano y la interfaz lo dice.** `activate_ally_registration`
  devuelve `operational`; la pantalla de activación deja de prometer «ya puedes registrar
  aportes»; `/donar` distingue a quien no es aliado de quien lo es y espera decisión —antes le
  decía «inicia sesión» a alguien que ya tenía sesión—.
- **Una prueba afirmaba el defecto.** El E2E del registro terminaba en «y la cuenta ya opera».
  Se corrigió a comprobar lo contrario en las tres superficies. `consolidation_flow_test` pasó
  de 56 a 58: el escenario de veinte pasos ahora incluye la decisión de verificación, sin la
  cual el paso 7 se rechaza. No se relajó nada: al recorrido le faltaba un paso real.
- **La puerta se validó rompiéndola.** Reintroducido el `verified = true`, 7 de las 30
  comprobaciones se ponen en rojo. Revertido después.
- **Abiertas por esto:** `G-059` (la regla de publicación sigue existiendo dos veces, sin nada
  que impida que vuelvan a divergir) y `G-060` (`bootstrap_organization_habilitation` es poder
  concedido a una clave, no a una persona).
- Evidencia: `npm run verify` verde · 63/63 unitarias · 532/532 pgTAP · 54/54 Playwright · RLS ·
  dos concurrencias · `audit:a11y` 0 sobre 14 superficies · `audit:visual` 70 mediciones sin
  desbordes · barrido de las 10 superficies anónimas en cero.


### Sistema de movimiento y microinteracción · 2026-08-20

- **Movimiento con tokens, no animaciones sueltas**: tres duraciones y dos curvas, y una
  regla que las gobierna —el movimiento explica un cambio de estado o anuncia que llega
  contenido, y nada se repite en bucle salvo lo que indica que una operación está en curso
  (ADR-021).
- **Microinteracción de estado declarada**: pulsación que hunde el botón, foco visible con
  el amarillo de marca, latido mientras una operación está en vuelo, fila resaltada bajo el
  puntero, tarjetas que se elevan, cabecera que se despega al dejar de estar arriba.
- **Entrada por secciones en el sitio público**, con escalonado corto. La regla de seguridad:
  **el contenido es visible por omisión**; el estado oculto solo existe bajo
  `[data-motion="on"]`, atributo que el runtime no pone si el sistema pide menos movimiento,
  si JavaScript falla o si nunca llega a ejecutarse. Comprobado: tras recorrer la página no
  queda un solo bloque oculto, y con `prefers-reduced-motion` no se oculta ninguno siquiera.
- **`audit:a11y` estrena la puerta que faltaba (`DQ-03`)**: una segunda pasada con
  `prefers-reduced-motion: reduce` que mira lo que calcula el motor, no lo que el CSS
  pretende, y suma a `totalProblemas` cualquier transición que sobreviva. **Se validó
  rompiéndola a propósito** —una transición con `!important`— y señaló las siete rutas
  públicas antes de revertirse. Un control que no puede fallar no prueba nada.
- **Se completó el recoloreado que la identidad había dejado a medias**: el módulo CSS del
  mapa y los colores de los marcadores vivían fuera de `globals.css` y seguían en verde.
- **Hallazgo de entorno, no de código**: el servidor de desarrollo devolvía 403 en tres
  chunks de cliente, así que el runtime de movimiento no llegaba a ejecutarse y parecía roto.
  Es el mismo síntoma de `G-033`. Contra una construcción de producción todo funciona; las
  auditorías se corrieron contra ella para que la evidencia no dependiera de un servidor
  enfermo.
- Evidencia: `npm run verify` verde · 63/63 unitarias · 500/500 pgTAP · 54/54 Playwright ·
  `audit:a11y` 0 problemas y 0 rutas con movimiento pese a la preferencia · `audit:visual`
  70 mediciones sin desbordes.


### Identidad visual institucional · 2026-08-20

- **La aplicación pasa a la identidad de Fedesoft · Cenisoft**: azul oscuro `#0d2343`, azul
  claro `#008bed` y azul hielo `#f0f4f8`, con la marca real de Ruta Solidaria —el mosaico de
  píxeles— en la cabecera, el ícono de la aplicación y la banda del portal (ADR-020).
- **Se recolorearon los tokens, no las reglas.** Los 98 colores sueltos del stylesheet se
  pasaron a la familia azul **conservando la luminosidad de cada uno**, que es lo que hace
  que el contraste de toda la aplicación sobreviva a un cambio de familia cromática.
- **La marca dejó de imitarse.** Donde había un cuadrado con tres puntos que hacía de
  logotipo ahora está el activo real, servido como imagen; el ícono de la aplicación y los
  del manifiesto se generaron del mismo archivo.
- **DQ-08: el azul de identidad no sirve para escribir.** `#008bed` da 3,55:1 sobre blanco:
  como fondo del botón principal dejaba la etiqueta de 14 px por debajo de AA y como
  antetítulo de 12 px se quedaba en 4,18. Lo destapó `audit:a11y` al pasar de 3 a 9
  indeterminados. Ahora hay dos azules con papeles distintos —`--brand` para lo gráfico,
  `--forest-2` (`#0b5ea3`) para lo que es texto o lo sostiene— y la puerta vuelve a 0.
  Es una desviación deliberada del comparativo, documentada.
- Los tres rótulos sobre la fotografía del portal se volvieron a medir a mano: el velo azul
  oscuro compuesto sobre la peor zona de la foto da **10,2:1** en blanco y **7,87:1** en el
  secundario, mejor que el velo verde anterior.
- Evidencia: `npm run verify` verde · 63/63 unitarias · 500/500 pgTAP · 54/54 Playwright ·
  `audit:a11y` 0 problemas en 14 superficies · `audit:visual` 70 mediciones sin desbordes.


### Recaudo por pasarela para aportes en dinero · 2026-08-20

- **El dinero ya puede entrar por la plataforma.** Antes un aporte económico solo podía
  declararse y tesorería lo conciliaba a mano contra un extracto. Ahora existe el núcleo del
  recaudo, agnóstico del proveedor: canal parametrizable, intención de cobro, vuelta firmada
  del proveedor y conciliación humana (`G-053`, ADR-018 y ADR-019).
- **Cobrar no es conciliar, y esa regla la impuso el propio esquema.** El primer diseño creaba
  el movimiento en `provider_confirmed` y lo actualizaba al conciliar; el disparador
  `financial_transactions_immutable` lo rechazó. El libro es append-only: no tiene asientos que
  cambian de estado, tiene hechos. Confirmar deja la intención en `confirmed` y no escribe nada;
  el asiento lo escribe tesorería al casar el cobro con el extracto, y nace conciliado. **El
  saldo no se mueve hasta ese momento.**
- **La plataforma no ve datos de pago.** Ni tarjeta, ni cuenta, ni token: solo cuánto se pidió
  cobrar, por qué canal y qué referencia devolvió el proveedor.
- **La base no guarda secretos y la aplicación no estrena una clave de administración.**
  `payment_providers` guarda el SHA-256 del secreto de webhook. La ruta del webhook verifica la
  firma HMAC del cuerpo y llama a la RPC con la clave publicable, enviando el secreto como
  argumento; PostgreSQL compara huellas. `src/` sigue sin contener ninguna clave `service_role`.
- **`public_config` rechaza por nombre cualquier llave que huela a secreto** (`api_key`, `token`,
  `clave`…): el campo de configuración libre es el sitio más probable donde alguien pegaría una
  credencial.
- **El canal de práctica no es una maqueta.** Firma su aviso con el mismo secreto y lo manda al
  mismo webhook que usaría un proveedor real, así que el recorrido probado es el que se operará.
  Lo único simulado es que nadie paga.
- **Sigue sin haber proveedor real (`G-054`).** Conectarlo no es trabajo de código —el adaptador
  es una función que devuelve la URL de checkout— sino de contrato, credenciales, alcance PCI y
  base legal (`G-004`, `G-005`). Hasta entonces la plataforma **no recauda**, y activar un canal
  con `sandbox = false` exige autoridad global y un motivo escrito.
- Evidencia: `npm run verify` verde · 63/63 unitarias · 500/500 pgTAP en ocho archivos ·
  54/54 Playwright, con un recorrido completo que paga por la pasarela y concilia · RLS con el
  recaudo cerrado a visitantes · `audit:a11y` en 0 sobre 14 superficies y `audit:visual` con 70
  mediciones sin desbordes.


### Consola por las tres acciones · 2026-08-20 (Fase C del loop maestro)

- **`/operaciones` deja de ser un menú de módulos.** Abre con «¿Qué necesitas hacer?» y las
  tres acciones humanas del recorrido —Solicitar, Recibir, Despachar— como nivel visual
  dominante, cada una con la cifra real de lo que espera y enlazada a su etapa. Lo demás
  (revisar, inventario, movimiento, tesorería, parametrización) baja a soporte (`G-052`).
- **Las cifras salen de las mismas consultas que alimentan la consola de bodega**, para que
  el tablero y la lista que se abre al pulsarlo no puedan contradecirse. «Despachar» excluye
  las solicitudes que uno mismo creó: quien pide no autoriza, así que no están esperándole.
- **Solo para bodega, logística y administración.** El aliado no ve las tres acciones; una
  prueba lo comprueba, porque una consola que ofrece lo que el rol no puede hacer es peor que
  una que no lo ofrece.
- **DQ-07, un desborde que ninguna de las dos vistas habituales mostraba.** El panel de
  movimiento se salía 25 px a 768 px: `inline-form` fija 88+88+150 px que no se encogen y
  `.ops-bottom` reparte tres columnas cuyo mínimo es el min-content. Solo ocurría entre 761 y
  1024 px, la banda donde no llega la regla móvil. Lo encontró `audit:visual`, no la vista.
- Evidencia: `npm run verify` verde con 52/52 Playwright (dos pruebas nuevas, web y móvil),
  `audit:a11y` en 0 sobre 14 superficies y `audit:visual` con 70 mediciones sin desbordes.


### Solicitud logística generalizada · 2026-08-20 (Fases A y B del loop maestro)

- **El eje P0 del documento maestro: un centro le pide producto a otro, aunque sean
  organizaciones distintas.** `transfer_requests` servía para el traslado interno y solo para
  eso: una categoría, una unidad y una cantidad, entre dos bodegas de la misma organización.
  No se creó un segundo motor: se extendió el que había (`G-050`, ADR-015 a ADR-017).
- **Cabecera + N líneas.** `transfer_request_items` guarda cada producto pedido y la cabecera
  deja de llevar categoría, unidad y cantidad. Una solicitud puede pedir 500 litros de agua,
  100 mercados y todas las cobijas que haya, en una sola operación.
- **Los tres modos, resueltos donde tienen que resolverse.** `exact_quantity` viaja con su
  cifra; `full_lot` y `all_available` viajan **sin cantidad**: la pone PostgreSQL al autorizar,
  con los lotes ya bloqueados en un orden idéntico en toda transacción. Lo comprueba la prueba
  de concurrencia: dos autorizaciones simultáneas de «todo lo disponible» sobre 120 unidades
  reservan 120 y la segunda se rechaza con su razón, en vez de quedar autorizada y vacía.
- **Pedir no es leer.** La cabecera separa la organización proveedora de la solicitante, y lo
  único que atraviesa el tenant son tres funciones con compuerta explícita:
  `shared_stock_availability` (centro, categoría, unidad, disponible, cadena de frío y fecha
  del último movimiento), `logistics_requests` y `shipment_reconciliation_lines`.
  `verify-rls.mjs` lo ejerce contra la API real con una cuenta que pertenece a **una sola**
  organización: puede ver la disponibilidad y crear su solicitud, y no lee ni los puntos, ni
  los lotes, ni los aportes, ni la auditoría, ni la evidencia de quien provee.
- **La política es de quien provee.** `inventory_locations.shares_availability` decide si una
  bodega publica su disponibilidad a la red del evento; si la apaga, desaparece de la
  proyección y deja de aceptar solicitudes externas en el mismo instante.
- **Autorización parcial por línea**, con `transfer_request_decisions` append-only para que
  quien pidió 500 y recibió 350 pueda leer por qué, aunque la auditoría de quien decide sea
  privada. Una cantidad exacta que no alcanza no se recorta en silencio; una línea de la
  decisión que no pertenece a la solicitud tampoco se ignora en silencio.
- **Recibir producto a producto (`delivery_items`).** El cálculo anterior repartía lo recibido
  en proporción a lo despachado: con un solo producto era exacto y con varios inventaba
  números. Y el inventario que nace en el destino ahora pertenece a **la organización que
  recibe**, no a la que despachó: sin eso, un traslado entre organizaciones dejaba producto en
  una bodega cuya dueña no podía leerlo. Las entregas históricas se convirtieron en líneas con
  el mismo reparto que la vista venía aplicando, para que ninguna cifra cambiara.
- **La consola cambia de verbo.** La etapa 03 pasa de «Trasladar» a «Solicitar»: se elige a qué
  bodega se le pide —propia o de otra organización, desde la disponibilidad publicada—, se
  añaden productos con su modo, y quien provee autoriza línea por línea. Al recibir no se
  escribe el faltante: se deduce de lo despachado menos lo recibido y lo dañado.
- **Dos cosas que encontró la ejecución y no la revisión.** La clave de idempotencia estaba
  acotada a la organización proveedora: con dos solicitantes distintos eso era un espacio de
  claves compartido, y una colisión le habría devuelto a uno el código de la solicitud del
  otro. Y una comprobación nueva usaba el alias `item` dentro de un procedimiento cuya variable
  de recorrido también se llama `item`: compilaba, y reventaba al ejecutarse. La lección del
  ciclo anterior sigue vigente: una migración que compila no es una migración que funciona.
- **Límite deliberado (`G-051`):** pedir *un lote concreto* a otra organización no es posible,
  porque elegir un lote exige verlo y la disponibilidad publicada es agregada. Dentro de la
  propia organización el lote completo sí funciona.
- Evidencia: 453/453 pgTAP (49 nuevas del recorrido completo entre dos organizaciones), RLS
  con la cuenta de una sola organización, dos concurrencias, build, 48/48 Playwright,
  `audit:a11y` en 0 sobre 14 superficies y `audit:visual` con 70 mediciones sin desbordes.
- El documento que dirige esta fase quedó versionado en
  `docs/MASTER_OPERATING_LOOP_2026-08-20.md`. Fase A y Fase B cerradas; sigue la Fase C.

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
