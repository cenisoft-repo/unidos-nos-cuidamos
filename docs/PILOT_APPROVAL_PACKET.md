# Paquete de decisión para piloto G2

La ingeniería local está agotada hasta G1. Este paquete convierte cada bloqueo externo en una decisión verificable. Marcar una casilla exige adjuntar evidencia; el texto no constituye aprobación por sí mismo.

| Puerta | Responsable nominal | Decisión/evidencia | Estado |
|---|---|---|---|
| Operador y autoridad | Por asignar | entidad operadora, alcance territorial, RACI, turnos y SLA firmados | Bloqueado |
| Bienes y ayuda humanitaria | Por asignar | catálogo, rechazo, cadena de frío, retiro y escalamiento aprobados | Bloqueado |
| Privacidad | Por asignar | DPIA, responsable/encargados, avisos, derechos, retención e incidentes | Bloqueado |
| Migración | Por asignar | snapshot autorizado, clasificación PII, checksum, muestra, corte y rollback | Bloqueado |
| Finanzas | Por asignar | proveedor, fondo, KYB/AML, conciliación, reversos, contabilidad y certificados | Bloqueado |
| Identidad y marca | Por asignar | padrón de aliados, dominios, marcas, fuentes y vocerías | Bloqueado |
| Infraestructura | Por asignar | proyectos Supabase/Vercel, regiones, presupuesto, secretos, HIBP, WAF y observabilidad | Bloqueado |
| Continuidad | Por asignar | backups/PITR, cifrado, copia externa, RPO/RTO, guardias y simulacro staging | Bloqueado |
| Evidencias | Por asignar | consentimiento, escaneo antimalware, formatos, retención y acceso | Bloqueado |
| Salida | Por asignar | preview validado, capacitación, rollback y autorización expresa de G2 | Bloqueado |

## Evidencia técnica ya disponible

- Suite local integral: SQL, RLS, concurrencia, unitarias, build y navegador.
- Backup/restauración sintética con SHA-256 y RTO medido.
- Matriz público/privado, dashboards, Excel, mapas y seguimiento sin PII.
- Preflight local y preflight remoto de solo lectura.
- Runbooks: continuidad en `docs/OPERATIONAL_READINESS.md`, incidentes en `docs/INCIDENT_RESPONSE_RUNBOOK.md`, WAF en `docs/WAF_ROLLOUT.md` y gobierno en `docs/DATA_GOVERNANCE_DRAFT.md`.

## Acta

Completar con nombre, cargo, entidad, fecha, alcance, versión aprobada, condiciones, vigencia y firma de cada responsable. Una aprobación parcial no habilita recaudo, PII, marcas, comunicaciones o despliegue fuera de su alcance expreso.
