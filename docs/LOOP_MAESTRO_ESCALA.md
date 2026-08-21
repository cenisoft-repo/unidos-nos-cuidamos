# RUTA SOLIDARIA — LOOP MAESTRO DE ESCALA
## Proceso único para llevar el sistema de sandbox a red humanitaria

**Versión:** 2026-08-21 · sustituye en orden de ejecución a `MASTER_OPERATING_LOOP_2026-08-20.md`, que sigue siendo la constitución funcional del recorrido.

---

# 0. CÓMO SE USA

Este documento es la fuente de trabajo. Al abrir sesión:

1. Léelo entero, una vez.
2. Lee `docs/ai/STATE.md`, `docs/GAP_LEDGER.md` y `docs/DECISIONS.md` desde ADR-001.
3. `git status`, `git log -n 8 --oneline`, y el diff pendiente.
4. Localiza en la §5 la fase abierta. **No se salta de fase.**
5. Implementa el delta más pequeño que cierre una puerta.
6. Prueba de menor a mayor coste. Repara. Documenta. Sigue.

> **NO RECONSTRUIR. REUTILIZAR → EXTENDER → CORREGIR → CREAR.**

Y una regla que este proyecto ya aprendió a su costa: **una migración que compila no es una migración que funciona**, y **un envoltorio que valida se pierde en silencio** cuando alguien reimplementa lo que envolvía. Ejecuta contra una base real antes de dar nada por cerrado.

---

# 1. QUÉ SIGNIFICA «ESCALA» AQUÍ

El encargo pide un alcance enorme. Traducido a algo que se pueda diseñar y medir, significa cuatro ejes que **no crecen juntos**:

| Eje | Hoy | Objetivo | Qué se rompe primero |
|---|---|---|---|
| **Personas alcanzadas** | decenas sintéticas | 10⁷–10⁸ | nada del backend: es alcance de lectura pública y de reporte ciudadano |
| **Operadores concurrentes** | 7 cuentas | 10⁴–10⁵ | las compuertas RLS por fila y las consolas sin paginar |
| **Volumen del libro** | 10² movimientos | 10⁸ | el Kardex agregado en cada lectura y la auditoría sin particionar |
| **Emergencias simultáneas** | 1 por despliegue | 10²–10³ | `EVENT_ID` fijado en tiempo de compilación |

**El eje que de verdad manda es el tercero y el cuarto.** Servir a cien millones de personas no exige cien millones de filas por segundo: exige que un evento con diez millones de movimientos siga respondiendo, y que caber una emergencia más no signifique un despliegue más.

Y hay un límite que no es técnico: **una plataforma humanitaria no escala más rápido que su gobernanza.** Con datos reales de personas afectadas, cada país nuevo es una base legal nueva, no un `INSERT`.

---

# 2. LA TESIS QUE ORDENA EL LOOP

> **Un recorrido —alguien pide, alguien responde, y los dos pueden probarlo— se vuelve verdadero, no dañino y proporcional a lo que se mira, en un sitio más cada vez.**

De ahí salen las tres preguntas que ordenan cualquier decisión de prioridad:

1. **¿Miente?** Una cifra recortada en silencio, un saldo que suma monedas distintas o un sello de «verificado» que nadie concedió son peores que una funcionalidad ausente. **Lo que miente se arregla antes que lo que falta.**
2. **¿Hace daño?** Un dato de una persona afectada expuesto, una dirección publicada donde hay riesgo físico, un pago sin trazabilidad. **Lo que puede herir se arregla antes que lo que incomoda.**
3. **¿Aguanta?** Lo que hoy responde en 200 ms y a 10⁶ filas no responde.

En ese orden. Un sistema lento que dice la verdad se puede operar; uno rápido que miente, no.

---

# 3. EL ESTADO REAL, CON NÚMEROS COMPROBADOS

Medido sobre el árbol al 2026-08-21, no de memoria:

| | |
|---|---|
| Migraciones | 42 · las dos últimas sin desplegar |
| Tablas con RLS | 66 · 55 políticas |
| Funciones `security definer` | **92** — la superficie que hay que auditar a mano |
| Tablas con disparador de auditoría | **31** — cada escritura genera al menos otra fila |
| Tablas append-only protegidas | 5 (`audit_events`, `stock_movements`, `financial_transactions`, `delivery_point_changes`, `intake_verification_decisions`) |
| Tablas particionadas | **0** |
| Consultas con `.range()` en todo `src/` | **0** |
| Consultas de `/operaciones/bodega` | 11, **ninguna con `limit`** |
| Suite | 63 unitarias · 500 pgTAP · 54 Playwright · RLS · 2 concurrencias |

Y el plan real de la consulta que la consola de bodega ejecuta en cada carga:

```
Sort → Hash Right Join → HashAggregate → Seq Scan on stock_movements
```

**`Seq Scan`.** El `.eq("event_id", …)` filtra `inventory_lots`, nunca el CTE que agrega el Kardex. Con 10⁸ movimientos se agregan todos para pintar una pantalla.

---

# 4. LOS DIEZ BLOQUEOS, ORDENADOS POR CUÁNDO DUELEN

No por gravedad conceptual: por el momento en que empiezan a doler. Cada uno con su evidencia.

### Duelen HOY

**B1 · El autorregistro se concede a sí mismo el sello de confianza.**
`202608190001_ally_self_registration.sql:352-353` escribe `organizations(..., verified, ...) values (..., true, ...)`. ADR-013 dice que llegar a `verified` exige `decide_organization_verification` con actor y sustento. `/donar` filtra por `organizations.verified`. Cualquiera que complete el autorregistro aparece como organización verificada. **Contradice una decisión vigente del propio repositorio.**

**B2 · El resumen público de una necesidad es texto ciudadano copiado literal.**
`202608170005:89-96` publica `left(description,180)` en `public_need_projections`, tabla `anon`-legible y en Realtime. El único filtro es una expresión regular de teléfonos y cuentas. Quien verifica puede publicar o no publicar; no puede *redactar*. Un nombre propio o una dirección escritos por un ciudadano llegan intactos a la web pública.

**B3 · El armazón sin conexión no existe, y lo que cachea no debería.**
El service worker cacheaba toda GET del mismo origen —incluidas las consolas autenticadas— y `signOut()` no borra nada. Además `APP_SHELL` listaba `/icon.svg`, borrado al cambiar la identidad, y `cache.addAll` es atómico: **el trabajador no llegaba a instalarse**. *Corregido el 2026-08-21: rutas privadas excluidas, instalación tolerante a faltantes y purga por mensaje. Queda pendiente disparar la purga al cerrar sesión.*

### Duele a partir de la fila 1.001

**B4 · Corte silencioso presentado como cifra cierta.**
`supabase/config.toml:18` fija `max_rows = 1000`. En todo `src/` hay **cero** llamadas a `.range()`. Las consolas, el portal, transparencia y **las dos rutas de exportación a Excel** piden sin paginar: a partir de la fila 1.001 PostgREST corta y nadie se entera. La hoja «Resumen» publica el `length` de un arreglo ya truncado. Es exactamente el defecto que `202608160006_treasury_balance.sql` documenta haber corregido para el saldo… y que sigue vivo en todo lo demás.

### Duele a 10⁵

**B5 · La idempotencia se busca sin índice utilizable.**
`202608190005:1270-1273` busca `stock_movements.idempotency_key` sin aportar `organization_id`; el único índice es `unique (organization_id, idempotency_key)`, sin prefijo aprovechable. Mismo patrón en `reserve_lot_quantity`, `allocate_stock`, `create_shipment` y `reconcile_sandbox_payment`. Cada recepción y cada reserva recorren la tabla entera. **Es el mejor coste/beneficio de toda la lista: son cuatro índices.**

### Duele a 10⁶

**B6 · El Kardex se agrega entero en cada lectura.**
`202608210001:1094-1131`. Y peor: `transfer_request_lines` lo invoca con una subconsulta correlacionada **por línea**, desde `logistics_requests`, que no tiene cota ni límite. El coste es (agregación completa) × (líneas) × (solicitudes). *Trampa a tener en cuenta al materializar:* `register_delivery` escribe el `transfer_in` sobre el lote **nuevo** del destino y ninguna fila contra el lote de origen, así que un disparador sobre `stock_movements` no basta — hay que alimentarlo también desde `delivery_items`.

### Duele a 10⁶–10⁷

**B7 · Las compuertas se evalúan por fila y desde SUPER_ADMIN cuestan el doble.**
`is_org_member(organization_id, event_id)` usa columnas de la fila, así que no se iza a InitPlan. Desde `202608200002`, cada llamada ejecuta primero `is_super_admin()`, un segundo `EXISTS` sobre `memberships` filtrando por `role`, columna ausente del índice de búsqueda. `auth.uid()` sí está envuelto en `(select …)`; las compuertas no. Se aplicó la optimización a la mitad barata.

### Duele a los meses

**B8 · La auditoría duplica la escritura del sistema, no se puede podar y no está particionada.**
31 tablas con disparador, `prevent_mutation` prohibiendo `UPDATE`/`DELETE`, cero particiones, cero BRIN, cero retención. La misma inmutabilidad que la hace confiable la hace impodable. Con varios países, además, las retenciones legales difieren por jurisdicción. Es la única append-only cuya clave es un sustituto sin significado de negocio: **la única particionable sin dolor**.

### Duele en la segunda emergencia

**B9 · Un despliegue sirve un solo evento.**
`src/lib/constants.ts:27` — `EVENT_ID` incrustado en compilación, usado en 17 archivos. El esquema es multievento; la aplicación no. Es el multiplicador que convierte cada bloqueo anterior en N bloqueos: N tuberías, N juegos de secretos, N regímenes de respaldo, N guardias.

### Duele en la segunda moneda

**B10 · El libro suma monedas distintas y lo llama saldo conciliado.**
`202608160006:33-44` suma `amount` sin agrupar por `currency`. `src/lib/format.ts` fija `es-CO`/`COP`, y la consola de tesorería formatea el importe con el formateador de pesos y le concatena al lado la moneda real del cobro. Parece verificado y no lo es.

---

# 5. LAS FASES Y SUS PUERTAS

Cada fase termina cuando su puerta está **verde y automatizada**. Una puerta que se comprueba a ojo no es una puerta.

## F0 · Instrumentar antes de tocar
**Propósito:** no se optimiza lo que no se mide, y no se declara verde lo que nadie comprueba.
**Sale:** un entorno con volumen sintético realista (10⁶ movimientos, 10⁴ solicitudes, 10³ operadores), un catálogo de consultas con su tiempo actual, y `npm run verify` corriendo en integración continua sobre ese volumen.
**Puerta:** existe `scripts/seed-volumen.mjs` y un informe con el tiempo de las 15 consultas del camino caliente. **Ninguna optimización posterior se acepta sin su línea base.**

## F1 · Que deje de mentir
**Propósito:** B1, B2, B4 y B3. Nada de esto es rendimiento: es veracidad.
**Puerta:** el autorregistro nace `email_verified` y jamás `verified`; publicar una necesidad exige un resumen escrito por quien verifica; ninguna consulta devuelve una lista sin declarar su corte —o pagina, o dice «hay más»—; y una prueba automática falla si aparece un `.from(...).select(...)` sin `range` ni `limit` en una ruta de listado.

## F2 · Que no haga daño
**Propósito:** los controles que faltan antes de que entre un solo dato real.
**Puerta:** rate limiting de borde (`G-015`); rotación de secretos y CIDR del primario cerrado; purga de caché al cerrar sesión; el detalle del mapa público configurable **en caliente** por quien opera en terreno, no por despliegue; y `confirm_payment_intent` deja de estar concedida a `anon` en cuanto exista un proveedor real, con marca de tiempo dentro de lo firmado y rotación con secreto anterior.

## F3 · Que aguante el volumen
**Propósito:** B5, B6, B7, B8, en ese orden —de lo barato a lo caro.
**Puerta:** con el volumen de F0, ninguna consulta del camino caliente supera 200 ms en p95; `stock_movements` y `audit_events` particionadas por rango temporal con retención por `DETACH`; y el saldo por lote materializado con disparador, alimentado desde las dos fuentes.

## F4 · Multievento en un solo despliegue
**Propósito:** B9. Es la fase que convierte el producto en plataforma.
**Puerta:** un despliegue sirve N emergencias; el evento se resuelve por petición y no por compilación; y una prueba comprueba que un actor de un evento no ve absolutamente nada del otro. **No se entra en F4 sin la auditoría de lectura de F6**, porque consolidar despliegues elimina la única compartimentación real que hoy existe.

## F5 · Multipaís y multimoneda
**Propósito:** B10 y la estructura que lo sostiene.
**Puerta:** el libro nunca suma monedas distintas —ni puede, por restricción—; cada organización declara país, responsable del tratamiento y régimen de retención; el territorio deja de asumir DIVIPOLA; y la interfaz existe en al menos dos idiomas con la misma cobertura de auditoría.

## F6 · Gobernanza observable
**Propósito:** que se pueda demostrar quién hizo qué, incluido quien lo puede todo. Ver §6 y §8.
**Puerta:** un identificador de correlación por transacción (`G-026`); auditoría **de lectura** en las funciones que atraviesan el tenant; elevación temporal de SUPER_ADMIN con motivo y caducidad; y la consola de auditoría reconstruye una operación completa desde una sola referencia.

## F7 · Financiero de grado institucional
**Propósito:** la §7 entera.
**Puerta:** partida doble balanceada por restricción; cierre de período que congela; conciliación bancaria con cola de no casados; y un dictamen externo que reproduce el saldo desde el libro sin ayuda del equipo.

## F8 · Operación 24/7
**Propósito:** que exista quien responda a las 3 de la mañana.
**Puerta:** despliegue sin intervención manual con migración y front en la misma tubería; PITR con restauración **probada**; SLO con presupuesto de error; guardia con nombres y relevo. **Esta fase la desbloquea una decisión humana, no código.**

---

# 6. SUPER_ADMIN: OPERABILIDAD Y FACULTAD DE AUDITORÍA

Hoy SUPER_ADMIN está bien planteado —es un valor más de `app_role`, el alcance vive en las cuatro compuertas, no hay bypass de RLS, se concede fuera de banda y un disparador impide escribir esa fila por otra vía (ADR-010, ADR-011)—. **Lo que le falta no es poder: es contrapeso y ergonomía.**

## 6.1 Los cuatro problemas a escala

1. **Sus lecturas son invisibles.** Escribir queda auditado; **leer no**. Una autoridad global puede recorrer la evidencia privada, los donantes y los contactos de cualquier organización sin dejar rastro. Con 20 organizaciones es un riesgo; con 2.000 es indefendible ante cualquiera de ellas.
2. **El poder es total y permanente.** No hay elevación temporal, ni motivo, ni caducidad. Quien lo tiene, lo tiene siempre y para todo.
3. **Es una sola llave para catorce cerraduras.** Administrar usuarios, editar catálogos, abrir un canal de recaudo real y leer auditoría son riesgos distintos con un solo permiso.
4. **Cuesta el doble en cada fila** (B7): cada compuerta evalúa `is_super_admin()` antes que su propia regla.

## 6.2 Lo que hay que construir

**a) Auditoría de lectura en la frontera del tenant.** Las funciones `security definer` que atraviesan organizaciones —`shared_stock_availability`, `logistics_requests`, `treasury_provider_payments`, `intake_evidence_for_review` y las que vengan— registran *quién consultó qué y cuándo* en un flujo append-only propio. No el contenido: la consulta. Sin esto, «no hay bypass» es una afirmación sobre escrituras que se lee como si fuera sobre todo.

**b) Elevación temporal (JIT).** `grant_super_admin` pasa a conceder una ventana: motivo obligatorio, caducidad, y revocación automática. Lo permanente es la capacidad de elevarse, no la elevación.

**c) Capacidades en vez de una llave maestra.** Sobre los roles actuales —que se quedan como agrupadores (§22 de la constitución)— una capa de capacidades: `audit.read`, `users.manage`, `config.write`, `payments.enable`, `tenant.read`. Abrir un canal de recaudo real exige `payments.enable` y **cuatro ojos**: dos autoridades distintas, registradas.

**d) El vigilante también es vigilado.** Todo lo que hace una autoridad global va a un flujo que **una parte distinta** puede leer —auditoría interna, junta, o el operador humanitario—. Un registro que solo puede leer quien lo genera no es un control.

**e) Coste.** `is_super_admin()` se resuelve una vez por sentencia, no por fila: envolver las compuertas en `(select …)` para que se icen a InitPlan, e indexar `memberships (user_id, role) where active`.

## 6.3 La consola de auditoría

Cuatro vistas, y ninguna es una tabla de `audit_events` en crudo:

| Vista | Responde a | Fuente |
|---|---|---|
| **Línea de tiempo de una operación** | «¿qué pasó exactamente con APO-XXXX?» | correlación única (`G-026`) sobre todas las tablas tocadas |
| **Actividad de un actor** | «¿qué hizo esta persona en esta ventana?» | `audit_events` + flujo de lecturas |
| **Accesos que cruzaron organización** | «¿quién miró lo de otro y por qué?» | flujo de lecturas + motivo de elevación |
| **Cambios de contrato** | «¿quién cambió una regla, no un dato?» | catálogos, canales de pago, roles, alcance |

Cada vista exporta con firma y sello de tiempo. Ese export **es** el entregable de una auditoría externa.

---

# 7. LA ESTRUCTURA FINANCIERA MÁS SEGURA Y FUNCIONAL

## 7.1 Lo que ya está bien y no se toca

- `financial_transactions` es **append-only por disparador**: sin `UPDATE`, sin `DELETE`. Las correcciones compensan.
- Separación de funciones real: quien solicita un gasto no lo aprueba, quien aprueba no paga, quien aporta no concilia.
- El saldo solo cuenta lo `reconciled`: **confirmar no es conciliar** (ADR-018).
- Idempotencia por `(organization_id, idempotency_key)` y unicidad por `(provider, provider_reference_private)`.
- La plataforma **no ve datos de medio de pago**: ni tarjeta, ni cuenta, ni token (ADR-019).
- El vocabulario correcto ya existe: `credit, debit, reversal, refund, chargeback`.

## 7.2 El defecto estructural

**`financial_accounts` existe y está huérfana.** `financial_transactions` no tiene **ni una sola columna** que apunte a una cuenta —comprobado—, y la tabla tiene RLS activada **sin ninguna política**, así que nadie la lee. Es decir: hay un plan de cuentas que no participa en el libro.

Consecuencia: los movimientos son **de una sola pata**. Un `credit` sobre un fondo dice que entró dinero, pero no de dónde ni contra qué. No hay ecuación contable, así que no hay cuadre posible: la única comprobación es «la suma de lo que marqué conciliado». Eso basta para un sandbox y **no basta para un dictamen**.

## 7.3 La estructura objetivo

**a) Partida doble, impuesta por restricción y no por disciplina.**
Cada hecho financiero es una transacción con **N asientos** (`financial_entries`: transacción, cuenta, dirección, importe, moneda). Una restricción diferida exige que **la suma de débitos iguale la de créditos por transacción y por moneda**. Si no cuadra, no entra. La contabilidad deja de depender de que nadie se equivoque.

**b) Plan de cuentas por fondo, con naturaleza declarada.**
`financial_accounts` gana `kind` (`caja`, `banco`, `pasarela`, `ingreso`, `gasto`, `obligación`), `currency`, y `restricted` — porque en el mundo humanitario **un fondo restringido no es dinero disponible**, y hoy no hay forma de decirlo. Un donante que da para agua en Manizales no financia logística en Cali, y el sistema debe poder demostrar que no lo hizo.

**c) La moneda es del asiento, no del informe.**
Cada asiento lleva su moneda; **sumar monedas distintas es imposible por restricción**, no por convención. Si se necesita un consolidado, se hace con una tasa fechada y almacenada (`fx_rates`), y el informe declara la tasa que usó. Cierra B10.

**d) Períodos contables que congelan.**
`accounting_periods (fund_id, desde, hasta, estado)`. Cerrado un período, ningún asiento con fecha dentro entra: lo que llegue tarde se registra en el período abierto con referencia al original. Es lo que permite decir «el saldo a 31 de marzo era X» y que siga siendo X en junio.

**e) Conciliación bancaria de verdad.**
Importación de extracto → propuesta de casación → **cola de no casados** con antigüedad. Hoy la referencia del extracto se escribe a mano en un campo de texto. Un no casado que envejece es la señal más temprana de fraude o de error, y hoy no existe.

**f) El ciclo completo del cobro.**
El enum ya contempla `refund` y `chargeback`; **no hay flujo para ninguno**. Un contracargo que no se puede registrar es un saldo que miente. Con proveedor real hay que cerrar: reembolso total y parcial, contracargo, disputa y su resolución — todos como asientos compensatorios, nunca como edición.

**g) Controles proporcionales al importe.**
Umbral configurable por evento: por encima, doble aprobación. Listas restrictivas y marca de operación inusual antes del primer peso real: una plataforma que recauda para emergencias sin control AML es un vehículo de lavado por diseño.

**h) Todo movimiento, correlacionado.**
Cada escritura financiera comparte identificador de correlación con la auditoría de su transacción (`G-026`). Reconstruir «qué pasó con este dinero» deja de ser cruzar por marca de tiempo y confiar en que no hubo concurrencia.

---

# 8. DASHBOARDS PROYECTADOS

Regla que gobierna todos: **una cifra sin fuente, fórmula y corte no se publica.** Y cada tablero declara explícitamente *qué no dice* — una promesa no es impacto, un cobro confirmado no es saldo, una foto no es verificación.

## 8.1 Público — rendición de cuentas
| Tablero | Cifras | Estado |
|---|---|---|
| Transparencia | prometido · recibido · disponible · reservado · en tránsito · entregado, sin mezclar unidades | **existe**, falta serie temporal (`G-027`) |
| Mapa de ayuda en movimiento | origen → destino, sin dirección privada | **existe** |
| Evidencia verificada | solo lo aprobado para publicación | falta (`DQ-02`) |
| Impacto por corte | cada métrica con su corte conciliado y su método | falta (`G-027`) |

## 8.2 Operación — decidir hoy
| Tablero | Responde a |
|---|---|
| Torre de control multievento | ¿dónde está tensionada la red ahora mismo? *(exige F4)* |
| Cobertura de necesidades | ¿qué se pidió, qué se cubrió, qué lleva más tiempo esperando? |
| Salud del inventario | vencimientos próximos, lotes bloqueados, existencia inmóvil |
| Movimiento y novedades | qué está en tránsito, qué llegó con faltante, qué no concilia |
| Rendimiento del recorrido | horas entre reporte → verificación → despacho → entrega |

## 8.3 Financiero
| Tablero | Cifras |
|---|---|
| Posición por fondo | saldo **por moneda**, restringido vs. libre, comprometido vs. disponible |
| Cobros | confirmados sin conciliar, con antigüedad; fallidos y su razón; reembolsos y contracargos |
| Conciliación | no casados por antigüedad; diferencias; período abierto |
| Gasto | por categoría y por fondo, con su aprobación y su soporte |
| Trazabilidad donante | de un aporte a lo que financió, sin exponer al donante |

## 8.4 Auditoría y autoridad global
Las cuatro vistas de la §6.3, más **salud de la propia auditoría**: filas por día, cobertura por tabla, y **huecos** —operaciones críticas sin correlación—.

## 8.5 Ingeniería
SLO y presupuesto de error, latencia p95 por consulta del camino caliente contra la línea base de F0, errores por ruta, crecimiento de las tablas append-only y proyección de cuándo tocan el límite.

---

# 9. REGLAS INNEGOCIABLES

1. **El Kardex es la fuente de verdad.** Nunca escritura directa de existencias.
2. **El libro financiero es append-only.** Se compensa, no se corrige.
3. **RLS en toda tabla expuesta.** Ocultar un botón no es seguridad.
4. **Ninguna cifra pública sin fuente, fórmula y corte.**
5. **Confirmar ≠ conciliar. Evidencia cargada ≠ operación confirmada ≠ evidencia publicada.**
6. **Nunca `service_role` en el servidor web.** Hoy `src/` no contiene ninguna; que siga así.
7. **Una migración aplicada es historia.** Se compensa; no se reescribe.
8. **No se relaja una prueba para que pase.** Se corrige la causa.
9. **Sin datos reales, dinero real ni comunicación institucional** hasta que `G-002`–`G-006` estén cerradas por decisión humana.
10. **Nada se despliega ni se comitea sin instrucción explícita.**
11. **Números reales.** Si no se midió, no se afirma.

---

# 10. CÓMO SE MIDE SIN PODER ENGAÑARSE

- **La puerta es un comando**, no una opinión: `npm run verify`, `audit:a11y`, `audit:visual`, y el nuevo `verify:carga` de F0.
- **Un control que no puede fallar no prueba nada.** Toda puerta nueva se valida **rompiéndola a propósito** una vez, y se anota que se hizo. Así se validó la puerta de movimiento reducido.
- **Cada defecto cerrado deja una aserción permanente.** Si un arreglo no se puede convertir en prueba, se registra como brecha con dueño y espera.
- **El avance se cuenta en puertas cerradas**, no en tareas hechas.
- **Lo omitido se declara.** Un recorte silencioso —de filas, de cobertura, de alcance— se reporta como tal.

---

# 11. QUÉ DEJA FUERA ESTE LOOP, EXPLÍCITAMENTE

Un loop que lo abarca todo no ordena nada.

- **No** construye un ERP: ni licitaciones, ni contratos, ni nómina.
- **No** abre multi-región activa-activa antes de que exista un ADR de disponibilidad.
- **No** sustituye sistemas de identidad humanitaria existentes: interopera cuando toque.
- **No** hace aprendizaje automático de nada. Ni priorización algorítmica de necesidades: eso decide quién recibe ayuda antes, y no es una decisión de software.
- **No** optimiza nada que no esté en el catálogo medido de F0.
- **No** persigue el nivel 4 de `DESIGN_QUALITY` sin prueba de uso con personas.

---

# 12. LO QUE NO DESBLOQUEA ESCRIBIR CÓDIGO

Se persiguen en carril paralelo, **con nombre y fecha**, y no se sustituyen escribiendo una política conservadora que luego pase por aprobada.

| # | Decisión | Bloquea |
|---|---|---|
| 1 | Entidad operadora, RACI y guardia con nombres (`G-002`) | F8 |
| 2 | Responsable del tratamiento, jurisdicción y base legal por país (`G-005`) | toda entrada de PII real |
| 3 | Política de aceptación y verificación documental (`G-003`) | que una organización llegue a `verified` |
| 4 | Contrato, credenciales y KYB del proveedor de pago (`G-004`, `G-054`) | F7 con dinero real |
| 5 | Política AML y umbrales | el primer peso real |
| 6 | Residencia de datos, transferencias y subencargados | F5 |
| 7 | Plazos de retención por clase de dato | el mecanismo no; el número de días sí |
| 8 | Presupuesto de infraestructura | PITR, staging con volumen, guardia |
| 9 | Detalle del mapa público donde hay riesgo físico | lo decide quien opera en terreno |
| 10 | SMTP propio y confirmación de correo (`G-044`, `G-045`) | el primer aliado real — **es lo más barato de la lista** |
| 11 | Rotar la contraseña de base expuesta y cerrar el CIDR del primario | requiere panel, no código |

---

# 13. FORMATO DE RESPUESTA

Tras cada delta, y nada más:

**IMPLEMENTADO · MIGRACIONES · ARCHIVOS · SEGURIDAD · TESTS · HALLAZGOS · PENDIENTES · SIGUIENTE DELTA**

Máximo detalle donde haya riesgo. Mínimo texto narrativo. Números medidos.

---

# 14. ARRANQUE

La fase abierta es **F0**. La primera acción exacta:

> Escribir `scripts/seed-volumen.mjs` (10⁶ movimientos, 10⁴ solicitudes, 10³ operadores, por las RPC reales) y `scripts/verify-carga.mjs`, que cronometra las 15 consultas del camino caliente y falla si alguna supera su línea base. Sin esa línea base, ninguna optimización posterior se puede defender.

Y en paralelo, porque es de hoy y es barato: los cuatro índices de idempotencia de **B5**.
