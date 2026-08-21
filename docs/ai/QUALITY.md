# Calidad activa

| Frente | Nivel | Evidencia / siguiente prueba |
|---|---:|---|
| Gobernanza y multi-evento | 3 | Esquema tenant/evento, fuentes y memoria durable |
| Identidad y permisos | 3 | Auth local + RLS/IDOR/escalamiento probado |
| Necesidades | 3 | reporte → verificación → proyección pública |
| Especie e inventario | 3 | E2E A/F/G/H, locks, hold y libro append-only; solicitud multiproducto entre organizaciones con los tres modos, sin sobreventa bajo autorizaciones simultáneas y con recepción producto a producto |
| Dinero sandbox | 3 | COP 1 M → gasto COP 300 k → saldo COP 700 k; y recaudo por pasarela: cobro confirmado por el proveedor que no es saldo hasta que tesorería lo concilia contra el extracto. Sin proveedor real conectado (G-054) |
| Transparencia | 3 | proyecciones y fórmulas reconciliadas |
| Privacidad/seguridad/auditoría | 3 | moderación, RLS y eventos inmutables probados |
| Offline/resiliencia | 3 | contrato runtime estricto, TTL 72 h, máximo 50, sin PII, idempotencia DB; política de dispositivo pendiente para G2 |
| Accesibilidad/responsive | 3 | semántica/teclado y QA 320–1440 sin overflow |

No se recomienda piloto ni producción: evidencia/antimalware, infraestructura remota, decisiones humanas y validaciones jurídica/contable/humanitaria siguen pendientes. Observabilidad y backup/restore ya están probados en local, no en un entorno autorizado.
