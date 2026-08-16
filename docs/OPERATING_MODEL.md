# Modelo operativo sandbox

| Cola | Responsable de rol | SLA simulado | Escalamiento |
|---|---|---:|---|
| Riesgo vital/rescate | Verificador → autoridad | 15 min | No enviar voluntariado general |
| Triage de necesidad | Verificador | 2 h | Coordinador de evento |
| Intake de aliado | Verificador de aportes | 4 h | Coordinador de donaciones |
| Recepción/cuarentena | Operador de centro | Inmediato | Responsable sanitario/logístico |
| Conciliación financiera | Tesorería | 1 día | Responsable financiero |
| Privacidad/fraude | Auditor/privacidad | 4 h crítico | Responsable del tratamiento futuro |

Segregación: quien solicita un gasto no lo aprueba ni lo audita; quien recibe/ajusta stock deja evidencia y un segundo rol revisa diferencias.

## RACI nominal pendiente

Antes de activar G2, cada rol genérico debe tener nombre, entidad, suplente, turno, canal seguro y autoridad de decisión: responsable del evento, verificación humanitaria, centro/logística, tesorería, privacidad, seguridad, auditoría, soporte y vocería. La asignación se aprueba en `docs/PILOT_APPROVAL_PACKET.md`; el código no puede inventarla.

## Inicio y cierre de turno

1. Verificar salud, colas, incidentes, sincronización offline y conciliaciones.
2. Aceptar formalmente el relevo sin compartir credenciales.
3. Registrar decisiones, bloqueos y excepciones en eventos append-only.
4. Conciliar casos/stock/dinero abiertos antes de entregar turno.
5. Escalar cualquier P0/P1 conforme a `docs/INCIDENT_RESPONSE_RUNBOOK.md`.

Las cuentas sandbox son personales ficticias por rol; en piloto se prohíben cuentas compartidas y se exige revocación al terminar la vinculación.
