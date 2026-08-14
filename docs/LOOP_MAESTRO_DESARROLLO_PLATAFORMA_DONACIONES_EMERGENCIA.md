# Loop maestro para desarrollar la plataforma de trazabilidad de donaciones

> **Versión 3.0 validada · 13 de agosto de 2026**  
> **Estado:** aprobado para iniciar desarrollo controlado y sandbox. No autoriza recaudo real ni despliegue público.  
> **Criterio de aprobación:** cero brechas P0/P1 en la especificación, riesgos externos aislados y cada requisito crítico asociado a una prueba o puerta humana.

## Propósito

Este documento contiene un prompt operativo para que Codex desarrolle, de forma iterativa y verificable, el alcance completo de una plataforma colombiana de seguimiento y trazabilidad de donaciones en especie y económicas durante emergencias.

El loop está diseñado para:

- continuar trabajando después de cada entrega parcial;
- conservar el contexto entre sesiones mediante documentos de estado;
- construir por recorridos completos, desde la interfaz hasta los datos y la auditoría;
- detener el avance cuando una validación falle;
- distinguir lo terminado de lo simulado, pendiente o bloqueado;
- exigir decisiones humanas solo cuando sean legales, financieras, irreversibles o realmente bloqueantes.

## Veredicto de la validación previa

El primer loop tenía buena cobertura funcional, pero **no era todavía el mejor punto de partida**. La inspección directa del aplicativo vigente —corte aproximado del 13 de agosto de 2026 a las 09:13 a. m. de Colombia; las cifras cambian en vivo— detectó condiciones que obligan a intervenir el alcance antes del desarrollo:

| Evidencia observada | Riesgo | Corrección incorporada en esta versión |
|---|---|---|
| 617 puntos activos; 522 clasificados como urgentes | La urgencia deja de priorizar cuando cubre casi todo | Urgencia sin valor predeterminado, criterios objetivos, triage y SLA |
| 520 puntos sin confirmar durante más de seis horas | Registros viejos siguen compitiendo por atención | Caducidad, cuarentena, renovación y métricas de frescura |
| El formulario preselecciona “Rescate” y “Urgente” | Induce reportes peligrosos y sobrerrepresenta criticidad | Separación entre rescate oficial, necesidad humanitaria, oferta y acopio |
| El formulario indica que nombre o teléfono será público | Exposición de datos y riesgo para población vulnerable | Contención inmediata, contacto mediado y privacidad por diseño |
| La política afirma que no se guardan datos personales mientras admite nombres, fotos y teléfonos públicos | Contradicción de transparencia y tratamiento | Evaluación de impacto, inventario de datos y aviso coherente |
| 42 puntos no estaban ubicados y el mapa mezclaba necesidades, acopios, voluntarios y solicitudes monetarias | Emparejamiento y trazabilidad deficientes | Taxonomía, geografía DIVIPOLA, flujos independientes y estados verificables |
| Cientos de botones y marcadores se renderizan simultáneamente | Sobrecarga, accesibilidad y rendimiento deficientes | Lista virtualizada, clustering, vista alternativa y presupuesto de rendimiento |

La versión 3.0 agrega una **Puerta Cero**, contención del sistema vivo, migración verificable, operación humanitaria, controles fiscales para bienes donados, cadena logística ampliada, modelo de pantallas, métricas, pruebas adversariales y la integración expresa del flujo **Unidos Nos Cuidamos** como canal de ingreso de aliados —no como libro transaccional ni fuente pública inmediata de verdad—.

La revisión de `unidos-nos-cuidamos.netlify.app` y del libro `UNIDOS NOS CUIDAMOS · Registro de donaciones.xlsx` incorporó además estas correcciones:

| Evidencia del flujo de aliados | Riesgo | Corrección incorporada |
|---|---|---|
| El formulario anuncia que cada aporte aparece inmediatamente en el tablero público | Suplantación, publicación de datos no verificados y cifras no conciliadas | Todo envío entra como `Reportado / Pendiente de verificación`; solo una proyección aprobada se publica |
| El reportante elige por sí mismo “Comprometida”, “En gestión”, “En tránsito” o “Entregada” | Una declaración se confunde con recepción, custodia o entrega comprobada | Se conserva como `estado_declarado`; el estado operacional solo cambia con actor autorizado y evidencia |
| Especie y dinero comparten un único esquema y el valor estimado es obligatorio | Se mezclan valoración indicativa, recaudo, conciliación, inventario y certificación | Bifurcación temprana por tipo; flujos, datos, permisos y métricas independientes |
| Aliado, cantidad, unidad, destino y beneficiarios admiten selección o texto sin identidad/evidencia suficiente | Suplantación, datos no normalizados y doble conteo | Autenticación de aliados, catálogos versionados, unidades normalizadas, DIVIPOLA, vínculo a necesidad/fondo y método de estimación |
| El Excel contiene 22 columnas, listas que deben sincronizarse manualmente con Apps Script/micrositio y un tablero con funciones específicas de Google Sheets | Deriva de catálogos, fórmulas `#NAME?` fuera de Sheets y falta de IDs de trazabilidad | El libro pasa a ser staging/importación; API y base transaccional son fuente canónica; conciliación independiente |
| Responsable y contacto se marcan como privados, pero el nombre de una persona donante puede atribuirse públicamente | Exposición de personas naturales | Preferencia de atribución: nombre autorizado, organización, alias o anónimo; contactos siempre privados |

## Loop de perfeccionamiento aplicado

Esta versión se revisó con el siguiente meta-loop y el mismo patrón queda incorporado para futuras revalidaciones:

```text
REPETIR
  1. Contrastar objetivo, actores, recorridos, datos, riesgos y restricciones.
  2. Buscar contradicciones, supuestos peligrosos y requisitos sin prueba.
  3. Simular fraude, error humano, caída de red, duplicidad, reversión y recuperación.
  4. Clasificar brechas P0, P1, P2 o P3.
  5. Corregir la especificación y volver a ejecutar la matriz completa.
HASTA QUE
  P0 = 0, P1 = 0,
  cada P2 tenga responsable y decisión,
  todos los recorridos críticos tengan aceptación y evidencia,
  y las decisiones externas no bloqueen el desarrollo en sandbox.
DEVOLVER una sola versión canónica, su evidencia y los límites pendientes.
```

“Perfecto” significa aquí **sin brechas críticas conocidas frente al alcance y criterios definidos**, no una promesa de ausencia absoluta de riesgo. La preparación para producción requiere decisiones y validaciones humanas indicadas más adelante.

## Cómo usarlo

1. Agrega al repositorio la auditoría funcional del sitio actual, si todavía no está allí.
2. Guarda este archivo en la raíz del repositorio o en `docs/`.
3. Inicia Codex en el repositorio y pega el bloque **Prompt ejecutable**.
4. Exige que Codex complete primero la **Puerta Cero**; no debe saltar directamente a construir pantallas.
5. Si la sesión se interrumpe, vuelve a ejecutar el mismo prompt. Codex deberá leer los archivos de estado y continuar desde el último punto comprobado.

## Prompt ejecutable

```text
Actúa como líder integral de producto, arquitectura, ingeniería, UX, seguridad, datos, calidad y operación para este repositorio. Tu misión es llevar hasta un estado desplegable y verificable una plataforma para registrar, verificar, asignar, transportar, entregar y auditar donaciones en especie y económicas durante emergencias en Colombia.

No te limites a analizar, proponer una arquitectura o generar un prototipo visual. Ejecuta un loop de implementación hasta satisfacer la definición global de terminado o encontrar un bloqueo externo que requiera una decisión humana. Trabaja con autonomía dentro de los permisos disponibles, conserva los cambios ajenos y evita acciones destructivas o externas no autorizadas.

ALCANCE DE LA AUTORIZACIÓN ACTUAL

- Puedes investigar, diseñar, implementar y probar localmente o en sandbox dentro del repositorio.
- Puedes crear migraciones reversibles, fixtures ficticios y adaptadores de servicios externos.
- No asumas autorización para modificar el sitio vivo, migrar sus datos, recaudar dinero, enviar comunicaciones, registrar entidades, emitir certificados tributarios ni desplegar en producción.
- Si tienes acceso al código vivo, primero prepara el cambio, sus pruebas, rollback y evidencia; la activación sigue siendo una puerta humana.

JERARQUÍA DE FUENTES DE VERDAD

Resuelve conflictos en este orden y registra la decisión:

1. Instrucciones explícitas del usuario, permisos y reglas del repositorio.
2. Normativa vigente y fuentes oficiales del evento, territorio y autoridades.
3. Especificación canónica, decisiones aprobadas y contratos del sistema.
4. Registros verificados por una organización autorizada.
5. Reportes comunitarios no verificados.
6. Supuestos reversibles del equipo.

Nunca promociones automáticamente una fuente de menor nivel a una de mayor confianza. Si dos fuentes autorizadas se contradicen, conserva ambas, marca el conflicto y envíalo a resolución.

════════════════════════════════════════════════════════════════════
1. RESULTADO DE PRODUCTO
════════════════════════════════════════════════════════════════════

Construye una solución multi-evento cuya primera configuración atienda la emergencia sísmica de agosto de 2026 en Colombia. La fecha, epicentro, municipios afectados, cifras y fuentes del evento deben provenir de fuentes oficiales registradas; no conviertas afirmaciones no verificadas en hechos.

La plataforma debe permitir:

1. Reportar, verificar, priorizar, publicar y cerrar necesidades humanitarias.
2. Ofrecer y recibir donaciones en especie con comprobante y cadena de custodia.
3. Administrar inventario por lote, ubicación, condición, vencimiento y movimiento.
4. Asignar una o varias donaciones a una o varias necesidades sin perder trazabilidad.
5. Crear despachos, registrar transporte, confirmar entrega y adjuntar evidencia.
6. Recibir y conciliar donaciones económicas únicamente mediante fondos y organizaciones verificadas.
7. Solicitar, aprobar, pagar y justificar gastos con separación de funciones.
8. Publicar información agregada de transparencia sin exponer datos personales o sensibles.
9. Permitir a cada donante consultar el estado de su aporte mediante autenticación o un código seguro.
10. Operar en móviles, conexiones lentas y puntos de acopio con conectividad intermitente.
11. Mantener un historial de auditoría inmutable para toda acción crítica.
12. Integrar el mapa existente como capa pública de orientación, no como única fuente transaccional.

Superficies mínimas del producto:

- **Mapa y portal público:** necesidades agregadas, confianza, frescura y orientación segura.
- **Portal del donante:** promesa, comprobante, seguimiento, preferencias de privacidad y soporte.
- **PWA de campo:** verificación, recepción, inventario, despacho y entrega con conectividad intermitente.
- **Centro de acopio:** citas, recepción, lotes, existencias, asignaciones, conteos y novedades.
- **Centro de mando:** triage, deduplicación, cobertura, capacidad, coordinación territorial y alertas.
- **Tesorería:** fondos, conciliación, gastos, aprobaciones, soportes y cierre.
- **Auditoría y transparencia:** evidencia, historial, conciliaciones, exportaciones y rendición de cuentas.

La intención de experiencia es: **para ciudadanía, donantes y operadores bajo presión, facilitar una decisión segura y trazable con el mínimo de pasos, mostrando siempre qué está verificado, qué falta y quién debe actuar a continuación.**

La tesis visual debe transmitir calma operativa, confianza y dignidad, no alarma permanente. La urgencia se comunica con texto, jerarquía y símbolos además del color; rojo se reserva para riesgo/acción verdaderamente crítica. Define tokens semánticos, tipografía legible, espaciado, componentes, estados y movimiento reducido. La interfaz no debe parecer una colección genérica de tarjetas ni depender de efectos decorativos.

════════════════════════════════════════════════════════════════════
2. REGLAS INNEGOCIABLES
════════════════════════════════════════════════════════════════════

- No publiques teléfonos personales, documentos, direcciones privadas, ubicaciones precisas de población vulnerable, datos bancarios ni evidencias sensibles.
- No permitas que un ciudadano publique cuentas bancarias, enlaces de pago o instrucciones para recibir dinero.
- Solo organizaciones y fondos verificados pueden figurar como receptores de donaciones económicas.
- No marques una organización, necesidad, entrega o evidencia como verificada sin una acción y un responsable autorizados.
- Usa pagos simulados o sandbox hasta contar con entidad operadora, acuerdos, credenciales y autorización explícita para producción.
- Separa las funciones de quien solicita, aprueba, paga y audita un gasto. Una persona no puede aprobar su propia solicitud.
- Registra los eventos críticos de forma append-only. Una corrección crea un nuevo evento compensatorio; no borra la historia.
- Toda cifra pública debe poder reconciliarse con los registros operativos y financieros subyacentes.
- No declares terminado un flujo basado en datos falsos, mocks, TODO, botones sin acción o persistencia temporal.
- No hagas despliegues públicos, envíos de mensajes, compras, activaciones financieras, migraciones irreversibles ni cambios de DNS sin autorización explícita.
- No reescribas ni descartes cambios del usuario que no pertenezcan a esta tarea.
- Mantén una fuente de verdad por concepto y evita duplicar reglas de negocio entre cliente y servidor.
- Ningún reporte ciudadano debe iniciar marcado como “Urgente”, “Rescate” o “Verificado”. La persona reporta hechos; el sistema y un rol autorizado determinan la clasificación.
- No envíes voluntariado general a rescate, evacuación clínica, evaluación estructural, materiales peligrosos ni otras tareas reservadas a personal competente. Esos casos se escalan a autoridades o equipos acreditados.
- Un dato vencido, no ubicado o en conflicto no permanece como activo y confiable por defecto. Debe renovarse, degradarse, ponerse en cuarentena o cerrarse mediante una regla auditable.
- Separa ubicación operacional precisa de ubicación pública aproximada. La precisión pública se decide por riesgo, consentimiento y tipo de caso.
- No publiques cifras de “personas en línea”, cobertura o impacto sin definición, fuente, periodo, método y margen de actualización.
- No aceptes bienes prohibidos, abiertos, vencidos, sin trazabilidad, que requieran cadena de frío no disponible o que representen riesgo sanitario/logístico. Las reglas de aceptación son versionadas por organización y centro.
- No expidas un certificado tributario por el simple hecho de emitir un comprobante de recepción. Elegibilidad, valoración, firma, factura y destinación siguen un flujo contable autorizado.
- Aplica idempotencia y control de concurrencia a recepción, inventario, asignación, conciliación, aprobaciones, webhooks, sincronización offline y cierre.
- Mantén mecanismos de denuncia, rectificación, retiro de contenido y atención de titulares con SLA, responsable y trazabilidad.
- La automatización o IA puede sugerir prioridad, duplicados o fraude, pero no toma sola decisiones que afecten acceso a ayuda, verificación institucional, desembolso o exposición de datos.
- Aísla organizaciones y eventos en toda consulta y escritura; prueba IDOR, escalamiento horizontal/vertical y exportaciones entre tenants.
- No captures ni almacenes datos completos de tarjeta. Usa componentes/redirecciones del proveedor autorizado, verifica firma y antigüedad de webhooks y bloquea replays.

════════════════════════════════════════════════════════════════════
3. ARRANQUE Y MEMORIA PERSISTENTE
════════════════════════════════════════════════════════════════════

Al comenzar o reanudar una sesión:

1. Lee `AGENTS.md`, instrucciones del repositorio, README, manifiestos, configuración, migraciones, pruebas y cambios pendientes.
2. Busca y lee la auditoría del producto y este loop. Si existen especificaciones previas, intégralas en lugar de reemplazarlas sin análisis.
3. Identifica stack, arquitectura, servicios, variables de entorno, comandos, cobertura, deuda y estado real de ejecución.
4. Ejecuta la línea base aplicable: instalación, lint, typecheck, pruebas, build y arranque local. Registra fallos preexistentes por separado.
5. Crea o actualiza estos archivos durables:

   - `docs/PROJECT_SPEC.md`: alcance, actores, casos de uso, reglas y no objetivos.
   - `docs/PLAN.md`: hitos, dependencias, criterios de aceptación y estado.
   - `docs/STATUS.md`: último resultado comprobado, comandos ejecutados, bloqueos y siguiente acción.
   - `docs/DECISIONS.md`: decisiones arquitectónicas y de producto con fecha, motivo y consecuencias.
   - `docs/TRACEABILITY_MATRIX.md`: requisito → diseño → implementación → pruebas → evidencia.
   - `docs/RISK_REGISTER.md`: riesgos de fraude, privacidad, seguridad, continuidad, operación y cumplimiento.
   - `docs/DATA_DICTIONARY.md`: entidades, campos sensibles, reglas, retención y visibilidad.
   - `docs/READINESS_AUDIT.md`: resultado de la Puerta Cero, evidencia y brechas por severidad.
   - `docs/GAP_LEDGER.md`: brechas abiertas, responsable, decisión, fecha objetivo y prueba de cierre.
   - `docs/OPERATING_MODEL.md`: RACI, turnos, SLA, escalamiento y procedimientos de campo/tesorería.
   - `docs/DATA_MIGRATION_PLAN.md`: inventario del legado, mapeo, depuración, ensayo, corte y rollback.
   - `docs/PRIVACY_IMPACT_ASSESSMENT.md`: finalidades, base/autorización, minimización, acceso, retención y derechos.
   - `docs/THREAT_MODEL.md`: activos, actores, fronteras de confianza, abuso, mitigaciones y pruebas.
   - `docs/TEST_STRATEGY.md`: pirámide, fixtures, E2E, datos adversariales, rendimiento y recuperación.
   - `docs/COMPLIANCE_REGISTER.md`: requisito normativo/estándar, fuente oficial, interpretación validada y evidencia.
   - `docs/RELEASE_CHECKLIST.md`: condiciones técnicas, legales y operativas para salida.
   - `docs/PROJECT_SCORECARD.md`: nivel 0–4 por frente de trabajo.

6. Si el repositorio está vacío, documenta una decisión de arquitectura antes de generar la base. Prioriza una PWA accesible, API transaccional, base de datos relacional con capacidades geoespaciales, almacenamiento privado de evidencias, cola de trabajos, autenticación robusta y observabilidad. Elige tecnologías compatibles con el entorno y justificadas por mantenibilidad, no por novedad.
7. No esperes a completar un plan perfecto: cuando la línea base y el primer recorrido estén definidos, comienza la primera implementación segura.

Los documentos anteriores son memoria operativa, no documentación decorativa. Deben reflejar el estado comprobado después de cada ciclo.

════════════════════════════════════════════════════════════════════
3A. PUERTA CERO — LOOP DE VALIDACIÓN ANTES DE DESARROLLAR
════════════════════════════════════════════════════════════════════

Antes del primer cambio funcional, ejecuta este loop. Puedes corregir documentación, pruebas de línea base o una vulnerabilidad P0 evidente; no construyas módulos nuevos hasta aprobarlo.

RONDA 1 — EVIDENCIA Y LEGADO

- Inspecciona el producto renderizado, sus flujos, formularios, estados, avisos, accesibilidad, consola, rendimiento y métricas.
- Si hay datos vivos, toma solo una copia autorizada y protegida; registra corte, fuente, esquema, conteos y checksum.
- Identifica datos personales, ubicaciones precisas, reportes monetarios, duplicados, no ubicados, desmentidos, vencidos y contradicciones.
- No uses el contenido vivo como fixture público ni lo copies a entornos de desarrollo sin anonimización.

RONDA 2 — COBERTURA DE PRODUCTO Y OPERACIÓN

- Mapea actor → objetivo → recorrido → estado → regla → dato → pantalla → prueba → evidencia.
- Verifica rescate/autoridad, necesidades, ofertas, especie, dinero, inventario, logística, transparencia, reclamos, cierre y multi-evento.
- Define RACI, SLA de triage/verificación, escalamiento 24/7 durante activación y propietario de cada cola.
- Todo requisito sin dueño, estado o prueba es una brecha.

RONDA 3 — SEGURIDAD, PRIVACIDAD, FRAUDE Y CUMPLIMIENTO

- Ejecuta modelado de amenazas y abuso: doxxing, suplantación, cuentas falsas, enlaces de pago, fotos sensibles, malware, spam, bots, escalamiento de privilegios, manipulación de inventario, colusión, doble gasto y borrado de evidencia.
- Contrasta el diseño con protección de datos en Colombia, responsabilidad de datos humanitarios, obligaciones contables/tributarias y políticas de la entidad operadora.
- No interpretes fuentes como asesoría legal definitiva. Marca lo que requiere validación jurídica, contable o humanitaria.

RONDA 4 — ARQUITECTURA, MIGRACIÓN Y OPERABILIDAD

- Evalúa límites de dominio, consistencia, auditoría, idempotencia, concurrencia, offline, geoespacial, almacenamiento, cifrado, observabilidad, backup, restauración, costo y escalabilidad.
- Diseña migración por ensayo: snapshot → perfilado → clasificación PII → mapeo → deduplicación → importación en cuarentena → conciliación → aprobación → ejecución → rollback.
- Define coexistencia, feature flags y corte gradual para no interrumpir el mapa vivo. Ningún registro legado se vuelve “verificado” por migrarse.

RONDA 5 — TESTABILIDAD Y RED TEAM DEL PLAN

- Simula happy path, cancelación, rechazo, parcial, vencimiento, duplicado, conflicto, reversión, pérdida, fraude, caída de proveedor, caída de red y recuperación.
- Comprueba que cada P0/P1 tenga prevención y prueba automatizada o procedimiento verificable.
- Busca contradicciones entre estados, métricas, permisos, privacidad, documentos y definición de terminado.
- Verifica que el primer recorrido vertical pueda implementarse sin una decisión externa; si no, recórtalo o usa sandbox.

CLASIFICACIÓN

- **P0:** puede causar daño físico, pérdida/desvío de dinero, exposición sensible masiva, corrupción de registros o indisponibilidad crítica.
- **P1:** rompe un recorrido esencial, una obligación, conciliación, autorización o recuperación.
- **P2:** afecta eficiencia, comprensión, accesibilidad, calidad o escalabilidad sin daño crítico inmediato.
- **P3:** mejora deseable o pulido.

REPETICIÓN Y SALIDA

1. Registra brechas en `GAP_LEDGER` con evidencia, severidad y prueba de cierre.
2. Corrige especificación, plan, arquitectura o prototipo de prueba.
3. Repite las cinco rondas completas; no revises solo el área modificada.
4. Aprueba Puerta Cero únicamente cuando P0 = 0, P1 = 0, cada P2 tenga responsable/decisión y la matriz cubra todos los recorridos críticos.
5. Guarda un acta breve en `READINESS_AUDIT` con fecha, versión, verificaciones y límites.

Si no puede aprobarse, entrega el bloqueo exacto y continúa únicamente con trabajo independiente y reversible. No uses la búsqueda de perfección para repetir cambios cosméticos sin impacto.

════════════════════════════════════════════════════════════════════
4. LOOP DE EJECUCIÓN
════════════════════════════════════════════════════════════════════

Repite este ciclo sin esperar una nueva instrucción:

PASO A — ORIENTAR

- Lee `STATUS`, `PLAN`, matriz de trazabilidad, riesgos, decisiones y diff actual.
- Comprueba qué funciona realmente y qué sigue pendiente.
- Revisa si apareció un fallo, una regresión, un cambio externo o una decisión bloqueante.

PASO B — ELEGIR UN RECORRIDO VERTICAL

- Selecciona el incremento incompleto de mayor prioridad y menor tamaño que produzca valor comprobable de extremo a extremo.
- Incluye, según corresponda: migración, dominio, permisos, API, interfaz, accesibilidad, auditoría, telemetría, pruebas y documentación.
- No construyas capas enormes desconectadas. Prefiere una operación completa y demostrable.
- Prioriza en este orden: daño/seguridad P0, privacidad y dinero, integridad de datos, continuidad operacional, recorrido crítico, accesibilidad/rendimiento y luego pulido.

PASO C — DEFINIR EL CONTRATO DEL CICLO

- Escribe criterios de aceptación observables.
- Enumera actores, precondiciones, estados, transiciones válidas, errores, permisos, datos sensibles y eventos de auditoría.
- Actualiza la matriz de trazabilidad y los riesgos antes de codificar cuando el cambio sea sensible.
- Define también la prueba negativa: qué actor, estado o dato debe ser rechazado y cómo se evidencia.

PASO D — IMPLEMENTAR

- Implementa el recorrido con cambios pequeños, coherentes y reversibles.
- Usa transacciones e idempotencia donde haya inventario, dinero, webhooks, sincronización o reintentos.
- Incluye estados vacío, carga, éxito, error, permiso insuficiente, conflicto y conectividad perdida.
- Agrega migraciones seguras, datos de prueba claramente identificados y contratos tipados.
- No inventes secretos. Documenta variables requeridas y proporciona ejemplos sin credenciales reales.
- Protege cada escritura crítica con autorización, validación de transición, clave idempotente, transacción y evento de auditoría correlacionado.
- Mantén compatibilidad temporal o estrategia de migración explícita cuando cambies contratos o esquemas usados por el sistema vivo.

PASO E — VERIFICAR

Ejecuta las validaciones aplicables y registra evidencia:

- formato y lint;
- typecheck o compilación;
- pruebas unitarias de reglas e invariantes;
- pruebas de integración de persistencia, permisos y transacciones;
- pruebas de contrato/API;
- pruebas E2E del recorrido principal y fallos relevantes;
- build de producción;
- análisis de dependencias y secretos;
- pruebas de autorización horizontal y vertical;
- accesibilidad automatizada y navegación por teclado;
- revisión responsive en 320, 375, 768, 1024 y 1440 px;
- inspección visual del flujo renderizado;
- rendimiento de mapa, listados y consultas;
- migración hacia adelante, recuperación y respaldo cuando corresponda.
- pruebas de concurrencia, duplicación y reintentos en operaciones críticas;
- escaneo de archivos, límites de tipo/tamaño y privacidad de metadatos;
- conciliación de conteos y montos mediante consultas independientes;
- comprobación de que logs, analytics, exportaciones y errores no filtran PII.

PASO F — DETENER Y REPARAR

- Si una validación falla por tu cambio, corrígela antes de avanzar.
- Si el fallo es preexistente, compruébalo, documéntalo y decide si bloquea el recorrido.
- No ocultes fallos reduciendo pruebas, desactivando reglas o sustituyendo comportamiento real por mocks.
- No abras un nuevo frente mientras exista una regresión P0 o P1.
- Si dos intentos razonables sobre el mismo fallo no lo resuelven, reduce el caso, conserva logs/evidencia, registra una hipótesis y cambia de táctica. No repitas ciegamente.
- Si el bloqueo es externo, aísla el adaptador, mantén la prueba contractual y continúa los recorridos no dependientes.

PASO G — CERRAR EL CICLO

- Actualiza especificación, plan, estado, decisiones, matriz, riesgos, diccionario, checklist y scorecard.
- Registra qué cambió, qué se ejecutó y la evidencia de que funciona.
- Marca una tarea como completa solo si satisface sus criterios de aceptación.
- Identifica el siguiente recorrido concreto y vuelve al PASO A.
- El informe debe distinguir: implementado y probado; implementado sin prueba suficiente; simulado; bloqueado; no iniciado.

Si la sesión se compacta, reinicia o debe finalizar por límites de ejecución, guarda primero un checkpoint atómico en `STATUS`, deja el repositorio en estado verificable y registra el comando exacto para continuar. En una nueva ejecución, recupera ese estado y no repitas trabajo ya comprobado.

════════════════════════════════════════════════════════════════════
5. ORDEN DE HITOS
════════════════════════════════════════════════════════════════════

Trabaja en este orden salvo que una dependencia comprobada lo justifique. Cada hito debe dejar al sistema ejecutable.

HITO -1 — CONTENCIÓN Y CONTINUIDAD DEL SISTEMA VIVO

- Documentar corte del sistema actual: datos, métricas, flujos, infraestructura, responsables, dependencias y riesgos.
- Incluir en el corte el micrositio “Unidos Nos Cuidamos”, su formulario, tablero, Apps Script/endpoint, libro de registro, catálogos y permisos; calcular snapshot y checksum sin copiar PII a entornos inseguros.
- Sustituir la publicación inmediata de aportes por ingreso no verificado, moderación y proyección pública aprobada; si no hay autorización de producción, dejar cambio, prueba, flag y rollback preparados.
- Preparar correcciones P0: eliminar publicación de teléfonos/datos bancarios, quitar valores predeterminados “Rescate/Urgente”, separar precisión pública y bloquear contenido monetario ciudadano.
- Definir reglas para puntos sin ubicación, vencidos, desmentidos, duplicados o no confirmados; preservar la evidencia original sin mantenerlos como confiables.
- Crear exportación/snapshot verificable, inventario de PII, plan de anonimización y rollback.
- Diseñar coexistencia mediante flags o rutas separadas; el mapa público no debe interrumpirse durante la construcción.
- Si no existe autorización para tocar producción, producir un playbook y cambios listos para revisión; no afirmar que el riesgo está contenido.

Criterio de salida: los P0 del legado tienen cambio preparado, prueba, responsable, procedimiento de activación y rollback; existe un snapshot reproducible y ningún dato legado obtiene verificación automática.

HITO 0 — FUNDAMENTOS, GOBERNANZA Y SEGURIDAD

- Configuración reproducible, entornos, CI y datos de desarrollo.
- Usuarios, autenticación, recuperación, sesiones y MFA para roles privilegiados.
- Organizaciones, membresías, roles y permisos de mínimo privilegio.
- Eventos de emergencia, fuentes oficiales, geografía y clasificación de visibilidad.
- Códigos territoriales oficiales —incluida DIVIPOLA— y control de versiones de límites/nombres.
- Auditoría append-only, almacenamiento privado de evidencias y política de datos sensibles.
- Diseño de amenaza inicial, rate limiting, validación, protección de carga de archivos y gestión de secretos.
- RACI, turnos, SLA, escalamiento, segregación de funciones y procedimiento de revocación urgente.
- Registro de finalidades, consentimiento/autorización cuando corresponda, solicitudes de titulares, retención y cierre del evento.
- Tesis UX, arquitectura de navegación y sistema de diseño accesible con tokens semánticos y componentes/estados reutilizables.

Criterio de salida: un administrador autorizado puede crear un evento y una organización; los accesos indebidos son rechazados y auditados; ningún dato sensible aparece en superficies públicas; existe dueño y SLA para cada cola crítica.

HITO 1 — NECESIDADES Y VERIFICACIÓN

- Reporte ciudadano con categoría, cantidades, unidad, ubicación aproximada, urgencia y evidencia opcional.
- Reporte basado en hechos, sin urgencia/rescate preseleccionados, con instrucciones que eviten poner a la ciudadanía en peligro.
- Bandeja de triage, moderación, deduplicación, verificación, vencimiento, confianza, fuente, SLA y escalamiento.
- Estados: Reportada → En verificación → Verificada → Publicada → Parcialmente cubierta → Cubierta → Cerrada.
- Alternos: Duplicada, Desmentida, Rechazada, Vencida y Suspendida.
- Vista pública agregada; vista operativa con permisos y datos protegidos.
- Derivación a autoridad de rescate, salud, evaluación estructural o materiales peligrosos sin convocar voluntariado no calificado.
- Taxonomía versionada de necesidades, unidad normalizada y ventanas de atención; el texto libre complementa, no reemplaza, los datos estructurados.

Criterio de salida: una necesidad puede atravesar todo el flujo con historial, responsable, fuente y métricas de cobertura correctas; casos críticos se escalan de forma segura y registros vencidos dejan de competir como activos.

HITO 2 — DONACIONES EN ESPECIE Y RECEPCIÓN

- Canal breve para aliados autenticados: borrador, reporte, observación, verificación, constancia y seguimiento; una respuesta puede contener varias líneas de artículo.
- Promesa de donación vinculada o no a una necesidad.
- Artículos, unidad, cantidad, condición, vencimiento, restricciones y disponibilidad.
- Política versionada de artículos aceptados, restringidos y prohibidos por centro y capacidad real.
- Cita o instrucción de entrega, código seguro/QR y comprobante.
- Recepción con cantidades aceptadas, rechazadas, en cuarentena y motivo; clasificación por lote, inspección y responsable.
- Estados: Prometida → Programada → Recibida → Clasificada → Almacenada, con Cancelada y Rechazada.
- Separación entre comprobante operativo y certificado tributario; captura de soportes de valoración/factura solo cuando corresponda y con acceso restringido.

Criterio de salida: el donante y el punto de acopio ven el mismo estado, cada unidad aceptada entra exactamente una vez al inventario y nada rechazado/cuarentenado puede asignarse.

HITO 3 — INVENTARIO, ASIGNACIÓN Y LOGÍSTICA

- Lotes por centro, ubicación, estado, vencimiento, custodio, condición y requisitos de almacenamiento.
- Movimientos append-only: ingreso, traslado, reserva, salida, ajuste y baja con motivo.
- FEFO/FIFO según categoría; temperatura/cadena de frío, cuarentena, retiro/recall, daño, pérdida, robo, devolución y disposición final cuando apliquen.
- Conteos cíclicos y conciliación entre existencia física y libro de inventario; ajustes requieren motivo, evidencia y permiso.
- Asignaciones muchos-a-muchos entre existencias y necesidades.
- Picking, despacho, transportista, ruta, novedad, entrega y evidencia.
- Estados logísticos: Despachada → En tránsito → Entregada → Validada, con Novedad.

Criterio de salida: existencias, reservas, despachos, entregas y cobertura se reconcilian sin cantidades negativas ni movimientos duplicados; un lote bloqueado o retirado no puede salir.

HITO 4 — DONACIONES ECONÓMICAS Y FONDOS

- Separar aporte económico declarado por un aliado de ingreso financiero conciliado. Los aportes gestionados fuera de la plataforma requieren fondo/organización/operador y soporte antes de afectar métricas.
- Alta y verificación de organización receptora y fondo asociado al evento.
- Verificación KYB/KYC y controles AML/sanciones según proveedor, política de la entidad y validación jurídica; la plataforma registra resultado/fecha, no sustituye al responsable regulado.
- Integración sandbox por enlace o proveedor de pago; nunca captura informal de cuentas.
- Libro mayor de doble entrada o modelo contable equivalente e inmutable.
- Conciliación idempotente de pago, webhook, extracto, reversión, contracargo y reembolso.
- Recibo, anonimato público opcional, restricciones de destinación y política de reasignación/devolución.
- Solicitud de gasto, doble aprobación, pago, soporte, resultado y publicación agregada.
- Flujo separado de certificación tributaria con elegibilidad, forma, monto/valor, fecha, clase de bien, destinación, firma autorizada y conservación de soportes.
- Métricas: recibido, conciliado, comprometido, gastado, revertido y saldo disponible.

Criterio de salida: ninguna cifra pública se deriva de campos editables; cada valor concilia con transacciones y ningún solicitante aprueba su propio gasto.

HITO 5 — TRANSPARENCIA Y AUTOSERVICIO

- Consulta segura del aporte por donante.
- Tablero “Unidos Nos Cuidamos” alimentado por una proyección pública aprobada, no por respuestas crudas del formulario ni por fórmulas del Excel.
- Panel público por evento, organización, territorio, categoría y periodo.
- Metodología de cálculo, fecha de actualización y nivel de verificación visibles.
- Exportaciones CSV/JSON sin datos personales y comprobantes privados.
- Línea de tiempo de una donación sin revelar destinatarios vulnerables.
- Reporte de inconsistencias, fraude, quejas y canal seguro de moderación con estado y SLA.
- Mecanismo de retroalimentación de personas afectadas, protección contra represalias y registro de resolución.

Criterio de salida: una persona externa puede comprender de dónde provino, dónde está y qué resultado tuvo el aporte dentro de los límites de privacidad.

HITO 6 — OPERACIÓN TERRITORIAL Y RESILIENCIA

- PWA instalable y experiencia de bajo consumo de datos.
- Captura offline de operaciones permitidas con cola local cifrada cuando sea viable.
- Sincronización idempotente, resolución explícita de conflictos y prevención de duplicados.
- Notificaciones configurables y plantillas aprobables.
- Mapa con clustering, filtros, lista accesible alternativa y degradación sin geolocalización.
- Importación/exportación controlada e integración con fuentes oficiales cuando exista un contrato estable.
- Modos degradados, cola operacional priorizada y procedimiento manual controlado cuando fallen identidad, mapas, pagos o almacenamiento.
- Datos offline mínimos, cifrados, con expiración, cierre de sesión, revocación y limpieza segura ante pérdida del dispositivo o cambio de operador.

Criterio de salida: un punto de acopio puede registrar recepción sin conexión y sincronizar después sin duplicar inventario, auditoría ni comprobantes.

HITO 7 — ENDURECIMIENTO Y SALIDA

- Pruebas de carga y rendimiento con volumen realista.
- Índices, paginación, virtualización y optimización geoespacial.
- WCAG 2.2 AA en recorridos críticos.
- QA visual de estados vacío/carga/error/éxito/conflicto, texto largo, zoom, alturas cortas, teclado y `prefers-reduced-motion` en cada viewport objetivo.
- Observabilidad, alertas, métricas de negocio, logs sin datos sensibles y correlación de eventos.
- Backups, restauración comprobada, continuidad, runbooks e incidentes.
- Revisión de amenazas, dependencias, permisos, retención y borrado/anonimización donde legalmente aplique.
- Checklist de despliegue, rollback, operación, soporte y capacitación.
- Piloto territorial, feature flags, ensayo de migración, comparación paralela y criterios de abortar el corte.
- Pruebas de caos controladas para dependencias, colas, almacenamiento, mapas y proveedor financiero sandbox.
- Matriz de navegadores/dispositivos que incluya Android Chrome e iOS Safari, además de navegadores de escritorio soportados.
- Presupuestos de costo y capacidad por volumen, almacenamiento de evidencia, mapas, notificaciones y transacciones, con alertas de consumo anómalo.

Criterio de salida: el sistema puede ser operado y recuperado por un equipo distinto al desarrollador, con riesgos críticos cerrados o aceptados explícitamente.

════════════════════════════════════════════════════════════════════
6. MODELO MÍNIMO DE DOMINIO
════════════════════════════════════════════════════════════════════

El modelo puede adaptarse al stack, pero debe cubrir al menos:

- `emergency_event`
- `official_source`
- `source_assertion` y `source_conflict`
- `organization`
- `organization_verification`
- `user`
- `membership`
- `role` y `permission`
- `location`
- `territorial_unit` y `public_location_projection`
- `need_case`
- `need_item`
- `verification`
- `donation_intake` y `donation_intake_item`
- `intake_verification_decision`
- `donation`
- `donation_item`
- `receipt`
- `tax_certificate_request` y `tax_certificate`
- `item_acceptance_rule`
- `inventory_location`
- `inventory_lot`
- `stock_movement`
- `inventory_count`
- `storage_condition_event`
- `lot_hold_or_recall`
- `allocation`
- `shipment`
- `shipment_item`
- `delivery`
- `fund`
- `financial_account`
- `financial_transaction`
- `expense_request`
- `expense_approval`
- `expense_payment`
- `evidence`
- `moderation_report`
- `complaint_or_feedback_case`
- `data_subject_request`
- `notification`
- `integration_event` y `idempotency_key`
- `catalog` y `catalog_version`
- `migration_batch` y `migration_record_result`
- `public_donation_projection`
- `public_metric_snapshot`
- `security_or_operational_incident`
- `audit_event`

Para cada entidad define identificador, evento de emergencia, organización responsable cuando aplique, estado, marcas de tiempo, autor/origen, nivel de visibilidad, clasificación de sensibilidad, retención, base/finalidad de tratamiento y restricciones. Las transiciones de estado deben validarse en el servidor y generar eventos de auditoría correlacionados. El modelo público se deriva mediante vistas/proyecciones seguras; no se expone directamente el modelo operacional.

════════════════════════════════════════════════════════════════════
6A. ARQUITECTURA DE INFORMACIÓN Y RECORRIDOS
════════════════════════════════════════════════════════════════════

Antes de diseñar componentes, crea un inventario de pantallas y valida estos recorridos:

1. **Ciudadanía:** entender el evento → consultar fuente/frescura → reportar hechos → recibir código → corregir o retirar.
2. **Persona afectada:** pedir apoyo con privacidad → conocer estado → aportar retroalimentación o queja.
3. **Donante en especie:** descubrir demanda válida → revisar qué se acepta → prometer → agendar → entregar → seguir resultado.
4. **Donante económico:** elegir fondo verificado → pagar en sandbox/producción autorizada → obtener recibo → consultar uso y reversos.
5. **Aliado reportante:** autenticarse → registrar un aporte gestionado → adjuntar soporte → corregir observaciones → consultar validación y publicación.
6. **Verificador:** recibir cola priorizada → contactar/visitar → comparar fuentes → decidir → fijar vencimiento.
7. **Centro de acopio:** cita → recepción → inspección → lote → almacenamiento → conteo → asignación → salida.
8. **Logística:** plan → picking → custodia → transporte → novedad → entrega → validación.
9. **Tesorería:** conciliación → restricción → solicitud → aprobación segregada → pago → soporte → cierre.
10. **Auditor:** seleccionar muestra → seguir evento/soporte → reproducir conciliación → registrar hallazgo.
11. **Administrador del evento:** activar → configurar territorios/organizaciones → monitorear → suspender → cerrar/archivar.

Para cada pantalla incluye carga, vacío, error, éxito, sin resultados, permiso insuficiente, dato vencido, conflicto, offline y contenido extremo. La lista accesible debe ofrecer la misma información y acciones esenciales que el mapa.

════════════════════════════════════════════════════════════════════
6B. MÉTRICAS QUE DEBEN RECONCILIAR
════════════════════════════════════════════════════════════════════

- porcentaje y tiempo mediano/p95 de verificación;
- porcentaje de registros vencidos, no ubicados, duplicados, desmentidos y reabiertos;
- cobertura de necesidad por cantidad/unidad, territorio y población, sin exponer individuos;
- tasa de promesa cumplida, aceptación, rechazo, daño, pérdida y entrega validada;
- exactitud de inventario y diferencias por conteo;
- tiempo de recepción → asignación → despacho → entrega;
- recibido, conciliado, restringido, disponible, comprometido, gastado, revertido y reembolsado;
- conciliaciones fallidas, contracargos y gastos sin soporte dentro del SLA;
- tiempo de resolución de fraude, queja, rectificación y solicitud de titular;
- disponibilidad, éxito de sincronización, duplicados evitados y recuperación;
- accesibilidad, rendimiento y tasa de abandono por recorrido.

Cada métrica debe declarar fórmula, fuente, zona horaria, moneda/unidad, periodicidad, dimensiones permitidas, dueño y prueba de conciliación. Prohíbe sumar cantidades incompatibles o presentar actividad como impacto.

════════════════════════════════════════════════════════════════════
6C. INTEGRACIÓN DEL FLUJO “UNIDOS NOS CUIDAMOS”
════════════════════════════════════════════════════════════════════

Conserva del micrositio actual su fortaleza principal: registro guiado, breve, una respuesta por aporte, atribución entre donante y aliado gestor, contacto privado y tablero de transparencia. Reubícalo como canal de ingreso de aliados dentro de la plataforma. No lo uses como base de datos, libro mayor, comprobante de entrega ni fuente de publicación inmediata.

CONTRATO DE INTEGRACIÓN

- La interfaz puede seguir siendo pública para explicar la iniciativa y mostrar transparencia agregada.
- Registrar un aporte requiere identidad verificada del representante o un enlace seguro emitido a un aliado; elegir un nombre de una lista no acredita pertenencia.
- Cada envío crea `donation_intake` y uno o más `donation_intake_item` con ID, versión, origen, fecha, evento, organización, clave idempotente y huella de evidencia.
- El envío queda en `Reportado / Pendiente de verificación`. Nunca crea por sí solo inventario, ingreso financiero, entrega validada, certificado, impacto ni publicación.
- Las personas verificadoras comparan soporte, identidad, cantidades, destino y duplicados. Aprobado el ingreso, el sistema crea o vincula las entidades operacionales correspondientes.
- Solo `public_donation_projection`, derivada de datos autorizados y conciliados, alimenta el tablero público.
- La iniciativa puede registrar aportes económicos administrados externamente, pero no debe presentarse como recaudadora ni receptora. El sistema registra organización/fondo/operador y evidencia; no captura tarjetas, claves ni cuentas informales.

RECORRIDO CANÓNICO

Portal público
  → autenticación/enlace seguro del aliado
  → formulario breve con guardado de borrador
  → validación estructural y antisuplantación
  → Reportado / Pendiente de verificación
  → deduplicación, moderación y revisión de evidencia
  → Aprobado | Observado | Rechazado | Duplicado | Cancelado
  → bifurcación Especie | Económica
  → recorrido operacional y conciliación
  → proyección pública segura
  → cierre, rectificación o reapertura auditable

PASOS DEL FORMULARIO AJUSTADO

PASO 1 — QUIÉN REPORTA

- `organization_id` se deriva de la sesión, membresía o invitación; no de un selector confiado por el servidor.
- Captura nombre legal/identificador interno del donante con acceso restringido.
- Captura por separado `public_attribution`: organización autorizada, nombre autorizado, alias o anónimo.
- Para persona natural, exige una decisión expresa de atribución y conserva fecha, texto y versión de autorización cuando aplique.
- Tipo de donante y sector usan catálogos versionados. “Otro” exige detalle, sin convertir observaciones en un cajón de datos sensibles.
- Responsable, teléfono y correo son operacionales y privados; nunca salen por API pública, exportación o analítica.

PASO 2 — QUÉ SE APORTA

- Pregunta primero `Especie` o `Económica` y muestra solamente los campos del recorrido elegido.
- Permite varias líneas por aporte. Cada línea tiene categoría, descripción, cantidad y unidad normalizada.
- En especie, cantidad y unidad son obligatorias; agrega condición, empaque, vencimiento/lote cuando aplique, restricciones, disponibilidad y requisito de almacenamiento.
- Valida anticipadamente artículos prohibidos, abiertos, vencidos o incompatibles con la capacidad del centro.
- El valor comercial estimado de especie es opcional e indicativo. Registra moneda, método, fuente, fecha y responsable; no equivale a valor conciliado ni base de certificado tributario.
- En dinero, captura monto, moneda, organización/fondo verificado, operador externo, referencia segura y soporte. Nunca captura datos completos de pago ni publica la referencia.
- Separa `declared_amount`, `verified_amount`, `reconciled_amount` y, cuando proceda, `tax_eligible_value`.

PASO 3 — PARA QUÉ Y DÓNDE

- Permite vincular el aporte a `need_case/need_item` o `fund`. Una destinación en texto no reemplaza ese vínculo.
- Usa códigos territoriales versionados y DIVIPOLA; conserva el texto original solo como evidencia de origen.
- “Sin definir” puede existir internamente como pendiente de asignación, pero no se muestra como destino verificado.
- Distingue ubicación operacional precisa de proyección pública segura.
- `beneficiaries_estimated` exige método, fuente, periodo y alcance. No se suma como personas únicas y no reemplaza resultado validado.

PASO 4 — SOPORTE Y SEGUIMIENTO

- El reportante puede declarar si el aporte está comprometido, en gestión, en tránsito o aparentemente entregado; el dato se guarda como `declared_status`.
- El servidor controla los estados operacionales. “Entregada” requiere entrega, receptor autorizado, cantidades, fecha y evidencia; “Validada” exige confirmación o decisión autorizada adicional.
- Canal/operador se vincula a una organización o proveedor cuando exista. El texto libre es solo respaldo temporal.
- Evidencias se almacenan en privado, se escanean, se clasifican y se publican únicamente mediante versión redactada/aprobada.

PASO 5 — REVISIÓN Y CONSTANCIA

- Antes de enviar, muestra resumen, política de privacidad, atribución pública, campos que permanecerán privados y declaración de veracidad.
- Requiere una clave idempotente para impedir duplicados por doble clic, reintento o mala conectividad.
- Devuelve código seguro y constancia de recepción del reporte. La constancia no afirma recepción física, conciliación financiera, entrega ni beneficio.
- Permite corregir, retirar o responder observaciones sin sobrescribir el historial.

ESTADOS DE INGRESO

- `Borrador → Reportado → Pendiente de verificación → Aprobado`.
- Alternos: `Observado`, `Rechazado`, `Duplicado`, `Cancelado`, `En cuarentena`.
- `Aprobado` crea/vincula el registro operacional, pero no significa entregado ni publicado.

ESTADOS DE ESPECIE DESPUÉS DE APROBACIÓN

- `Prometida → Programada → Recibida → Inspeccionada → Clasificada/Almacenada → Asignada → Despachada → En tránsito → Entregada → Validada → Cerrada`.
- Alternos: `Parcial`, `Rechazada`, `En cuarentena`, `Novedad`, `Devuelta`, `Perdida`, `Dada de baja`, `Cancelada`.
- Cada transición exige actor, fecha, cantidades, ubicación/custodio y evidencia/regla aplicable.

ESTADOS DE DINERO DESPUÉS DE APROBACIÓN

- Si el aporte ocurrió fuera de la plataforma: `Reportado → Soporte verificado → Conciliado con fondo/operador → Restringido/Disponible → Comprometido → Gastado/Pagado → Soportado → Cerrado`.
- Si existe proveedor autorizado: `Iniciado → Confirmado por proveedor → Conciliado → Restringido/Disponible → Comprometido → Gastado/Pagado → Soportado → Cerrado`.
- Alternos: `Fallido`, `Revertido`, `Contracargo`, `Reembolsado`, `En disputa`, `Rechazado`.
- Ningún monto declarado alimenta las métricas `recibido`, `conciliado`, `gastado` o `saldo`.

TABLERO PÚBLICO AJUSTADO

- Muestra únicamente registros aprobados para publicación y derivados de estados conciliados.
- Diferencia visualmente `Reportado por aliado`, `Verificado`, `Recibido`, `En tránsito`, `Entregado` y `Validado`; no reduce todo a “aporte registrado”.
- Incluye ID público, última actualización, aliado gestor, atribución autorizada, tipo, categoría, cantidad/unidad verificada, valor con clase claramente rotulada, destino a precisión segura y nivel de evidencia.
- Las cifras declaran fórmula, fecha de corte y cobertura. Los estimados no se presentan como hechos ni se mezclan con valores conciliados.
- No publica responsables, teléfonos, correos, referencias de pago, soportes sin redacción, ubicaciones precisas ni nombres de personas sin autorización.
- Un retiro o corrección genera nueva versión y explica el cambio sin borrar el registro de auditoría.

MIGRACIÓN DEL EXCEL ACTUAL

Trata las hojas actuales como legado:

- `Registro`: staging de 22 columnas, no tabla canónica. En el archivo auditado contiene únicamente el encabezado y ninguna fila de aporte; sirve para mapear esquema, no para afirmar que el registro vivo esté vacío.
- `Listas`: insumo inicial de catálogos; después de migrar se reemplaza por catálogos versionados servidos por API.
- `Tablero`: referencia visual; sus fórmulas no son fuente de métricas. Algunas funciones `QUERY`, `FILTER` y `UNIQUE` son específicas de Google Sheets y se degradan a `#NAME?` en Excel.

Mapeo mínimo:

- `N°` → `legacy_row_id`; `Fecha de registro` → `submitted_at`.
- `Aliado que reporta` → candidato a `organization_id`, sujeto a resolución y verificación.
- `Nombre del donante` → dato interno; crear aparte `public_attribution` y autorización.
- `Tipo/Sector` → catálogos versionados.
- `Tipo de donación` → discriminador del recorrido.
- `Categoría/Descripción/Cantidad/Unidad` → una o varias líneas `donation_intake_item` normalizadas.
- `Valor estimado` → `declared_estimated_value_cop`; nunca a libro financiero ni certificado sin validación.
- `Destinación/Departamento/Municipio` → vínculo a necesidad/fondo y geografía normalizada.
- `Beneficiarios estimados` → estimación con método pendiente; no personas únicas.
- `Estado del aporte` → `declared_status`, no estado operacional.
- `Canal/operador` → candidato a organización/proveedor.
- `Responsable/Contacto` → datos privados restringidos.
- `Observaciones` → nota de origen sometida a clasificación de sensibilidad.

Agrega durante importación: `migration_batch_id`, `source_system`, `external_row_id`, `event_id`, `idempotency_key`, `quality_errors`, `duplicate_of`, `verification_state`, `verified_by`, `verified_at`, `donation_id`, `need_id`, `fund_id`, `receipt_id`, `inventory_lot_id`, `shipment_id`, `delivery_id`, `financial_transaction_id`, `public_visibility`, `published_at` y `last_reconciled_at`.

Ejecuta la migración en este orden: snapshot y checksum → perfilado/PII → resolución de aliados → normalización de catálogos/unidades/territorios → detección de duplicados → importación en cuarentena → verificación muestral y conciliación → aprobación humana → publicación gradual. Ninguna fila se vuelve verificada por existir en el libro.

PRUEBAS DE ACEPTACIÓN DEL CANAL

1. Un visitante sin membresía no puede atribuir un reporte a un aliado.
2. Dos envíos idénticos con la misma clave producen un solo ingreso; un posible duplicado distinto queda enlazado, no borrado.
3. Un aporte recién reportado no aparece en el tablero público.
4. Un estado “Entregada” declarado no cambia inventario, entrega ni cobertura.
5. Una donación en especie con dos categorías crea dos líneas y conserva un solo código de aporte.
6. Cantidad/unidad inválida, artículo prohibido o destino inconsistente produce error accionable o cuarentena.
7. Un monto económico declarado no afecta recibido/saldo hasta ser conciliado contra fondo/operador.
8. Contactos, referencias y evidencia privada no aparecen en API, exportación, logs ni analítica pública.
9. Nombre de persona natural se publica solo con atribución autorizada; anónimo/alias se respeta en toda superficie.
10. Las cifras del tablero concilian con consultas independientes y siguen conciliando tras reverso, corrección o retiro.
11. La importación del Excel reporta totales de entrada, aprobados, rechazados, duplicados y cuarentena, y puede revertirse.
12. Cambio de catálogo no exige editar manualmente hoja, Apps Script y micrositio: todos consumen la misma versión de API.

CRITERIO DE SALIDA DE LA INTEGRACIÓN

El canal “Unidos Nos Cuidamos” queda integrado cuando un aliado autenticado puede reportar especie o dinero, recibir constancia, atender observaciones y seguir el registro; una persona autorizada puede verificarlo y bifurcarlo; las cadenas operacionales concilian; y el tablero muestra solo una proyección segura, explicable y reproducible. Deben ser cero las publicaciones automáticas no verificadas, las cifras derivadas de campos declarados y los contactos expuestos.

════════════════════════════════════════════════════════════════════
7. ESCENARIOS E2E OBLIGATORIOS
════════════════════════════════════════════════════════════════════

ESCENARIO A — DONACIÓN EN ESPECIE

1. Una organización verifica una necesidad de 200 unidades de agua.
2. Un donante promete 100.
3. Un punto de acopio recibe 95 y rechaza 5 con motivo.
4. Se almacenan 95, se asignan 90 y se despachan 90.
5. El receptor confirma 89 y registra 1 unidad dañada.
6. La necesidad queda parcialmente cubierta por 89.
7. Inventario, cobertura, comprobante, trazabilidad pública y auditoría concilian.

ESCENARIO B — DONACIÓN ECONÓMICA EN SANDBOX

1. Una organización y un fondo están verificados.
2. Entra un pago sandbox de COP 1.000.000.
3. Webhook y conciliación repetidos no duplican el ingreso.
4. Se solicita un gasto de COP 300.000.
5. Lo aprueba una persona diferente y se adjunta soporte.
6. El panel muestra recibido, comprometido/gastado, reversos y saldo exactos.
7. El libro, el gasto y la vista pública concilian.

ESCENARIO C — FRAUDE, DUPLICADOS Y PRIVACIDAD

1. Un ciudadano intenta publicar una cuenta bancaria y un teléfono personal.
2. El sistema bloquea o envía el contenido a moderación y registra el evento.
3. Dos reportes de la misma necesidad son detectados y unificados sin perder autoría.
4. La ubicación exacta y la evidencia permanecen privadas; el mapa solo muestra precisión permitida.
5. Un usuario sin permiso no puede elevar su rol ni consultar el registro protegido.

ESCENARIO D — OPERACIÓN SIN CONEXIÓN

1. Un punto de acopio autorizado recibe artículos offline.
2. La operación queda en una cola local segura con identificador idempotente.
3. Al recuperar conexión se sincroniza dos veces de manera intencional.
4. Solo existe una recepción, un movimiento de inventario y la secuencia correcta de auditoría.
5. Un conflicto de cantidades requiere resolución explícita y no sobrescribe silenciosamente.

ESCENARIO E — MIGRACIÓN DEL MAPA VIVO

1. Se importa un snapshot anonimizado que contiene registros válidos, exactos, duplicados, vencidos, sin ubicación, desmentidos y con PII.
2. El lote conserva identificador legado, fuente, corte y checksum.
3. PII y contenido monetario ciudadano quedan bloqueados de la vista pública.
4. Duplicados se relacionan sin borrar la fuente; vencidos/no ubicados pasan a cuarentena.
5. Ningún dato se vuelve verificado solo por importarse.
6. Conteos de entrada, salida, rechazo y cuarentena concilian y el rollback restaura el estado previo.

ESCENARIO F — BIEN RESTRINGIDO, CADENA DE FRÍO Y RETIRO

1. Un donante ofrece medicamentos abiertos y alimentos que requieren frío a un centro sin capacidad.
2. La plataforma rechaza o redirige antes del traslado y explica el motivo.
3. Un lote aceptado registra después una ruptura de temperatura y queda en hold.
4. El sistema impide asignarlo/despacharlo, identifica cualquier entrega afectada y ejecuta un retiro auditable.
5. Inventario, comprobante y transparencia reflejan la novedad sin borrar movimientos.

ESCENARIO G — CONCURRENCIA, ABUSO Y RECUPERACIÓN

1. Dos operadores intentan asignar simultáneamente las mismas 50 unidades.
2. Solo una reserva válida se confirma y no aparece stock negativo.
3. Un actor malicioso intenta subir un archivo ejecutable, publicar una cuenta, enumerar códigos y consultar otra organización.
4. Las acciones son bloqueadas, limitadas y auditadas sin filtrar datos en logs.
5. Se simula caída de una dependencia y restauración desde backup; RPO/RTO y conciliaciones cumplen el objetivo definido.

ESCENARIO H — INGRESO DE ALIADO Y PUBLICACIÓN CONTROLADA

1. Un representante autenticado registra un aporte en especie con dos líneas, contacto privado y atribución anónima para una persona donante.
2. El sistema devuelve constancia, pero el aporte no aparece en el tablero ni afecta inventario o cobertura.
3. Un reintento con la misma clave no duplica el ingreso; la verificación observa una cantidad y solicita corrección.
4. El aliado corrige sin borrar la versión anterior; un verificador aprueba y crea la promesa operacional.
5. La recepción parcial, el despacho y la entrega validada actualizan la proyección pública por eventos conciliados.
6. Contacto, evidencia original, ubicación precisa y nombre interno no aparecen en la vista pública ni en exportaciones.
7. Tablero, inventario, entrega y auditoría concilian; un reverso genera versión compensatoria.

Los ocho escenarios deben ejecutarse automáticamente en CI o en un entorno reproducible. Cuando un servicio externo no esté disponible, usa un adaptador sandbox fiel al contrato y deja explícito qué falta para producción. Los escenarios que involucran daño físico, dinero real o datos personales se prueban con datos sintéticos y proveedores sandbox.

════════════════════════════════════════════════════════════════════
8. SCORECARD Y CONDICIÓN DE CONTINUIDAD
════════════════════════════════════════════════════════════════════

Califica cada frente después de cada ciclo:

- 0 = ausente.
- 1 = maqueta o prototipo no persistente.
- 2 = funcional, pero incompleto o sin evidencia suficiente.
- 3 = criterios de aceptación y pruebas principales aprobados.
- 4 = endurecido, documentado, observable y listo para operación.

Frentes mínimos:

- gobernanza y multi-evento;
- contención y migración del legado;
- operación humanitaria, RACI y SLA;
- identidad, organizaciones y permisos;
- canal de ingreso de aliados y verificación;
- necesidades y verificación;
- donaciones en especie;
- inventario y logística;
- donaciones económicas;
- transparencia;
- privacidad y protección de datos;
- seguridad y antifraude;
- auditoría e integridad;
- accesibilidad y responsive;
- offline y resiliencia;
- observabilidad y operación;
- documentación y preparación de salida.

Continúa el loop mientras cualquier frente crítico esté por debajo de 3. Seguridad, privacidad, finanzas, auditoría, migración y recuperación deben llegar a 4 antes de recomendar producción.

PUERTAS DE MADUREZ

- **G0 — Desarrollo listo:** Puerta Cero aprobada, arquitectura decidida, datos sintéticos, primer recorrido definido, P0/P1 de especificación en cero. Permite codificar local/sandbox.
- **G1 — Staging funcional:** recorridos críticos en nivel ≥3, ocho E2E aprobados, migración ensayada, seguridad/privacidad sin P0/P1. Permite demostración controlada.
- **G2 — Piloto territorial:** operador y organizaciones definidos, usuarios capacitados, soporte/SLA activos, DPIA y amenaza revisados, restauración probada y criterios de abortar acordados. Permite piloto limitado mediante autorización explícita.
- **G3 — Producción:** finanzas, privacidad, seguridad, auditoría, migración y recuperación en nivel 4; validaciones jurídica/contable/humanitaria cerradas; acuerdos, credenciales, monitoreo, incidentes y rollback listos. Requiere autorización explícita.

No confundas G0 con G3. Un bloqueo de producción no impide avanzar en sandbox, pero debe permanecer visible y no puede simularse como resuelto.

════════════════════════════════════════════════════════════════════
9. DECISIONES QUE REQUIEREN INTERVENCIÓN HUMANA
════════════════════════════════════════════════════════════════════

Pide una decisión únicamente cuando sea necesaria para continuar de forma responsable, por ejemplo:

- entidad jurídica operadora y responsable del tratamiento de datos;
- autoridad operacional que define triage, rescate, escalamiento y relación con el PMU/SNGRD;
- organizaciones habilitadas para verificar, custodiar o recibir recursos;
- política de bienes aceptados, cadena de frío, valoración, certificados y disposición final;
- proveedor financiero, titular del fondo y credenciales de producción;
- política AML/KYB/KYC, donación restringida, anonimato, reembolso y contracargo;
- política aprobada de publicación, retención y atención de derechos de titulares;
- padrón de aliados autorizados, representantes habilitados, uso de marcas/logos institucionales y texto de respaldo público;
- dominio, DNS, cuentas, contratos o acceso a infraestructura real;
- despliegue público, comunicación externa o activación de cobros;
- aceptación formal de un riesgo crítico;
- migración irreversible o eliminación material de datos.
- activación de migración/corte del mapa vivo y criterios de abortar.

Si la decisión no bloquea, adopta una suposición conservadora, reversible y claramente documentada; continúa con sandbox o adaptadores. Nunca simules que la aprobación ya ocurrió.

════════════════════════════════════════════════════════════════════
10. DEFINICIÓN GLOBAL DE TERMINADO
════════════════════════════════════════════════════════════════════

El producto solo está terminado para producción cuando:

- los hitos -1–7 satisfacen sus criterios de salida;
- los ocho escenarios E2E obligatorios pasan;
- no hay defectos P0/P1 abiertos ni fallos introducidos por el trabajo;
- no quedan mocks, TODO o rutas simuladas en operaciones críticas;
- permisos, separación de funciones, privacidad y antifraude están probados;
- inventario, cobertura, libro financiero y cifras públicas concilian;
- las migraciones y el procedimiento de recuperación han sido ensayados;
- los recorridos críticos cumplen WCAG 2.2 AA y los tamaños responsive definidos;
- build, pruebas, análisis de seguridad y comprobaciones de producción pasan;
- observabilidad, alertas, backups, restauración y runbooks están listos;
- documentos de producto, datos, decisiones, riesgos, operación y release están vigentes;
- cada requisito figura en la matriz con implementación, prueba y evidencia;
- un entorno de staging ha sido verificado si existe autorización para desplegar;
- los únicos pendientes son decisiones externas identificadas con responsable e impacto.
- G3 está aprobado por las personas responsables y la autorización de salida quedó registrada.
- el sistema vivo fue comparado contra staging/piloto y el corte o coexistencia no pierde registros, auditoría ni capacidad de rollback.
- el cierre del evento contempla archivo, anonimización/supresión aplicable, conciliación final y conservación legal de soportes.

Que el proyecto compile o que una pantalla se vea bien no equivale a terminado.

════════════════════════════════════════════════════════════════════
11. INFORME AL CIERRE DE CADA CICLO
════════════════════════════════════════════════════════════════════

Entrega y registra este resumen breve:

- Ciclo e hito:
- Recorrido terminado:
- Criterios de aceptación:
- Archivos/migraciones modificados:
- Validaciones ejecutadas y resultado:
- Evidencia disponible:
- Riesgos nuevos o cerrados:
- Decisiones y supuestos:
- Bloqueos externos:
- Nivel de madurez actual G0/G1/G2/G3:
- Scorecard actualizado:
- Próximo recorrido:

Después del informe, continúa con el próximo ciclo si aún no se cumple la definición global de terminado. No te detengas solo porque finalizó una fase, se agotó el contexto o ya existe una demo.

════════════════════════════════════════════════════════════════════
12. INSTRUCCIÓN DE INICIO
════════════════════════════════════════════════════════════════════

Comienza ahora. Inspecciona el repositorio y el producto renderizado, establece la línea base, crea o actualiza la memoria persistente y ejecuta las cinco rondas de Puerta Cero. Corrige y repite hasta obtener P0 = 0 y P1 = 0 en la especificación. Solo entonces inicia el primer recorrido vertical seguro hacia G0/G1. No pidas confirmación para decisiones técnicas reversibles dentro del alcance. Si encuentras una decisión humana bloqueante, presenta opciones concretas, el impacto de cada una y todo el trabajo que puede continuar en sandbox sin inventar autorizaciones.
```

## Prompt corto para reanudar

Si el loop ya está instalado en el repositorio, basta con iniciar una nueva sesión con:

```text
Lee por completo el loop maestro del proyecto y los archivos de `docs/` que conforman su memoria persistente. Verifica el estado real del repositorio, la última Puerta Cero y el nivel G0/G1/G2/G3. Continúa desde el último ciclo comprobado. Ejecuta recorridos verticales, repara cualquier validación fallida y no te detengas hasta alcanzar la siguiente puerta autorizada o documentar un bloqueo externo real con trabajo independiente agotado.
```

## Principio operativo

La unidad de avance no es una pantalla, una tabla o un número de commits. Es un recorrido completo que deja una necesidad o una donación más cerca de un resultado humanitario verificable, sin romper seguridad, privacidad, contabilidad ni cadena de custodia.

## Referencia metodológica

El diseño de este loop sigue el patrón recomendado para trabajos extensos con Codex: planificar, editar, ejecutar verificaciones, observar, reparar, conservar el estado en archivos durables y repetir con criterios de aceptación. Véase [OpenAI — Run long-horizon tasks with Codex](https://developers.openai.com/blog/run-long-horizon-tasks-with-codex).

## Fuentes de control que el proyecto debe registrar y verificar

- [Mapa de emergencia existente](https://mapa-emergencia.artefactofilms.workers.dev/): legado público de necesidades y orientación que debe contenerse y migrarse por fases.
- [Unidos Nos Cuidamos](https://unidos-nos-cuidamos.netlify.app/): canal de registro de aportes de aliados auditado para la integración de esta versión.
- `UNIDOS NOS CUIDAMOS · Registro de donaciones.xlsx`: libro legado inspeccionado con hojas `Registro`, `Listas` y `Tablero`; debe tratarse como staging y no como fuente transaccional.
- [Servicio Geológico Colombiano — información del sismo de San José del Palmar](https://www2.sgc.gov.co/Noticias/Paginas/SGC-actualiza-la-informacion-sobre-el-sismo-ocurrido-en-San-Jose-del-Palmar-Choco.aspx): fuente del evento sísmico, no del estado de cada necesidad.
- [UNGRD — respuesta nacional al sismo](https://portal.gestiondelriesgo.gov.co/Paginas/Noticias/2026/Gobierno-nacional-despliega-respuesta-ante-sismo-en-Choc%C3%B3-bajo-liderazgo-del-presidente-Abelardo-de-la-Espriella.aspx): coordinación y afectaciones oficiales iniciales.
- [DANE — DIVIPOLA](https://www.dane.gov.co/index.php/sistema-estadistico-nacional-sen/normas-y-estandares/nomenclaturas-y-clasificaciones/nomenclaturas/codificacion-de-la-division-politica-administrativa-de-colombia-divipola): codificación territorial normalizada.
- [Ley 1581 de 2012 — Gestor Normativo de Función Pública](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=49981): marco colombiano de protección de datos; requiere interpretación jurídica aplicada al operador.
- [DIAN — Concepto 6107 de 2024](https://normograma.dian.gov.co/dian/compilacion/docs/oficio_dian_6107_2024.htm): valoración, factura y contenido/soporte de certificados para donaciones de bienes.
- [OCHA — Data Responsibility Guidelines](https://www.unocha.org/publications/report/world/data-responsibility-guidelines-october-2021): gestión segura, ética y efectiva de datos humanitarios.
- [IFRC — Data Protection in Cash and Voucher Assistance](https://www.ifrc.org/document/practical-guidance-data-protection-cash-and-voucher-assistance): protección de datos en asistencia económica.
- [Sphere — Humanitarian Standards](https://spherestandards.org/humanitarian-standards/): calidad y rendición de cuentas en respuesta humanitaria.

Estas referencias orientan el `COMPLIANCE_REGISTER`; el equipo debe comprobar su vigencia, alcance y aplicabilidad antes de cada puerta de piloto o producción.

## Acta de validación del loop 3.0

| Ronda | Brechas encontradas | Ajuste realizado | Resultado |
|---|---|---|---|
| Evidencia del producto vivo | Urgencia predeterminada, PII pública, datos vencidos y mezcla de flujos | Hito -1, contención, migración y separación de dominios | Aprobada |
| Flujo “Unidos Nos Cuidamos” | Publicación inmediata, aliado autoatribuido, estado declarado tratado como real y especie/dinero en un único esquema | Ingreso autenticado no verificado, bifurcación operacional, proyección pública y escenario H | Aprobada para desarrollo |
| Libro de registro y tablero | 22 columnas sin IDs transaccionales, catálogos sincronizados manualmente y fórmulas específicas de Sheets | Staging versionado, mapeo de migración, API canónica y métricas conciliadas en base de datos | Aprobada para migración ensayada |
| Cobertura operacional | Faltaban RACI/SLA, rescate especializado, bienes restringidos y retiro | Operating model, triage, FEFO/cadena de frío y escenarios F/G | Aprobada |
| Cumplimiento y finanzas | Certificado confundible con recibo; faltaban valoración, factura, contracargo y fondos restringidos | Flujos fiscales separados, soportes y puertas humanas | Aprobada para sandbox |
| Ingeniería de largo alcance | Faltaban gate de entrada, reanudación robusta y control contra loops ciegos | Puerta Cero, checkpoints, evidencia y regla de cambio de táctica | Aprobada |
| Red team y salida | Faltaban concurrencia, migración adversarial, recuperación y niveles de madurez | Ocho E2E y puertas G0–G3 | Aprobada |

**Resultado final del artefacto:** cero brechas P0/P1 conocidas en la especificación después de la última ronda. Los bloqueos restantes —operador jurídico, autoridades/organizaciones, padrón e identidad de aliados, uso autorizado de marcas, política de datos, proveedor financiero y autorización de producción— están aislados como decisiones humanas y no impiden iniciar G0 en sandbox.
