# Calidad activa

| Frente | Nivel | Evidencia / siguiente prueba |
|---|---:|---|
| Gobernanza y multi-evento | 3 | Esquema tenant/evento, fuentes y memoria durable |
| Identidad y permisos | 3 | Auth local + RLS/IDOR/escalamiento probado |
| Necesidades | 3 | reporte → verificación → proyección pública |
| Especie e inventario | 3 | E2E A/F/G/H, locks, hold y libro append-only |
| Dinero sandbox | 3 | COP 1 M → gasto COP 300 k → saldo COP 700 k |
| Transparencia | 3 | proyecciones y fórmulas reconciliadas |
| Privacidad/seguridad/auditoría | 3 | moderación, RLS y eventos inmutables probados |
| Offline/resiliencia | 2 | cola mínima sin PII + idempotencia DB; cifrado/dispositivo pendiente |
| Accesibilidad/responsive | 3 | semántica/teclado y QA 320–1440 sin overflow |

No se recomienda piloto ni producción: offline endurecido, escaneo real, observabilidad, backup/restore y decisiones humanas siguen pendientes.
