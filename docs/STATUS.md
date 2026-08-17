# Estado comprobado

Fecha: 2026-08-16 · Puerta: G1 sandbox publicado para demostración interna exclusivamente sintética; G2 bloqueada por `G-021` y por verificar en remoto el cierre local de `G-022`.

Supabase y Next.js locales están activos con datos 100 % sintéticos. La base se reconstruye con 17 migraciones. Pasan 152 pruebas SQL, RLS, concurrencia real, 33 unitarias y 28 Playwright en navegador y móvil; lint, TypeScript y build están verdes. La salud HTTP entrega request ID, duración y estado de base; las exportaciones registran telemetría estructurada sin PII.

Administración dispone de `/operaciones/centros` para crear y editar puntos de entrega: organización responsable, nombre, zona pública, dirección exacta privada, instrucciones seguras, coordenada aproximada, cadena de frío, disponibilidad y categorías aceptadas. Cada escritura usa una RPC transaccional idempotente, versiona reglas y genera auditoría append-only; desactivar reemplaza eliminar.

El aliado ya no recibe una lista transversal: `organization_delivery_points` filtra los puntos activos por membresía y organización, preserva la herencia de reglas generales y muestra las instrucciones parametrizadas. `submit_donation_intake_v2` vuelve a comprobar que el punto esté activo y pertenezca al mismo evento/tenant. Así `G-022` queda cerrado localmente; el remoto todavía conserva el contrato previo.

El registro de aportes consume ocho catálogos autoritativos versionados: tipos de donante, sectores, categorías detalladas, estados declarados, cobertura inicial, departamentos, unidades y 22 aliados de referencia. El selector de referencia solo resume el aporte: la organización autorizada sigue derivándose de una membresía activa en una organización verificada. El flujo admite hasta tres fotografías JPG/PNG privadas por `APO-*`, con ruta de servidor, hash, límite de 5 MB y confirmación de almacenamiento; permanecen pendientes de revisión y no crean recepción, entrega ni impacto.

Las solicitudes ahora se presentan como fichas de decisión: distinguen necesidad ciudadana de aporte reportado, muestran un resumen en lenguaje natural, código, cantidad, centro, aliado relacionado, fotos privadas, fecha y siguiente control. La confirmación del aporte explica expresamente que crea una solicitud de verificación, no una solicitud de ayuda, recibo o constancia de entrega.

La entrada ciudadana conserva moderación y honeypot, y ahora limita cinco reportes exitosos por origen/evento cada diez minutos mediante un hash SHA-256 sin IP en claro. Auth bloquea el auto-registro, exige 12 caracteres con mayúsculas, minúsculas, dígitos y símbolo, requiere reautenticación para cambiar contraseña y limita sesiones a 12 h/2 h de inactividad.

La recuperación local fue ejecutada: snapshot de esquema/datos, manifiesto con checksums, reconstrucción desde migraciones, restauración y 94 pgTAP. RTO observado: 57,1 segundos. El procedimiento y sus límites están en `docs/OPERATIONAL_READINESS.md`.

La bodega ofrece búsqueda, etapas, compatibilidad categoría/unidad y cola offline con validación estricta, TTL 72 h, máximo 50 y cero PII. CI y runbooks de incidente, datos, WAF y aprobación están versionados. La ejecución CI `31958813505` fue verde sobre `main`.

Local: aplicación `http://127.0.0.1:3000`, Studio `http://127.0.0.1:55323`, Mailpit `http://127.0.0.1:55324`.

Control de entorno: la suite funcional local está verde, pero `npm run preflight:local` bloquea porque permanecen `.vercel/project.json` y `supabase/.temp/project-ref` de la configuración remota previa. No se retiraron automáticamente para no alterar enlaces del usuario. Antes de tratar el workspace como sandbox aislado hay que desvincular ambos de forma explícita.

Remoto autorizado: `https://unidos-nos-cuidamos.vercel.app` sirve `NEXT_PUBLIC_APP_ENV=sandbox` desde el despliegue Vercel `dpl_6isVPmpj83EKqKFX6DPRpjUpLVqM`, estado `READY`. `/api/health` responde `ok` con PostgreSQL conectado; CSP está presente; `/reportar` encuentra el evento activo y `/ingresar` ya no publica correos ni el bloque de cuentas de práctica. Supabase `vcgwfyhytzgyzicfbikf` registra las 15 migraciones, dos organizaciones y centros totalmente sintéticos, reglas de aceptación por centro, un fondo sin movimientos reales y cinco identidades iniciales con 12 membresías separadas. Los cinco inicios de sesión y sus roles fueron comprobados con la clave pública; la clave administrativa nunca se incorporó al frontend ni a Vercel.

La simulación integral remota `SIM-20260816195948-9f2d8d2b` pasó 38/38 controles: reporte/verificación, aporte en especie, QR, recepción, lote, asignación, despacho, entrega, conciliación monetaria, segregación de gasto, transparencia, salud, Excel, idempotencia y auditoría. Produjo 46 eventos append-only y confirmó que las denegaciones de autoaprobación funcionan. El detalle reproducible está en `docs/REMOTE_FLOW_SIMULATION_2026-08-16.md`.

La misma simulación abrió dos brechas P0. `G-022` ya cuenta con corrección y pruebas locales; `G-021` continúa abierto porque un `partner_reporter` puede leer ubicación/contacto privados de necesidades. También quedan pendientes continuidad del QR, coordenadas para despachos reales, contexto/correlación de auditoría y actualización de cortes (`G-023` a `G-027`). Por tanto, el sandbox sirve para corregir y demostrar internamente con datos sintéticos, no para incorporar operadores, PII o actividad real.

Bloqueos: G2/G3 requieren operador jurídico, autoridades/organizaciones, DPIA y políticas aprobadas, proveedor financiero, WAF/monitoreo externo, backups remotos/PITR, protección HIBP, marcas y aprobación explícita del piloto. Este despliegue técnico sigue limitado a datos sintéticos: no autoriza recaudo, PII ni uso institucional.

Siguiente: cerrar `G-021`; después, con autorización explícita, aplicar las migraciones locales pendientes y repetir la simulación remota para confirmar `G-022`. Rotar las credenciales expuestas durante el diagnóstico. No entregar accesos a nuevos operadores ni introducir PII hasta que la matriz IDOR y el aislamiento usuario-organización-punto sean verdes también en remoto. Mantener Supabase remoto exclusivamente sintético hasta cerrar G2 y completar/firmar `docs/PILOT_APPROVAL_PACKET.md`.
