# Historia de STATE · ciclos hasta 2026-08-16

Extraído de `docs/ai/STATE.md` el 2026-08-17 para respetar el límite de 120
líneas del sistema operativo. Es historia, no estado: **las cifras de aquí
estaban vigentes cuando se escribieron y varias ya no lo están.** En
particular, la línea que dice que el remoto «conserva las 15 migraciones» era
cierta en su momento y dejó de serlo; el remoto tiene 28 desde el despliegue
del 2026-08-17. Para el estado vigente, `docs/ai/STATE.md`; para el remoto,
`supabase migration list --linked`.

- Provisión desde cero: `npm run bootstrap:environment` monta evento, organizaciones, cuentas por rol, centros de acopio y fondos sobre un proyecto vacío, a partir de un JSON declarativo (`supabase/bootstrap.config.example.json`). No está atado a ningún proyecto: exige `BOOTSTRAP_CONFIRM_TARGET` igual al host de destino y `BOOTSTRAP_ACKNOWLEDGE_REAL_EVENT=yes` si el evento no es simulado en remoto.
- Los centros de acopio se crean llamando a `manage_delivery_point` con sesión `event_admin`, no escribiendo tablas: nacen versionados y auditados igual que desde `/operaciones/centros`. La reejecución compara contra `delivery_points_admin` y no reescribe lo que ya coincide.
- `npm run verify:environment-flow` recorre el flujo completo sobre el entorno provisionado usando solo las funciones de la aplicación y sin la clave secreta: reporte → verificación/publicación → aporte en especie → aprobación → recepción idempotente → asignación → despacho → entrega → validación independiente → aporte económico → conciliación → solicitud/aprobación de gasto → seguimiento público. 17/17 comprobado sobre una base vaciada a cero.
- El evento dejó de estar fijado en código: `EVENT_ID`/`EVENT_SLUG` salen de `NEXT_PUBLIC_EVENT_ID`/`NEXT_PUBLIC_EVENT_SLUG` con validación de formato, y caen al evento local sintético si no se declaran. `DEMO_OPERATOR_ORG_ID` y `DEMO_PARTNER_ORG_ID` eran código muerto y se eliminaron.
- Migración `202608160004`: `service_role` recibe privilegios mínimos y explícitos sobre `organizations`, `emergency_events`, `profiles`, `memberships` y `funds` — el arranque en frío que ninguna sesión con rol puede crear. Sigue sin alcanzar aportes, inventario, movimientos financieros, centros ni auditoría. Antes esto dependía de los privilegios por defecto de la plataforma: el mismo procedimiento funcionaba en remoto y fallaba en local.
- Verificado tras el cambio: lint, `tsc --noEmit`, build, 39/39 unitarias, 163/163 pgTAP, RLS, concurrencia y 28/28 Playwright web/móvil, más el ciclo completo `db reset --no-seed` → bootstrap → flujo sobre un evento y unas organizaciones distintos a los del seed.

- Registro de aporte optimizado: el recorrido pasó de cinco pasos fijos a cuatro en especie y tres en dinero (el aporte económico ya no atraviesa el paso de punto de entrega). «Qué donarás» y «Cantidad» quedaron fusionados y el editor del artículo aparece al elegir la categoría, sin selector de categoría duplicado mientras haya un solo artículo.
- Campos por paso reducidos de ~24 visibles a 9 obligatorios: estado/cuidado/valor estimado, destinación específica con alcance y los siete datos internos del donante viven en bloques plegables con `aria-expanded`, que se abren solos si ya traen valores. El payload de `submit_donation_intake_v2` no cambió.
- Microcopy: encabezados en pregunta directa («¿Qué vas a aportar?», «¿Dónde lo entregas?», «¿Con quién coordinamos?»), «Estado declarado» pasó a «Situación actual del aporte» y los avisos de validación se muestran junto al botón que los provoca para no quedar fuera de pantalla en móvil.
- Verificado tras el cambio: lint, `tsc --noEmit`, 33/33 unitarias y 28/28 Playwright web/móvil.

- Simulación remota: reporte ciudadano → verificación/publicación → aporte/QR → aprobación → recepción/lote → asignación/despacho/entrega/validación y aporte económico → conciliación → solicitud/aprobación/pago; 38/38 comprobaciones finales.
- Controles confirmados: idempotencia en seis mutaciones, separación aliado/verificador, bodega/verificador y solicitante/aprobador, proyecciones públicas sin los marcadores de contacto, salud y Excel públicos.
- Brechas bloqueantes: `partner_reporter` alcanza datos privados de necesidades. El cruce organización-punto ya está bloqueado localmente, pero falta desplegarlo y probarlo en remoto.
- Seguimiento/territorio: el QR `APO-*` ya hereda el recorrido operacional del `DON-*` mediante `track_public_journey`; el despacho sigue sin entrar al mapa cuando no hay coordenadas aproximadas moderadas.
- Auditoría/analítica: historial crítico presente pero parte queda sin contexto completo de tenant, no comparte correlación transaccional y no genera un nuevo corte de métricas.
- Evidencia: `docs/REMOTE_FLOW_SIMULATION_2026-08-16.md`; JSON y captura QR permanecen fuera del repositorio bajo `%LOCALAPPDATA%\RutaSolidaria\simulaciones`.

- Catálogos locales: tipos de donante, sectores, categorías, estados, cobertura, departamentos, unidades y 22 aliados de referencia salen de PostgreSQL con versión fijada por intake; el aliado seleccionado no sustituye la organización derivada de membresía.
- Fotografías del intake: cero a tres JPG/PNG privadas de 5 MB, hash SHA-256, ruta generada por servidor, vínculo auditado y confirmación de existencia en Storage; continúan `pending` y no acreditan recepción o entrega.
- Claridad de solicitudes: la revisión define que es una petición de verificación (no ayuda/recibo/entrega) y la cola operativa presenta tipo, resumen, cantidad, centro, aliado, fotos, fecha y siguiente control en lenguaje natural.
- Centros: reglas con alcance opcional por `location_id`, proyección de reglas vigentes y doble validación UI/RPC de aceptación y cadena de frío.
- Puntos parametrizados: `/operaciones/centros` administra organización, zona pública, dirección privada, instrucción, coordenadas, frío, estado y categorías; RPC idempotente con reglas versionadas y auditoría append-only. Aliados solo consultan puntos activos de su organización y el intake rechaza cruces de tenant.
- Seguridad: aliado derivado de membresía activa y organización verificada; la firma antigua de intake quedó revocada para `authenticated`.
- Semántica: “Entregada” es solo estado declarado; el flujo conserva `pending_verification` y no crea donación operativa sin aprobación.
- Evidencia verde del ciclo: 152 SQL, RLS, concurrencia, 33 unitarias, 28 Playwright web/móvil, lint, TypeScript y build.
- Acceso remoto: el login ya no enumera cuentas; cinco identidades sintéticas y 12 membresías fueron provisionadas y autenticadas, con credenciales temporales fuera del repositorio y ACL exclusiva del usuario local.
- Publicación remota: migración `202608160001` aplicada; dos centros y reglas sintéticas activos; Vercel `dpl_6isVPmpj83EKqKFX6DPRpjUpLVqM` en `READY`; salud, formulario de reportes, centros, CSP y ocultamiento del bloque verificados sobre el alias público.

- Seguridad: migración `20260815224447_harden_local_operations.sql` agrega cuota atómica 5/10 min sin IP en claro; Auth bloquea altas libres, endurece contraseñas y acota sesiones.
- Observabilidad: logs JSON sin PII, hook de error, request ID, Server-Timing y salud no cacheable; cabeceras HTTP reforzadas, HSTS solo en producción.
- Recuperación: backup público sintético con manifiesto SHA-256; restore real desde migraciones + datos, 94 pgTAP y RTO 57,1 s.
- Operación: `npm run preflight:local` impide enlaces remotos accidentales; `npm run preflight:deploy` solo informa bloqueos y no muta servicios.
- Offline/UX: cola estricta sin PII, TTL/capacidad, búsqueda de recepción, etapas y compatibilidad de lote/necesidad.
- Entrega G2: CI y runbooks de incidente, datos, WAF y aprobación quedan listos para revisión humana.
- Evidencia previa: 94 SQL, RLS, concurrencia, 13 unitarias, 24 web/móvil y build antes de la integración catalogada.
- Remoto: Supabase `vcgwfyhytzgyzicfbikf` conserva las 15 migraciones y datos exclusivamente sintéticos; RLS sigue denegando tablas operacionales a `anon`; Auth tiene altas globales cerradas y contraseña mínima de 12 caracteres con complejidad y reautenticación.
- Publicación: `https://unidos-nos-cuidamos.vercel.app` apunta al despliegue sano; `/api/health` confirma `database: connected`, CSP/HSTS están presentes y el smoke test no produjo respuestas 500.
- Pendiente remoto: rotar la contraseña de base expuesta, HIBP, WAF/monitoreo y backups/PITR; no autorizar datos, dinero ni actores reales antes de G2.
- Resultado: detalle en `docs/FUNCTIONAL_AUDIT_2026-08-15.md` y `docs/OPERATIONAL_READINESS.md`.

## Ciclos del 2026-08-16 movidos el 2026-08-17

- Entorno local conmutado a **entrega**: base vaciada con `db reset --no-seed` y provisionada con `bootstrap:environment` sobre `entorno-entrega.json` (fuera del repositorio). Evento `entrega-piloto-2026`, dos organizaciones, cinco cuentas con contraseña generada, tres puntos (dos de acopio y uno solo de despacho) y un fondo.
- `NEXT_PUBLIC_APP_ENV=production` en `.env.local`: el aviso «Datos de práctica» desapareció de cabecera, pie, `/ingresar`, `/donar`, `/reportar`, `/transparencia`, `/operaciones`, `/operaciones/centros` y de los metadatos de los libros Excel. Comprobado: cero apariciones de «práctica» en las cinco superficies públicas.
- Limpieza comprobada: la contraseña publicada del seed ya no autentica (400) y no quedan proyecciones públicas de necesidades ni de donaciones heredadas de la demostración.
- Consecuencia asumida: con el entorno de entrega, pgTAP y Playwright fallan porque comprueban el seed sintético. 39/39 unitarias siguen verdes. `npm run env:suite` y `npm run env:entrega` alternan entre ambos; el runbook explica el par de variables que hay que mover.
- **No** se tocó el despliegue público: `unidos-nos-cuidamos.vercel.app` conserva `sandbox` y su aviso. Quitarlo allí es un cambio hacia afuera y sigue atado a `G-003` a `G-006`.

- Puntos con propósito declarado: cada punto dice si es centro de acopio, de despacho o ambos (`accepts_donations`, `dispatches_shipments`, con restricción que impide dejarlo sin propósito). Un punto que solo despacha deja de aparecer en el mapa público, en `public_collection_centers`, en la proyección logística y en el paso «Punto de entrega» del aliado. `/operaciones/centros` administra el propósito y oculta las categorías cuando el punto no recibe.
- Despacho con origen: `shipments.origin_location_id` fija desde dónde salió la carga. `create_shipment` valida tenant, punto activo y propósito de despacho, exige una zona de destino de 3 a 180 caracteres y la pasa por `contains_sensitive_content`. La consola de bodega dejó de enviar «Por asignar» y ahora pide origen, destino y transportador.
- Trazabilidad: `track_public_journey` devuelve la cadena real de hitos con fecha para NEC, APO y DON. Cierra el hallazgo de que el `APO-*` no heredaba el estado `DON-*`: el donante ve recepción, reserva, despacho, entrega y validación, con ambos códigos. El orden es por etapa del proceso y no por fecha, para que un registro con fecha atrasada no desordene la lectura. `/seguimiento` pasó de cuatro etapas fijas a la cronología comprobada más el siguiente control.
- Privacidad de la cadena: solo salen etiquetas fijas, cantidades conciliadas y la zona pública del despacho. Transportador, dirección exacta, contacto y notas de decisión no aparecen; hay comprobación automática de ello.
- Seed corregido: el código de la donación de demostración no cumplía el formato `DON-` + 24 hexadecimales, así que nunca resolvía en `/seguimiento`; y las necesidades se publicaban sin dejar `need_verifications`, lo que dejaba la cadena hueca. Ambos casos ya reflejan el recorrido real.
- Verificación: `verify:environment-flow` pasó de 17 a 42 comprobaciones. Suma sobreasignación, origen inválido, destino con contenido sensible, entrega que no concilia, idempotencia de despacho y conciliación, no publicación de la referencia privada del soporte y los ocho hitos de la cadena.
- Verificado tras el cambio: lint, `tsc --noEmit`, build, 39/39 unitarias, 174/174 pgTAP, RLS, concurrencia, 28/28 Playwright y el ciclo `db reset --no-seed` → bootstrap → 42/42 del recorrido.
