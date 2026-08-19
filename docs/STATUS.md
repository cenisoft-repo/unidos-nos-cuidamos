# Estado comprobado

Fecha: 2026-08-17 · Puerta: **G1**, sandbox con datos 100 % sintéticos.
G2 y G3 siguen bloqueadas: no deben incorporarse operadores, PII, dinero ni
comunicación institucional.

## Lo verificado

`npm run verify` pasa de extremo a extremo. Se ejecutó dos veces: la primera
reprobó por `G-033` —la suite reutilizaba un servidor de desarrollo degradado— y
la segunda, ya con el arnés aislado, salió verde completa:

| Comprobación | Resultado |
|---|---|
| `preflight:local` | ok · sin enlaces activos a proyectos remotos |
| Lint · TypeScript · build | verdes |
| Unitarias (Vitest) | 39/39 |
| SQL (pgTAP) | 218/218 sobre 28 migraciones |
| RLS (`verify-rls.mjs`) | ok · aislamiento de tenant y anonimato |
| Concurrencia | ok · doble envío produce un solo aporte |
| Playwright web + móvil | 30/30 · servidor propio y limpio (`G-033`) |
| `audit:a11y` | **0 problemas** en 11 superficies · 3 indeterminados medidos a mano |
| `audit:visual` | 55 mediciones · cero desbordes horizontales |

## Qué se cerró en este ciclo

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

### Deuda visual

`docs/ai/DESIGN_QUALITY.md` inventaría 16 superficies: **1 en nivel 0**
(Evidencias, sin interfaz), 2 en nivel 2 y 13 en nivel 3. Ninguna en 4.

**Lo que se cerró.** `DQ-01` era una brecha del instrumento, no del producto:
`audit:a11y` y `audit:visual` solo miraban seis rutas públicas, así que las
cinco consolas —donde ocurre el trabajo real— no tenían ninguna evidencia y no
podían declararse por encima de nivel 2. Ahora se auditan las once superficies,
cada una con el rol que la usa. Eso destapó dos defectos reales:

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
