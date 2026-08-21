# Registro de decisiones

## ADR-001 · 2026-08-13 · Supabase como backend transaccional

Decisión: usar Supabase local (PostgreSQL 17, Auth, Storage y Realtime) con migraciones versionadas, RLS y funciones SQL transaccionales. Next.js App Router/TypeScript será PWA y BFF cuando sea necesario.

Motivo: cubre base relacional, geoespacial, autenticación, almacenamiento privado y desarrollo reproducible con Docker, reduciendo piezas operativas sin renunciar a invariantes de datos.

Consecuencia: lógica crítica vive en PostgreSQL/RPC; el cliente nunca recibe `service_role`. Una futura cola robusta/observabilidad administrada deberá validarse antes de piloto.

## ADR-002 · 2026-08-13 · Sandbox estricto y proyecciones públicas

Decisión: usar exclusivamente datos sintéticos, proveedor financiero simulado y vistas/RPC públicas con lista explícita de campos. Evidencia privada en bucket no público.

Motivo: no existe autorización de operador, tratamiento, marcas, recaudo, migración o despliegue.

Consecuencia: G0/G1 pueden avanzar; G2/G3 permanecen bloqueadas hasta aprobación humana.

## ADR-003 · 2026-08-13 · Interfaz operativa de calma

Decisión: jerarquía sobria, alto contraste, listas equivalentes al mapa, estados textuales además del color, rojo solo para riesgo crítico y movimiento reducido.

Motivo: operadores y ciudadanía actuarán bajo presión, en móvil y con conectividad limitada.

## ADR-004 · 2026-08-14 · Centro territorial local y privacidad geoespacial

Decisión: usar MapLibre GL JS con una base cartográfica local de Natural Earth y puntos aproximados servidos por una RPC PostGIS `security invoker`. La proyección pública participa en Supabase Realtime bajo su RLS existente.

Motivo: ofrecer zoom, agrupación, intensidad territorial y actualización en vivo sin llaves propietarias ni dependencia de un proveedor de teselas. PostGIS permite encuadres indexados a medida que crezca el volumen.

Consecuencia: el mapa público nunca recibe direcciones o rutas operacionales; solo renderiza coordenadas ya aprobadas en `public_need_projections`. Una futura cartografía detallada deberá incluir licencia, caché y evaluación de conectividad antes del piloto.

## ADR-005 · 2026-08-14 · Cartografía real dual y logística aproximada

Decisión: sustituir la silueta Natural Earth de ADR-004 por MapLibre/OpenFreeMap y añadir Leaflet/OpenStreetMap cuando WebGL no esté disponible. Centros y despachos se publican desde `public_logistics_projections`, derivada por triggers y disponible en Realtime bajo RLS.

Motivo: una cartografía útil necesita calles y topónimos reales incluso en navegadores limitados, sin convertir el mapa público en GPS ni exponer la operación.

Consecuencia: la base cartográfica depende de servicios externos sin SLA para este sandbox y conserva atribución. Los endpoints son configurables. Antes de G2 se deberá escoger un proveedor con contrato/cuota o infraestructura propia; las claves no se infieren, no se versionan y no se exponen si son privilegiadas. La línea de despacho solo representa origen-destino aproximado.

## ADR-006 · 2026-08-14 · Preview remoto sin promoción a piloto

Decisión: publicar el código en un repositorio privado y desplegar un preview de Vercel conectado a un proyecto Supabase remoto vacío, migrado únicamente con fixtures sintéticos. Las funciones `SECURITY DEFINER` parten de denegación y reciben permisos explícitos; el intake de aportes exige membresía autenticada.

Motivo: habilitar una revisión remota autorizada sin confundirla con un sistema operativo, recaudo, campaña pública o piloto con datos vivos.

Consecuencia: la publicación técnica sigue siendo G1 sandbox. No habilita marcas institucionales, PII real, GPS, pagos, comunicaciones, evidencias reales ni atención de emergencias. G2/G3 conservan sus puertas humanas, jurídicas, operativas y de observabilidad.

## ADR-007 · 2026-08-19 · Autorregistro ALIADO con el correo como puerta

Decisión: abrir `auth.enable_signup` y exigir `enable_confirmations`. Crear la identidad no otorga nada: sin membresía activa las políticas RLS no devuelven una sola fila operativa. El rol ALIADO se entrega únicamente en `activate_ally_registration()`, que exige `email_confirmed_at` y crea organización, membresía `partner_reporter` y el punto de acopio propio del aliado. La organización queda verificada con un registro explícito de método `self_registration_email_confirmed`.

Motivo: la Fase 2 del loop pide un solo registro para empresa, organización, ONG, fundación, entidad y persona aportante, con la confirmación de correo como condición para operar. Mantener el alta cerrada obligaba a provisionar cada aliado a mano.

Consecuencia: la verificación de una organización autorregistrada es la de un correo confirmado, no la de un NIT comprobado documentalmente. Queda escrita como tal y con vigencia de 90 días. Antes de G2, incorporar aliados reales exige una verificación documental y una política de aceptación aprobada; no basta con este control.

## ADR-008 · 2026-08-19 · El Kardex es la única fuente de la posición de inventario

Decisión: derivar físico, disponible, reservado, en movimiento y entregado de `stock_movements` y de las entregas conciliadas, mediante `inventory_lot_positions`. No se agrega ninguna columna de saldo y `inventory_lots.quantity_initial` queda como lo que siempre fue: la cantidad con la que nació el lote.

Motivo: la consola presentaba `quantity_initial` como si fuera existencia disponible y la usaba como tope de reserva. Era un contador independiente que solo coincidía con la realidad el día de la recepción.

Consecuencia: cualquier cifra de inventario se puede reconstruir desde el historial append-only, y una cifra que no cuadre es un error de movimientos, no de sincronización. El costo es que la posición se calcula en cada consulta; si el volumen lo exige, la salida natural es materializar la vista, no volver a los contadores.

## ADR-009 · 2026-08-19 · El traslado entre bodegas reutiliza reserva y despacho

Decisión: modelar Centro A → Centro B con `transfer_requests` y las piezas que ya existían: la reserva es una fila de `allocations` con su movimiento `reserve`, y la salida es `release` + `transfer_out`. El inventario del destino nace solo cuando el destino confirma, en la misma `register_delivery` que concilia una entrega a una necesidad.

Motivo: el eje bodega a bodega no existía —`transfer_in`/`transfer_out` estaban declarados y sin usar— y construirlo aparte habría creado una segunda forma de mover inventario.

Consecuencia: `allocations.need_item_id` pasa a ser opcional y excluyente con `transfer_request_id`. `validate_delivery` rechaza los traslados: un movimiento entre bodegas no publica impacto ni cubre una necesidad, se cierra con la confirmación del destino.

## ADR-010 · 2026-08-18 · SUPER_ADMIN es alcance, no un segundo RBAC

Decisión: `super_admin` es un valor más de `app_role` y se concede con una fila en `memberships`, igual que cualquier otro rol. Su autoridad global no vive en una tabla nueva ni en un claim del token: vive en las cuatro funciones de compuerta que ya usaban todas las políticas y todas las RPC (`is_org_member`, `has_any_role`, `has_event_role`, `has_location_scope`), cada una con su regla original más `or is_super_admin()`.

Motivo: crear un segundo sistema de permisos habría duplicado la superficie que hay que auditar y habría abierto la puerta a que las dos discreparan. Extender las compuertas mantiene una sola respuesta a «¿puede esta persona?», que es la de PostgreSQL.

Consecuencia: SUPER_ADMIN no es un bypass. RLS sigue habilitada, el inventario sigue sin política de escritura directa y ninguna RPC de operación tiene una rama especial: si la autoridad global modifica existencias, lo hace con el mismo movimiento, el mismo Kardex y la misma auditoría que cualquiera. La organización y el evento de su fila de membresía no acotan nada; están porque las columnas son obligatorias.

## ADR-011 · 2026-08-18 · La autoridad global no se concede desde la aplicación

Decisión: `assign_membership_role` rechaza el rol `super_admin` y rechaza actuar sobre uno mismo. Conceder o revocar autoridad global solo es posible con `grant_super_admin` / `revoke_super_admin`, revocadas para `anon` y `authenticated`, alcanzables únicamente con `service_role` y obligadas a registrar un motivo.

Y no es solo una convención: un disparador `before insert or update` sobre `memberships` bloquea escribir o alterar una fila con rol `super_admin` fuera de esas dos funciones, que ponen una marca local a la transacción. Hace falta porque `service_role` tiene INSERT y UPDATE sobre esa tabla para el arranque en frío (ADR previo, `202608160004`): sin el disparador, la vía sancionada era la difícil y la silenciosa —una fila escrita a mano, sin motivo, sin actor y sin auditoría— era la fácil.

Motivo: una consola que reparte el permiso más alto es un único punto de compromiso. Y una consola donde alguien puede editar su propia membresía deja de ser auditable frente a quien la usa.

Consecuencia: incorporar una autoridad global en producción es una operación fuera de banda, con credencial de servicio y su registro en `audit_events`. Hay que preverlo en el runbook de despliegue; no es un olvido. El propio `seed.sql` la siembra por esa vía, de modo que el sandbox ejercita el camino real en cada `db:reset`.

## ADR-012 · 2026-08-18 · La parametrización edita datos, nunca contratos

Decisión: el módulo de parametrización solo alcanza estructura operativa (puntos, con la RPC que ya existía), organizaciones, alcance de cuentas y una lista blanca explícita de catálogos. Quedan fuera los catálogos que sostienen invariantes —los estados declarados alimentan el mapeo a estados operativos dentro de la RPC de aporte, y los departamentos son referencia DIVIPOLA— además de toda regla de RLS, autorización, transición de despacho, tipo del Kardex, fórmula de disponibilidad y regla de concurrencia.

Motivo: parametrizar una regla es convertir un contrato en un dato editable desde una pantalla, y un contrato editable deja de poder probarse.

Consecuencia: publicar un catálogo crea una versión nueva y cierra la anterior; los aportes ya registrados conservan la versión con la que se validaron. Un elemento con historial se desactiva, no se borra. El identificador público (`slug`) de una organización existente es inmutable: aparece en proyecciones públicas y en enlaces ya emitidos, y este módulo no puede ver qué rompería al renombrarlo.

`catalog_versions` no lleva disparador de auditoría a propósito: su único escritor es `manage_catalog_values`, que ya deja un registro con motivo, versiones y el antes emparejado con el después. Añadirlo guardaría el mismo `values_json` dos veces y llamaría auditoría a la repetición.

## ADR-013 · 2026-08-18 · Confirmar un correo no verifica una organización

Decisión: `organization_verifications.state` distingue `email_verified` (el buzón responde) de `document_pending` y `verified` (revisión documental). El autorregistro solo puede llegar a `email_verified`; subir de ahí exige `decide_organization_verification`, con actor y sustento. `organizations.verified` conserva su significado —habilitada para operar— y no se confunde con el nivel de comprobación.

Motivo: escribir `verified` por haber confirmado un correo hacía indistinguible una organización comprobada de una que solo abrió un buzón, y esa distinción es exactamente la que una plataforma humanitaria necesita antes de aceptar aportes a nombre de terceros.

Consecuencia: la verificación documental en sí no se implementa aquí; depende de la política de aceptación (`G-003`). Lo que existe es el sitio correcto donde escribirla cuando esa política llegue.

## ADR-014 · 2026-08-19 · La confirmación de correo se desactiva temporalmente

Decisión: mientras el proyecto no tenga SMTP propio, el registro de aliado no exige confirmación de correo. La cuenta queda utilizable en cuanto se crea, con el correo y la contraseña que la persona elija, en el dominio que quiera.

Motivo: el servicio de correo integrado de Supabase no entrega de forma fiable a direcciones externas (`G-044`), así que exigir la confirmación dejaba el autorregistro sin salida —nadie podía completar una cuenta— sin dar a cambio ninguna garantía real, porque el correo simplemente no llegaba.

Consecuencia, dicha sin adornos: **se pierde la comprobación de que quien registra controla ese buzón.** Alguien puede registrarse con el correo de otro. Eso es tolerable hoy porque el entorno es G1 con datos sintéticos y sin aliados reales; deja de serlo en cuanto entre el primero. Queda como `G-045`.

La aplicación no codifica cuál de los dos modos está activo: mira si el alta devolvió sesión. Restablecer la puerta es volver a poner `enable_confirmations = true` y activar «Confirm sign up» en el panel, sin tocar código y sin desplegar. El `config.toml` del sandbox refleja el mismo modo que el proyecto remoto para que el recorrido se pruebe tal como se opera.

Lo que no cambia: `activate_ally_registration` sigue exigiendo `email_confirmed_at`, de modo que la activación sigue siendo un paso explícito y auditable. Lo que se relaja es quién pone esa marca —el servicio de Auth en vez del enlace del correo—, no que exista.

## ADR-015 · 2026-08-20 · Una solicitud es una cabecera con líneas, y la cantidad la decide la base

Decisión: `transfer_requests` deja de llevar categoría, unidad y cantidad. Cada producto pedido es una fila de `transfer_request_items` con su modo: `exact_quantity`, `full_lot` o `all_available`. En los dos últimos la línea **no** guarda cantidad, y la reserva la resuelve PostgreSQL al autorizar, dentro de la transacción y con los lotes ya bloqueados.

Motivo: una solicitud real casi nunca es de un solo producto, y sumar 500 litros de agua con 100 mercados en una sola cifra es exactamente el error que este proyecto ya había cometido y corregido en las proyecciones públicas. Y «todo lo disponible» calculado en el navegador es una cantidad que ya era falsa cuando se pintó: entre la lectura y la ejecución cualquier otra bodega pudo reservar.

Consecuencia: no existe un camino en el que el cliente diga cuánto hay. `reserve_transfer_item` recorre los lotes del origen por vencimiento más próximo, los toma con `select ... for update` en un orden idéntico en toda transacción —vencimiento, recepción, identificador—, y recalcula lo disponible desde el Kardex ya con el bloqueo puesto. Dos autorizaciones simultáneas de «todo lo disponible» sobre 120 unidades reservan 120, no 240; la segunda se rechaza con su razón en vez de quedar autorizada y vacía. Una cantidad exacta que no alcanza tampoco se recorta en silencio: para autorizar menos, quien autoriza escribe menos.

## ADR-016 · 2026-08-20 · Pedirle inventario a otra organización no da acceso a su información

Decisión: la solicitud distingue `organization_id` (quien provee, dueña de la bodega de origen) de `requesting_organization_id` (quien pide, dueña de la bodega de destino). Pueden ser distintas si ambas bodegas atienden el mismo evento y la de origen declara `shares_availability`. Lo único que atraviesa el tenant son tres funciones `security definer` con compuerta explícita: `shared_stock_availability` —centro, organización, categoría, unidad, disponible, cadena de frío y fecha del último movimiento—, `logistics_requests` y `shipment_reconciliation_lines`.

Motivo: la red existe para que un centro pueda pedirle a otro, y eso no puede exigir abrirle el inventario, los aportes, los donantes, la evidencia ni la auditoría de quien provee. Tampoco puede ser al revés: sin el nombre de la bodega de origen, la solicitud propia sería un identificador sin significado.

Consecuencia: quien pide sigue viendo su organización y nada más en toda tabla operacional; lo comprueba `verify-rls.mjs` contra la API real con una cuenta que solo pertenece a una organización. Como los lotes no se publican, **pedir un lote completo solo es posible dentro de la propia organización**: entre organizaciones se pide por cantidad o por todo lo disponible. Queda anotado como límite deliberado en `G-051`, no como un olvido. La política es de quien provee: si una bodega deja de compartir, desaparece de la disponibilidad y deja de aceptar solicitudes externas de inmediato.

## ADR-017 · 2026-08-20 · Lo que llega se declara producto a producto

Decisión: `register_delivery` recibe una línea por cada producto del despacho —recibido, dañado y faltante— y `delivery_items` las conserva. La cifra de la entrega es la suma de sus líneas, y la posición del Kardex se deriva de ellas. Cuando el destino es una bodega, el inventario que nace en la recepción pertenece a la organización **del destino**, no a la que despachó.

Motivo: el cálculo anterior repartía «lo recibido» en proporción a lo despachado por cada línea. Con un solo producto eso era exacto; con varios inventaba números, porque repartir 448 entre agua y cobijas no significa nada. Y en una solicitud entre organizaciones, crear el inventario de destino a nombre de quien despachó habría dejado producto en una bodega que su dueña no podía leer.

Consecuencia: cada producto concilia por separado —uno puede quedar CONFORME mientras otro queda en NOVEDAD— y el inventario del destino crece solo con lo que el destino confirmó. Las entregas ya registradas se convirtieron en líneas con el mismo reparto proporcional que la vista venía aplicando, para que ninguna cifra histórica cambiara. La consola no pide el faltante: lo deduce de lo despachado menos lo recibido y lo dañado, que es la conciliación que la base exige.

## ADR-018 · 2026-08-20 · Cobrar no es conciliar, y el libro no admite estados intermedios

Decisión: cuando el proveedor confirma un cobro, la plataforma **no escribe nada en el libro de movimientos**: la intención de cobro pasa a `confirmed` y ahí se queda. El asiento lo escribe una persona de tesorería al casar ese cobro con el extracto, y nace ya `reconciled`. El saldo, que solo suma movimientos conciliados, no se mueve hasta ese momento.

Motivo: se intentó primero lo obvio —crear el movimiento en `provider_confirmed` y actualizarlo a `reconciled` al conciliar— y el disparador `financial_transactions_immutable` lo rechazó. No fue un obstáculo: fue la respuesta. Un libro append-only no tiene asientos que cambian de estado; tiene hechos. Que el proveedor diga «pagado» es un hecho del proveedor, no del libro, y su sitio es la intención de cobro. Que tesorería lo reconozca contra el extracto sí es un hecho contable, y ese se escribe una vez.

Consecuencia: `payment_intents` es donde vive lo que está en vuelo y `financial_transactions` donde vive lo liquidado. La conciliación deriva la donación del aporte que originó el cobro —no la recibe por parámetro— para que sea imposible colgar un pago de la donación equivocada, y rechaza cobrar un importe distinto al declarado en vez de cuadrarlo por decreto. Las reglas de publicación de un aporte conciliado se extrajeron a `publish_reconciled_money_donation` y las usan los dos caminos: dos copias serían dos cifras públicas distintas para el mismo dinero.

## ADR-019 · 2026-08-20 · El webhook se autentica con el secreto del canal, no con una clave de administración

Decisión: la vuelta del proveedor entra por una ruta privada que verifica la firma HMAC del cuerpo y después llama a `confirm_payment_intent` con la **clave publicable**, enviando el secreto del canal como argumento. PostgreSQL compara ese secreto con el SHA-256 que guardó al registrar el canal y solo entonces escribe. La función está concedida a `anon` —el proveedor no tiene sesión— y lo primero que hace es esa comprobación.

Motivo: el camino habitual habría sido meter una clave `service_role` en el servidor web. Hoy `src/` no contiene ninguna, y ese es uno de los invariantes más fuertes del proyecto: una clave de administración en la aplicación convierte cualquier fallo de una ruta en un compromiso total de la base. Lo que este recorrido necesita es mucho menos que eso: poder confirmar **un** cobro concreto demostrando que se conoce el secreto de **un** canal concreto.

Consecuencia: la base nunca almacena el secreto, solo su huella; el secreto vive en el entorno de despliegue y en el proveedor. Las dos comprobaciones son independientes y ninguna sobra —la firma prueba que el mensaje no fue alterado, el secreto prueba ante la base quién llama—. Los rechazos no distinguen «referencia inexistente» de «secreto equivocado», para no dar un oráculo a quien pruebe a ciegas. Y `public_config` rechaza por nombre cualquier llave que huela a secreto (`api_key`, `token`, `clave`…), porque el sitio más probable donde alguien pegaría una credencial es el campo de configuración libre.

## ADR-020 · 2026-08-20 · La identidad es la de Fedesoft · Cenisoft, con un azul de acción propio

Decisión: la plataforma adopta la paleta institucional —azul oscuro `#0d2343`, azul claro `#008bed`, azul hielo `#f0f4f8`— y la marca real de Ruta Solidaria: el mosaico de píxeles en amarillo, azul y rojo. El activo se usa tal cual en la cabecera, en el ícono de la aplicación y como decoración de la banda del portal; no se reinterpreta en CSS.

Los cambios se hicieron sobre los tokens, no sobre cada regla: `--ink`, `--forest`, `--forest-2`, `--mint`, `--paper`, `--line` y los 98 colores sueltos del stylesheet se recolorearon **conservando la luminosidad de cada uno**. Eso es lo que hace que el contraste de toda la aplicación sobreviva a un cambio de familia cromática: lo que cambia es el tono, no la claridad.

Consecuencia, y es la parte incómoda: **el azul de identidad no sirve para escribir.** `#008bed` da 3,55:1 sobre blanco. Como fondo de un botón con texto de 14 px deja la etiqueta por debajo de AA, y como antetítulo de 12 px sobre una tarjeta teñida se queda en 4,18. Por eso hay dos azules: `--brand` (`#008bed`) para lo gráfico —el guion del antetítulo, el subrayado del titular, el mosaico— y `--forest-2` (`#0b5ea3`) para lo que es texto o lo lleva encima, con 6,67:1 sobre blanco.

Es una desviación deliberada del comparativo entregado, no un descuido, y no es negociable mientras `audit:a11y` sea una puerta: con el azul del comparativo esa puerta no puede estar verde. A ojo la diferencia es un azul algo más profundo; en la práctica es la diferencia entre poder leer la interfaz y no poder.

## ADR-021 · 2026-08-20 · El movimiento es un sistema con puerta, no un adorno

Decisión: la interfaz se mueve según tres duraciones y dos curvas declaradas como tokens (`--motion-fast`, `--motion`, `--motion-slow`, `--ease-out`, `--ease-in-out`), y el movimiento solo aparece por una de dos razones: **explicar un cambio de estado** —pulsar, enfocar, esperar una respuesta, señalar la fila bajo el puntero— o **anunciar que llega contenido** cuando una sección entra en pantalla. Nada se mueve en bucle salvo lo que indica que una operación está en curso, porque ahí la repetición es la información.

La regla de seguridad del bloque de entrada: **el contenido es visible por omisión**. El estado oculto solo se aplica bajo `[data-motion="on"]`, un atributo que pone un runtime de cliente y que no pone si el sistema operativo pide menos movimiento, si JavaScript falla o si nunca llega a ejecutarse. Una animación de entrada mal hecha esconde información para siempre, y es la clase de fallo que no se nota en la máquina de quien la escribió.

Consecuencia: `audit:a11y` estrena una segunda pasada que abre el navegador **pidiendo `prefers-reduced-motion: reduce`** y falla si algún elemento visible conserva una transición o animación efectiva. Antes el stylesheet declaraba que con esa preferencia no se movía nada y nadie lo comprobaba: una regla nueva con `!important` habría pasado sin que se notara. La puerta se probó rompiéndola a propósito —una transición con `!important` en la cabecera— y señaló las siete rutas públicas antes de revertirse. Un control que no puede fallar no prueba nada.

## ADR-022 · 2026-08-21 · La habilitación operativa de una organización tiene exactamente una puerta

Decisión: `organizations.verified` —la columna que decide si una organización puede registrar aportes y si su punto de acopio es público— sólo pasa a verdadero por `decide_organization_verification`, con actor, sustento escrito y auditoría, o por `bootstrap_organization_habilitation`, la vía de arranque en frío que exige motivo y sólo alcanza `service_role`. Un disparador sobre `organizations` rechaza cualquier otra ruta. El autorregistro crea la organización, la membresía y el punto, y **no la habilita**: nace en `false`.

Motivo: ADR-013 separó bien el *nivel de comprobación* —`organization_verifications.state`, donde el autorregistro llega como mucho a `email_verified`— del *permiso para operar*, y dejó dicho que el segundo «conserva su significado». Lo que no se vio entonces es que nadie custodiaba ese segundo. `activate_ally_registration` lo escribía en `true` (`202608190001:352-353`), y `decide_organization_verification` sólo sabía ponerlo en `false` al rechazar: **la única vía que concedía la habilitación era la que no dejaba rastro, y la vía auditada no concedía nada**. Con `enable_confirmations = false` (ADR-014) ni siquiera había comprobación del buzón. Medido contra la base local antes de tocar nada: quien llenaba el formulario quedaba habilitado y su acopio aparecía para un visitante anónimo, con su dirección.

Consecuencia, y son tres, en orden de lo que costó verlas:

**a) La regla vivía por duplicado y arreglar una copia no arreglaba nada.** La condición de publicar un acopio existe en `public_collection_centers`, que la calcula al leer, y en `sync_public_collection_projection`, que la calcula al escribir sobre `public_logistics_projections` —la tabla que alimenta el mapa y que `anon` lee directa—. Las dos tenían las mismas tres condiciones y ninguna miraba la organización. Cerrada la primera, el impostor seguía en el mapa. Lo destapó barrer las diez superficies legibles por `anon` con el nombre de una organización recién autorregistrada, no releer el código. Como la proyección es una tabla y no una vista, hace falta además un disparador que la repropague cuando cambia la habilitación: sin él, habilitar dejaría el punto invisible y rechazar lo dejaría publicado —las dos mentiras, una en cada dirección—.

**b) El disparador no puede ser `security definer`.** Se escribió así primero, y con derechos del definidor `current_user` es siempre el dueño, de modo que la comprobación no distinguía nada y la puerta era decorativa. Lo destapó la propia prueba que pone la marca de transacción a mano desde `service_role`. Con derechos del invocador, `current_user` es el rol que ejecuta de verdad: `authenticated` o `service_role` desde la API —bloqueados, aunque tengan privilegios de tabla y aunque logren poner la marca— y el dueño sólo desde dentro de una función `security definer` de este esquema. El dueño se lee del catálogo, no se incrusta.

**c) El recorrido gana un paso humano, y se dice.** Activar la cuenta ya no basta para aportar. `activate_ally_registration` devuelve `operational`, la pantalla de activación deja de prometer «ya puedes registrar aportes» cuando no es cierto, y `/donar` distingue a quien no es aliado de quien lo es y espera decisión —antes le decía «inicia sesión» a alguien que ya tenía sesión—. `manage_organization` conserva crear, renombrar y suspender, y pierde conceder: hacerlo por ahí no dejaba motivo escrito.

La puerta se validó rompiéndola: reintroducido el `verified = true` del autorregistro, 7 de las 30 comprobaciones se ponen en rojo. Un control que no puede fallar no prueba nada.

Lo que esto **no** decide: cuándo una organización merece la habilitación. Eso es la política de aceptación (`G-003`) y sigue siendo una decisión humana pendiente. Lo que existe ahora es que sólo una persona con rol y sustento puede tomarla, y que queda escrita.
