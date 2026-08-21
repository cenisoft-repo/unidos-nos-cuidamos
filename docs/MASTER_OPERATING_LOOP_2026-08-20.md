# UNIDOS NOS CUIDAMOS — MASTER OPERATING LOOP
## Especificación única para Claude Code / Codex / agentes de desarrollo

**Repositorio:** `https://github.com/cenisoft-repo/unidos-nos-cuidamos`  
**Rama base:** `main`

---

# 0. CÓMO USAR ESTE DOCUMENTO

Este archivo es la fuente maestra para continuar el desarrollo.

Orden de trabajo:
1. Lee este documento completo una sola vez al iniciar una nueva sesión.
2. Lee `docs/ai/STATE.md`.
3. Lee `docs/ai/DECISIONS.md` si contiene decisiones vigentes.
4. Revisa `git status`, `git log -n 8 --oneline` y el diff actual.
5. Inspecciona únicamente los archivos relacionados con el siguiente delta.
6. Implementa.
7. Prueba de menor a mayor costo.
8. Repara.
9. Actualiza `docs/ai/STATE.md`.
10. Continúa con el siguiente delta pendiente.

Directiva principal:

> **NO RECONSTRUIR. REUTILIZAR → EXTENDER → CORREGIR → CREAR.**

Si algo ya existe y funciona, consérvalo.  
Si existe pero está incompleto, extiéndelo.  
Si existe pero es incorrecto, corrígelo.  
Solo crea arquitectura nueva cuando el repositorio no tenga una base reutilizable.

---

# 1. MISIÓN DEL PRODUCTO

**Unidos Nos Cuidamos** debe operar como una red logística humanitaria capaz de dar trazabilidad completa a una ayuda desde que se registra hasta que se recibe y entrega.

La operación privada debe simplificarse alrededor de tres acciones humanas:

# SOLICITAR
Necesito mercancía.

# RECIBIR
Está llegando mercancía.

# DESPACHAR
Tengo mercancía que debe salir.

Todo lo demás debe soportar estas acciones:

- inventario;
- lotes;
- Kardex;
- reservas;
- solicitudes;
- autorización;
- picking;
- transporte;
- recepción;
- novedades;
- evidencia fotográfica;
- auditoría;
- mapa;
- tracking;
- transparencia.

El sistema debe ser usable durante una emergencia real desde escritorio, tablet y teléfono.

---

# 2. REALIDAD ACTUAL DEL REPOSITORIO

No asumas que estás iniciando un proyecto nuevo.

La base actual ya contiene, entre otras capacidades:

- Next.js;
- Supabase/PostgreSQL;
- autenticación;
- perfiles;
- organizaciones;
- membresías;
- roles;
- SUPER_ADMIN;
- RLS;
- alcance por organización;
- alcance por bodega mediante `membership_locations`;
- centros/puntos parametrizables;
- inventario por lote;
- stock movements;
- Kardex;
- posiciones derivadas de inventario;
- recepción;
- reservas;
- `allocations`;
- necesidades;
- `transfer_requests`;
- autorización parcial;
- despachos;
- transporte;
- recepción destino;
- entregas;
- auditoría;
- evidencia privada;
- Storage privado;
- hashes;
- mapas;
- proyecciones públicas;
- seguimiento;
- transparencia;
- PWA;
- pruebas unitarias;
- pgTAP;
- pruebas RLS;
- pruebas de concurrencia;
- Playwright;
- auditoría de accesibilidad;
- auditoría visual;
- memoria persistente en `docs/ai`.

Por tanto:

> **No crees `inventory_v2`, `new_warehouse`, `evidence_v2`, `users_v2` ni motores paralelos.**

---

# 3. ARCHIVOS QUE DEBES CONOCER

Antes de tocar el núcleo operativo inspecciona, según corresponda:

## Estado y calidad
- `docs/ai/STATE.md`
- `docs/ai/CHARTER.md`
- `docs/ai/PLAN.md`
- `docs/ai/QUALITY.md`
- `docs/ai/DESIGN_QUALITY.md`
- `docs/ai/DECISIONS.md`
- `docs/GAP_LEDGER.md` si existe

## Operación
- `src/app/operaciones/page.tsx`
- `src/app/operaciones/bodega/page.tsx`
- `src/app/operaciones/centros/page.tsx`
- `src/app/operaciones/parametrizacion/page.tsx`
- `src/app/operaciones/reportes/**`
- `src/app/operaciones/tesoreria/**`

## Componentes
- `src/components/warehouse-console.tsx`
- `src/components/platform-parameterization.tsx`
- `src/components/delivery-points-manager.tsx`
- `src/components/donation-intake-form.tsx`
- `src/components/intake-evidence-review.tsx`
- `src/components/tracking-form.tsx`
- `src/components/coverage-explorer.tsx`
- `src/components/transparency-dashboard.tsx`

## Seguridad
- `src/lib/authorization.ts`
- clientes Supabase server/client
- helpers de errores
- helpers de idempotencia
- scripts RLS/concurrencia

## Migraciones clave
Inspecciona especialmente las relacionadas con:
- Kardex;
- transferencias;
- transporte;
- SUPER_ADMIN;
- evidencia;
- mapa;
- alcance por bodega;
- reportes.

Entre las más relevantes:
- `202608190003_inventory_kardex_position.sql`
- `202608190005_warehouse_transfers_and_transport.sql`
- `202608200002_super_admin_authority.sql`

No dependas exclusivamente de esta lista. Mira qué existe actualmente en `main`.

---

# 4. REGLA DE RAZONAMIENTO

No todas las tareas merecen el mismo nivel de razonamiento.

## Razonamiento máximo
Úsalo para:
- SQL;
- PostgreSQL;
- RLS;
- concurrencia;
- locks;
- idempotencia;
- permisos;
- seguridad;
- migraciones;
- diseño de dominio;
- tenant isolation;
- transacciones;
- recuperación/compensación;
- bugs no triviales.

## Razonamiento medio
Úsalo para:
- componentes React;
- flujos UX;
- organización de estados;
- APIs server-side;
- tests E2E;
- refactors localizados.

## Ejecución rápida
Úsala para:
- CSS;
- copy;
- wiring;
- tipos;
- iconografía;
- accesibilidad obvia;
- tests derivados;
- ajustes visuales;
- refactors mecánicos.

No gastes razonamiento profundo en decisiones ya cerradas.

---

# 5. STOP RULES PARA EVITAR SOBREANÁLISIS

Deja de investigar y empieza a implementar cuando:
- ya identificaste el contrato existente;
- sabes qué archivo(s) deben cambiar;
- el cambio es reversible;
- no existe una incertidumbre P0 de seguridad o integridad.

No preguntes por decisiones triviales o reversibles.

No vuelvas a estudiar todo el repositorio después del primer ciclo.

Después de la primera inspección usa:
- `rg`;
- búsqueda por símbolos;
- `git diff`;
- archivos directamente afectados.

---

# 6. PRIORIDADES GLOBALES

Si dos objetivos entran en conflicto, manda este orden:

1. Seguridad.
2. Integridad del inventario.
3. Tenant isolation.
4. Trazabilidad.
5. Operación.
6. Evidencia.
7. UX.
8. Estética.

Nunca sacrifiques 1–5 por mejorar 7–8.

---

# 7. ARQUITECTURA OPERATIVA OBJETIVO

La red debe soportar dos caminos principales.

## Camino A — necesidad
NECESIDAD
→ asignación
→ reserva
→ preparación
→ despacho

## Camino B — solicitud logística
CENTRO / MUNICIPIO / ENTIDAD
→ solicitud
→ autorización
→ reserva
→ preparación
→ despacho

Ambos convergen en:

TRANSPORTE
→ RECEPCIÓN DESTINO
→ EVIDENCIA
→ CONCILIACIÓN
→ AUDITORÍA
→ TRANSPARENCIA

Una necesidad NO debe ser requisito obligatorio para mover inventario.

---

# 8. EJE P0 — SOLICITUD LOGÍSTICA GENERALIZADA

Actualmente existe infraestructura de transferencia.

La misión es generalizarla.

No crear un segundo motor si puede evolucionarse el actual.

Debe permitir:

Centro A
→ solicita inventario
→ Centro B

aunque pertenezcan a organizaciones diferentes,

si ambos pertenecen al mismo evento y la política operacional lo permite.

Permitir solicitar inventario a otra organización NO significa permitir leer toda su información.

La organización solicitante solo debe ver una proyección segura de disponibilidad.

---

# 9. SOLICITUD MULTIPRODUCTO

Una solicitud debe contener una cabecera y N líneas.

## Cabecera conceptual
- id;
- código legible;
- evento;
- centro solicitante;
- organización solicitante;
- centro proveedor;
- organización proveedora;
- solicitado por;
- fecha;
- justificación;
- necesidad opcional;
- estado;
- timestamps;
- observaciones seguras.

## Línea conceptual
- categoría;
- unidad;
- modo de solicitud;
- cantidad solicitada;
- lote opcional;
- cantidad autorizada;
- cantidad reservada;
- cantidad despachada;
- cantidad recibida;
- diferencias.

No almacenes valores redundantes que puedan derivarse de forma fiable.

---

# 10. MODOS DE SOLICITUD

Cada línea debe poder operar en uno de estos modos.

## EXACT_QUANTITY
Ejemplo: `500 unidades`

## FULL_LOT
Se selecciona un `lot_id`.

La cantidad final se determina dentro de PostgreSQL.

No confiar en la cantidad que vio React.

## ALL_AVAILABLE
Solicitar todo lo disponible de una categoría o selección.

No hacer:

`quantity = availableFromUI`

Hacer:

`mode = ALL_AVAILABLE`

y resolver la cantidad real dentro de la transacción.

---

# 11. NEED OPCIONAL

La solicitud debe funcionar con:
- `need_case_id = null`
- `need_item_id = null`

cuando sea una operación puramente logística.

Si existe una necesidad, puede relacionarse.

No debe controlar la disponibilidad del inventario.

---

# 12. DISPONIBILIDAD CROSS-ORGANIZATION

Crear o reutilizar una proyección segura.

Puede exponer:
- centro;
- categoría;
- unidad;
- disponible;
- capacidad de despacho;
- cadena de frío cuando aplique;
- timestamp de actualización.

No debe exponer:
- nombres privados;
- teléfonos;
- usuarios;
- donantes;
- evidencias privadas;
- auditoría privada;
- hashes;
- metadata sensible;
- dirección privada.

---

# 13. AUTORIZACIÓN

La persona que solicita no debe autoaprobarse por defecto.

Flujo:

SOLICITAR
→ REVISAR
→ AUTORIZAR
→ RESERVAR
→ PREPARAR
→ DESPACHAR

Debe permitirse autorización parcial.

Ejemplo:

Solicitado: 500  
Autorizado: 350

Registrar:
- actor;
- fecha;
- cantidad;
- nota;
- razón cuando corresponda.

---

# 14. RESERVA Y CONCURRENCIA

Reutiliza:
- `allocations`;
- `reserve_lot_quantity`;
- `stock_movements`;
- Kardex;
- idempotencia;
- locks.

Si una línea consume varios lotes:
- selecciona de forma determinística;
- lockea correctamente;
- reserva sin sobreventa;
- conserva trazabilidad lote → solicitud → despacho.

## Hard test
Disponible: 100

Operación A intenta reservar 70.

Operación B intenta reservar 70 simultáneamente.

Nunca pueden quedar 140 reservadas.

---

# 15. REGLA DEL INVENTARIO

El Kardex es la fuente de verdad.

Nunca permitir edición directa del stock.

Toda variación material se representa mediante movimiento.

Usa los tipos reales existentes.

No inventes duplicados si ya están modelados.

---

# 16. UX OPERACIONAL PRINCIPAL

La consola debe responder primero:

# ¿QUÉ NECESITAS HACER?

## SOLICITAR
Necesito mercancía.

## RECIBIR
Está llegando mercancía.

## DESPACHAR
Tengo mercancía que debe salir.

Después:
- Inventario
- Solicitudes
- Preparación
- En tránsito
- Evidencias
- Historial
- Novedades

No conviertas la operación en un menú administrativo denso.

---

# 17. UX — REGLAS DE VELOCIDAD HUMANA

Diseña para emergencia.

## Solicitar
Máximo 4–5 decisiones principales.

centro proveedor
→ productos
→ cantidad/lote/todo
→ destino
→ justificar
→ revisar
→ enviar

## Recibir
código
→ cantidades
→ evidencia
→ confirmar

## Despachar
solicitud
→ revisar
→ picking
→ transporte
→ evidencia
→ salir

## Principios
- un CTA primario por vista;
- máximo dos niveles visuales principales;
- no más de seis acciones simultáneas;
- móvil primero;
- tablas solo cuando realmente comparan datos;
- no usar tabla como interfaz principal de campo;
- no usar modales enormes;
- información crítica visible sin scroll cuando sea razonable.

---

# 18. UX — LENGUAJE

No mostrar jerga técnica al operador.

Preferir:
- Solicitud;
- Reserva;
- Lote;
- Preparación;
- Despacho;
- En tránsito;
- Recepción;
- Evidencia;
- Novedad.

---

# 19. SUPER ADMIN — CICLO COMPLETO DE USUARIOS

SUPER_ADMIN debe poder:
- crear/invitar usuario;
- activar;
- suspender;
- reactivar;
- revocar;
- asignar organización;
- asignar uno o varios centros;
- asignar rol;
- asignar capacidades;
- consultar actividad relevante.

## Alta segura
Usar server-side:
- Server Action;
- Route Handler privado;
- o mecanismo equivalente.

Supabase Admin jamás desde `"use client"`.

No exponer `service_role`.

---

# 20. ALTA DE USUARIO — CONSISTENCIA

El flujo debe intentar completar:

1. `auth.users`;
2. profile;
3. membership;
4. `membership_locations`;
5. capabilities;
6. auditoría.

Si `auth.users` no puede participar en la misma transacción PostgreSQL:
- diseñar compensación;
- evitar cuentas huérfanas;
- dejar estado recuperable;
- registrar el fallo.

---

# 21. ALCANCE POR CENTRO

La infraestructura `membership_locations` ya existe.

Terminar su UX.

Ejemplo:

CENTROS AUTORIZADOS

☑ Centro A  
☑ Centro B  
☐ Centro C

Conservar la semántica existente.

Si cero filas significa `todas las bodegas de la organización`, no cambiarla silenciosamente.

Explicarlo en UI.

---

# 22. CAPABILITIES

No crear un rol por combinación.

Mantener roles actuales como agrupadores.

Agregar una capa de capacidades cuando haga falta.

Ejemplos conceptuales:
- `stock.request`
- `stock.review_request`
- `stock.authorize`
- `stock.receive`
- `stock.reserve`
- `stock.prepare`
- `stock.dispatch`
- `stock.confirm_destination`
- `evidence.upload`
- `evidence.review`
- `evidence.publish`
- `center.manage`
- `users.manage`
- `audit.view`

Los strings finales deben seguir convenciones reales del proyecto.

La base debe hacer cumplir las capacidades críticas.

Ocultar un botón en React no es seguridad.

---

# 23. EVIDENCIA FOTOGRÁFICA OPERACIONAL

Ya existe infraestructura `evidence`.

Reutilízala.

No crear otro bucket ni otro motor.

Extender evidencia a:
- aporte;
- recepción;
- clasificación cuando aplique;
- almacenamiento opcional;
- picking;
- preparación;
- despacho;
- incidente;
- recepción destino;
- entrega final.

---

# 24. EVIDENCIA — MOBILE FIRST

En móvil priorizar:

**TOMAR FOTO**

y como alternativa:

**ELEGIR DE GALERÍA**

Usar cuando sea compatible:

```html
accept="image/*"
capture="environment"
```

Mantener:
- validación MIME;
- límites;
- hash;
- bucket privado;
- rutas generadas de forma segura;
- RLS.

---

# 25. EVIDENCIA ≠ VERIFICACIÓN

Subir una foto no valida automáticamente una operación.

Separar:
- evidencia cargada;
- operación confirmada;
- evidencia revisada;
- evidencia aprobada para publicación.

Privada por defecto.

---

# 26. EVIDENCIA PÚBLICA

Solo publicar mediante una acción explícita y autorizada.

No publicar automáticamente:
- documentos;
- teléfonos;
- identificaciones;
- información privada;
- rostros sensibles;
- menores;
- contenido que comprometa seguridad;
- direcciones sensibles.

---

# 27. RECIBIR

Al recibir un despacho mostrar:
- origen;
- código;
- esperado;
- recibido;
- faltante;
- daño/rechazo;
- evidencia.

Ejemplo:

Esperado: 500  
Recibido: 498  
Faltante: 2  
Dañado: 0

El inventario destino solo aumenta por lo realmente recibido.

---

# 28. DESPACHAR

Flujo objetivo:

Solicitud autorizada
→ reserva
→ picking
→ evidencia
→ transporte
→ despacho

Mantener las reglas actuales de transporte.

No permitir una salida si faltan datos obligatorios que hoy ya forman parte del contrato.

---

# 29. NOVEDADES

Permitir registrar:
- faltante;
- daño;
- rechazo;
- retraso;
- incidente;
- problema de transporte;
- observación.

Cada novedad debe tener:
- actor;
- fecha servidor;
- referencia operacional;
- evidencia opcional.

Las correcciones importantes deben ser compensatorias.

No borrar historia.

---

# 30. TRACKING VISUAL

El seguimiento debe contar una historia.

Ejemplo:

✓ Solicitud creada  
✓ Autorizada  
✓ Reservada  
✓ Preparada  
📷 evidencia  
✓ Despachada  
🚚 transporte  
📷 evidencia  
● En tránsito  
○ Recepción destino  
○ Entrega

No inventar eventos.

Usar solamente información derivable del sistema.

---

# 31. MAPA

Reutilizar la proyección logística existente.

Mostrar cuando sea seguro:

Centro origen
→ movimiento
→ Centro destino

No publicar dirección privada.

No publicar coordenadas no autorizadas.

---

# 32. FRONT PÚBLICO

No rehacer la portada desde cero.

Elevar la base actual.

Prioridades:

## AYUDA EN MOVIMIENTO
Mostrar operaciones publicables.

## EVIDENCIA VERIFICADA
Galería editorial con evidencia aprobada.

## IMPACTO
Diferenciar:
- prometido;
- recibido;
- disponible;
- reservado;
- en tránsito;
- entregado.

Una promesa no cuenta como impacto.

---

# 33. CALIDAD VISUAL

La interfaz debe sentirse:
- humana;
- institucional;
- moderna;
- tecnológica;
- confiable;
- sobria;
- rápida.

Evitar:
- look genérico de IA;
- gradientes exagerados;
- glassmorphism innecesario;
- exceso de tarjetas;
- dashboards saturados;
- sombras decorativas sin función;
- iconos incongruentes;
- textos técnicos.

Seguir `docs/ai/DESIGN_QUALITY.md`.

---

# 34. RESPONSIVE

Validar como mínimo:
- 390 px;
- 430 px;
- 768 px;
- 1024 px;
- 1440 px.

Sin overflow horizontal.

Las acciones principales deben funcionar con una mano en móvil cuando sea razonable.

---

# 35. ESTADOS DE UI

Toda superficie importante debe contemplar:
- loading;
- empty;
- error;
- success;
- offline;
- permission denied;
- conflict;
- stale data;
- no results;
- partial;
- syncing;
- retry.

No dejar botones sin feedback.

---

# 36. OFFLINE

No romper la cola offline existente.

No guardar PII innecesaria en localStorage.

Nunca mostrar evidencia como sincronizada si el archivo no llegó al Storage.

---

# 37. RLS — HARD GATE

Crear pruebas explícitas.

## Usuario Centro A
Puede:
- ver disponibilidad compartida permitida;
- crear solicitud;
- leer su solicitud.

No puede:
- leer PII Centro B;
- leer evidencia privada ajena;
- operar inventario fuera de alcance;
- administrar usuarios ajenos.

## Operador Centro B
Puede:
- revisar solicitudes dirigidas a su centro;
- autorizar según capacidades;
- preparar;
- despachar.

No puede:
- alterar centros sin scope.

## SUPER_ADMIN
Tiene alcance global.

No bypass.

## ANON
Solo proyecciones públicas explícitas.

---

# 38. TEST CROSS-ORGANIZATION

Escenario obligatorio:

Organización Roja  
Centro Bogotá

Organización Azul  
Centro Manizales

Roja puede consultar disponibilidad segura de Azul.

Roja crea solicitud a Azul.

Roja NO puede leer:
- usuarios;
- contactos;
- evidencia privada;
- auditoría privada;
- donantes privados.

Azul recibe la solicitud porque está dirigida a su centro.

---

# 39. E2E OBLIGATORIOS

## Caso 1 — multi-item
Una sola solicitud:
- 500 aguas;
- 100 mercados.

## Caso 2 — autorización parcial
Solicitado: 500  
Autorizado: 350

## Caso 3 — ALL_AVAILABLE
Cambiar stock entre lectura y ejecución.

Servidor usa disponibilidad real.

## Caso 4 — FULL_LOT
Servidor calcula disponible real del lote.

## Caso 5 — concurrencia
100 disponibles.

Dos reservas concurrentes de 70.

Nunca >100.

## Caso 6 — evidencia recepción
Foto privada y vinculada correctamente.

## Caso 7 — evidencia despacho
Foto aparece en el tracking permitido.

## Caso 8 — usuario limitado
Solicitar: sí  
Recibir: sí  
Despachar: no

RPC debe negar despacho.

## Caso 9 — scope
Usuario Centro A no opera Centro B.

## Caso 10 — need opcional
Solicitud sin necesidad llega hasta recepción.

---

# 40. DEMO FINAL

Preparar con RPC reales:

## Bogotá
- Agua: 1000
- Mercados: 300
- Cobijas: 120

## Manizales solicita
- Agua: 500
- Mercados: 100
- Cobijas: ALL_AVAILABLE

## Bogotá autoriza
- Agua: 450
- Mercados: 100
- Cobijas: 120

## Preparación
- picking;
- evidencia.

## Despacho
- transporte;
- evidencia.

## Manizales recibe
- Agua: 448
- Mercados: 100
- Cobijas: 118

Registrar:
- faltante agua: 2;
- faltante cobijas: 2;
- evidencia.

El inventario destino debe reflejar únicamente lo recibido.

El tracking debe reconstruir toda la cadena.

---

# 41. PRUEBAS — EMBUDO DE VELOCIDAD

No ejecutes `npm run verify` después de cada cambio mínimo.

Usa este embudo:

## Cambio TypeScript
typecheck dirigido

## Cambio función
unit test correspondiente

## Cambio SQL
pgTAP dirigido

## Cambio RLS
RLS dirigido

## Cambio UI
Playwright dirigido

## Delta terminado
`npm run verify`

Si falla:
corrige la causa.

No relajes el test.

---

# 42. HARD GATES FINALES

Antes de cerrar el ciclo deben quedar verdes:
- lint;
- typecheck;
- unit;
- pgTAP;
- RLS;
- concurrencia;
- build;
- Playwright;
- accessibility;
- visual audit;
- `npm run verify`.

Usar números reales.

No inventar resultados.

---

# 43. MIGRACIONES

Nunca editar migraciones ya aplicadas.

Toda evolución:

nueva migración append-only.

Verificar:
- clean reset;
- upgrade incremental;
- grants;
- signatures;
- RLS;
- indexes.

---

# 44. SEGURIDAD ADMIN

No usar `service_role` en cliente.

No conceder SUPER_ADMIN desde la UI común.

No permitir autoescalamiento.

No ampliar scope desde DevTools.

No confiar únicamente en UI.

Toda acción crítica debe validarse en servidor/base.

---

# 45. PRIVACIDAD

Separar:

## Público
- centro;
- zona;
- código;
- estado;
- cifras conciliadas;
- evidencia aprobada.

## Operacional
- inventario;
- solicitudes;
- transporte;
- reservas.

## Privado
- contacto;
- identificación;
- donante;
- dirección sensible;
- evidencia pendiente;
- hashes;
- PII.

No mezclar capas.

---

# 46. PERFORMANCE

Evitar N+1.

Crear índices solo para patrones de consulta reales.

Revisar especialmente:
- solicitudes por estado;
- origen;
- destino;
- items;
- lotes;
- evidencias;
- timestamps.

No optimizar a ciegas.

---

# 47. LOOP DE IMPLEMENTACIÓN

Para cada delta:

## INSPECT
Lee únicamente el contrato relacionado.

## MINIMAL PLAN
Define el cambio mínimo.

## IMPLEMENT
Haz el diff más pequeño razonable.

## DIRECT TEST
Ejecuta prueba específica.

## REPAIR
Corrige.

## ADVERSARIAL CHECK
Intenta romper seguridad/integridad.

## REGRESSION
Escala las pruebas.

## DOCUMENT
Actualiza estado.

## NEXT
Continúa.

Formato:

**INSPECT → PLAN → IMPLEMENT → TEST → REPAIR → ATTACK → REGRESSION → DOCUMENT → NEXT**

---

# 48. ORDEN RECOMENDADO

## Fase A
Solicitud multi-item + cross-organization.

## Fase B
Reserva:
- exact;
- full lot;
- all available.

## Fase C
UX SOLICITAR.

## Fase D
Evidencia operacional.

## Fase E
UX RECIBIR.

## Fase F
UX DESPACHAR.

## Fase G
Alta de usuarios y scope.

## Fase H
Capabilities.

## Fase I
Tracking + mapa.

## Fase J
Front público.

## Fase K
Reportes.

## Fase L
Hardening.

Puedes cambiar el orden solo si una dependencia real lo exige.

Documenta el motivo.

---

# 49. NO HACER

No:
- duplicar motores;
- quitar RLS;
- suavizar tests;
- escribir stock directo;
- hacer todo dependiente de necesidades;
- crear roles por combinación;
- publicar PII;
- modificar migraciones aplicadas;
- meter service role en cliente;
- inventar métricas;
- hacer refactors cosméticos masivos antes de cerrar P0;
- desplegar automáticamente a producción sin instrucción explícita.

---

# 50. ACTUALIZACIÓN DE MEMORIA

Después de cada delta importante actualiza:
- `docs/ai/STATE.md`;
- `docs/ai/QUALITY.md` cuando corresponda;
- `docs/ai/DESIGN_QUALITY.md` si cambia UX;
- `docs/GAP_LEDGER.md` si existe;
- ADR solo para decisiones arquitectónicas importantes.

`STATE.md` debe contener arriba:
- gate actual;
- último resultado verde;
- qué se cerró;
- qué está abierto;
- siguiente acción exacta;
- bloqueos reales.

No convertirlo en una bitácora infinita.

---

# 51. FORMATO DE RESPUESTA DEL AGENTE

Después de cada delta responde solamente:

## IMPLEMENTADO

## MIGRACIONES

## ARCHIVOS

## SEGURIDAD

## TESTS

## HALLAZGOS

## PENDIENTES

## SIGUIENTE DELTA

Máximo detalle donde haya riesgo.

Mínimo texto narrativo.

---

# 52. DEFINICIÓN GLOBAL DE TERMINADO

No está terminado porque compile.

Está terminado cuando:
- un centro puede solicitar a otro;
- puede ser otra organización autorizada;
- solicitud multiproducto funciona;
- exact quantity funciona;
- FULL_LOT funciona;
- ALL_AVAILABLE funciona;
- servidor calcula disponibilidad;
- no hay sobreventa;
- need es opcional;
- autorización parcial funciona;
- reserva queda en ledger;
- picking funciona;
- evidencia funciona;
- transporte funciona;
- despacho funciona;
- recepción parcial funciona;
- faltantes/daños quedan conciliados;
- inventario destino coincide con recibido;
- tracking reconstruye la historia;
- mapas respetan privacidad;
- SUPER_ADMIN puede crear usuarios;
- scope por centro funciona;
- capabilities se validan en servidor;
- RLS cross-organization no filtra PII;
- anon no accede a operación privada;
- experiencia móvil es utilizable;
- pruebas quedan verdes;
- documentación queda actualizada.

---

# 53. DIRECTIVA DE ARRANQUE

Empieza ahora.

Primero:

1. lee `docs/ai/STATE.md`;
2. revisa `git status`;
3. revisa últimos commits;
4. identifica qué partes de este documento ya están implementadas;
5. marca internamente:
   - EXISTE;
   - EXTENDER;
   - CREAR;
   - RIESGO;
6. selecciona el primer P0 real;
7. implementa.

No me pidas aprobar el análisis.

No reconstruyas.

No rediscutas decisiones que el repo ya resolvió.

No pares por decisiones reversibles.

Solo detente ante un bloqueo externo real o una decisión irreversible que no pueda inferirse de la arquitectura existente.

La meta es:

> **SOLICITAR → RESERVAR → PREPARAR → EVIDENCIAR → DESPACHAR → TRANSPORTAR → RECIBIR → EVIDENCIAR → CONCILIAR → AUDITAR → MOSTRAR DE FORMA SEGURA.**
