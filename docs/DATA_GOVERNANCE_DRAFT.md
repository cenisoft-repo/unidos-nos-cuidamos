# Gobierno y retención de datos · borrador para aprobación

Estado: implementable en sandbox, no aprobado para datos reales. El responsable del tratamiento, la base jurídica, los encargados, transferencias y plazos definitivos deben ser validados antes de G2.

## Principios operacionales

- Minimización por defecto: solo el dato necesario para verificar, custodiar, conciliar o atender un derecho.
- Separación: contacto, dirección, custodia, evidencia y referencia financiera nunca alimentan directamente una superficie pública.
- Precisión proporcional: el público recibe zona aproximada; la operación autorizada conserva el mínimo preciso necesario.
- Trazabilidad: las acciones críticas son append-only; una corrección compensa, no reescribe la historia.
- Datos sintéticos: desarrollo, CI, demostraciones y recuperación usan exclusivamente fixtures ficticios.

## Matriz de decisión pendiente

| Clase | Sandbox actual | Decisión obligatoria antes de G2 | Método de cierre |
|---|---|---|---|
| Identidad/contacto/dirección exacta | restringida por RLS; 30 días tras cierre simulado | finalidad, autorización/base, plazo y canal de derechos | acta jurídica + prueba de retiro/rectificación |
| Evidencia | bucket privado, 5 MiB, JPEG/PNG/PDF; UI deshabilitada | consentimiento, escaneo antimalware, metadatos, cifrado y retención | prueba de archivo seguro + eliminación aprobada |
| Finanzas | referencias privadas y cifras públicas conciliadas | operador, AML/KYB, contabilidad, reversos y certificados | contrato + staging del proveedor |
| Ubicación/logística | proyección aproximada | precisión por rol, GPS, custodios y retención | DPIA y prueba de no filtración |
| Auditoría | confidencial append-only | plazo legal, acceso y archivo | política firmada + restauración |
| Telemetría | operación, estado, duración y request ID sin cuerpos | proveedor, residencia, acceso, retención y alertas | configuración revisada + simulacro |

## Derechos y eliminación

El código de seguimiento permite localizar un caso sin publicar identidad. Una solicitud de consulta, corrección o retiro debe verificar legitimidad por un canal aprobado y crear evento auditable. Los datos operacionales corregibles se compensan; la PII que deba eliminarse se anonimiza o elimina conforme a política sin falsificar los eventos críticos. El diseño de esa rutina queda bloqueado hasta definir plazo y excepción legal aplicables.

## Propiedad requerida

Completar antes de piloto: responsable del tratamiento, oficial/encargado de privacidad, custodio de evidencias, administrador de acceso, dueño de retención, contacto de incidentes y fecha de próxima revisión. La plantilla de decisión está en `docs/PILOT_APPROVAL_PACKET.md`.
