# Simulación integral del flujo remoto · 2026-08-16

## Resultado

Se ejecutó el recorrido completo contra `https://unidos-nos-cuidamos.vercel.app` y Supabase `vcgwfyhytzgyzicfbikf`, exclusivamente con identidades y datos sintéticos. La corrida final `SIM-20260816195948-9f2d8d2b` terminó como `completed_with_critical_findings`: **38/38 controles funcionales pasaron** y se documentaron ocho hallazgos de seguridad, continuidad y observabilidad.

La simulación no usó `service_role` para aprobar artificialmente el flujo. Cada mutación se hizo con la sesión correspondiente: aliado, administración/verificación, bodega/logística, solicitante y aprobador de tesorería. La clave publicable se obtuvo de la configuración ya expuesta al cliente publicado; ninguna clave secreta ni contraseña se escribió en la evidencia.

## Recorridos comprobados

### Necesidad y aporte en especie

1. La interfaz pública creó el reporte `NEC-145A9767302ED370616EDEB1` por 10 litros.
2. `anon` no pudo consultar la tabla protegida.
3. Administración verificó y publicó la necesidad.
4. El aliado creó el intake `APO-17FC8225D1F23D9DC951CD91`; el ticket generó un QR SVG real de 5.782 caracteres de trazado hacia el seguimiento publicado.
5. El aliado no pudo autoaprobar su intake.
6. Administración lo aprobó y creó `DON-FFE9A38FAF1572F593AF5A70`.
7. Bodega recibió 10 litros, creó un lote, reservó existencias, creó `DSP-391A338B984760079580BC89` y registró la entrega.
8. Bodega no pudo validar su propia entrega; administración la validó.
9. La necesidad terminó `covered`, la proyección pública terminó `Cubierta` con 10/10 y el aporte en especie apareció en transparencia.
10. Los reintentos de recepción, asignación, despacho, entrega y validación devolvieron las mismas entidades sin duplicar efectos.

### Aporte económico y gasto

1. El aliado registró un aporte declarado de COP 500.000 usando los siete catálogos remotos vigentes.
2. El reintento del intake devolvió `was_duplicate=true` y el mismo identificador.
3. Administración aprobó el intake y tesorería concilió `DON-F18F96B3407A43C94EC35543` exactamente una vez.
4. El rol solicitante creó un gasto sintético por COP 125.000 y no pudo aprobarlo.
5. El rol aprobador lo aprobó y registró el débito; el reintento devolvió la misma transacción.
6. El aporte económico conciliado apareció en transparencia sin exponer los contactos privados.

### Superficies y controles adicionales

- Los cinco usuarios temporales iniciaron sesión y conservaron sus roles separados.
- Los dos centros públicos aparecen en el RPC del mapa.
- `/api/health` respondió HTTP 200 con PostgreSQL conectado.
- La exportación pública Excel respondió HTTP 200 y 14.394 bytes.
- La vista dinámica aumentó las unidades entregadas de 40 a 50 durante la corrida final.
- El tablero HTML no contenía los marcadores sintéticos usados en correo o ubicación privada.
- Se encontraron 46 eventos append-only para todas las tablas críticas esperadas y cinco actores distintos.

## Hallazgos

| ID | Severidad | Resultado observado | Corrección requerida |
|---|---|---|---|
| `G-021` / `NEED-PRIVATE-SCOPE` | Crítica | `partner_reporter` pudo leer `exact_address_private` y `contact_private` de una necesidad. `anon` sí fue rechazado. | Sustituir la política amplia de miembros del evento por una RPC/vista mínima y acceso explícito de verificadores o asignados. Añadir prueba IDOR por cada rol. |
| `G-022` / `CENTER-TENANT-UI` + `CENTER-TENANT-SERVER` | Crítica | La UI habilita centros de otra organización y `submit_donation_intake_v2` los acepta; luego `receive_donation` exige que donación y centro pertenezcan a la misma organización, dejando el aporte sin ruta posible. | Definir si el centro es exclusivo o compartido. Para el modelo actual, filtrar por organización y validar `center.organization_id = p_organization_id` dentro de la transacción. Incorporar asignación usuario-centro antes de datos reales. |
| `G-023` / `QR-TRACKING-CONTINUITY` | Alta | El QR `APO-*` siguió en `approved` después de que la donación `DON-*` y la entrega terminaron `validated`; el código operacional no se revela desde el QR. | Hacer que `track_public_code(APO-*)` derive el estado de la donación vinculada o devolver una transición pública segura al `DON-*`. |
| `G-024` / `MAP-DISPATCH-MISSING` | Alta | El despacho validado no apareció en el mapa: el reporte ciudadano publica texto de zona, pero no coordenadas aproximadas autorizadas. | Agregar geocodificación/selección territorial moderada y guardar solo coordenadas públicas con precisión permitida antes de publicar. |
| `G-025` / `AUDIT-TENANT-CONTEXT` | Alta | 14 eventos no tenían el par completo evento/organización. La organización nula del reporte ciudadano puede ser legítima, pero varias tablas hijas no llevan contexto propio y producen eventos sin evento, visibles bajo la excepción global de auditoría. | Derivar evento y organización desde la entidad padre en el trigger o en triggers específicos; endurecer la política para registros sin contexto. |
| `G-026` / `AUDIT-CORRELATION` | Media | Los 46 eventos tuvieron 46 identificadores de correlación distintos; una transacción multi-entidad no puede reconstruirse por un único correlation ID. | Propagar un ID por petición/RPC mediante contexto transaccional y reutilizarlo en auditoría y movimientos. |
| `G-027` / `METRIC-SNAPSHOT-STALE` | Media | Las filas/proyecciones públicas se actualizaron, pero no se creó un nuevo `public_metric_snapshot`; las tarjetas de corte conciliado permanecen antiguas. | Crear un proceso explícito de cierre/publicación de métricas y mostrar claramente el corte vigente. |

## Priorización

Antes de incorporar un nuevo operador o cualquier PII deben cerrarse `G-021` y `G-022`. Después conviene resolver en este orden: continuidad QR (`G-023`), contexto de auditoría (`G-025`), georreferenciación moderada (`G-024`) y finalmente correlación/cortes (`G-026` y `G-027`). G2 y cualquier piloto real permanecen bloqueados.

## Evidencia y reproducibilidad

- Arnés versionado: `scripts/simulate-sandbox-flow.mjs` (`npm run simulate:sandbox`).
- Evidencia JSON local, fuera del repositorio: `%LOCALAPPDATA%\RutaSolidaria\simulaciones\SIM-20260816195948-9f2d8d2b.json`.
- Captura del QR: `%LOCALAPPDATA%\RutaSolidaria\simulaciones\SIM-20260816195948-9f2d8d2b-qr.png`.

Cuatro ejecuciones preliminares completaron también las mutaciones sintéticas, pero su evidencia terminó `failed` por expectativas del arnés en `networkidle`, hidratación, traducción del estado y forma del JSON de salud. Conforme al historial append-only no se borraron: el sandbox conserva cinco recorridos completos de 10 litros, cinco aportes económicos/gastos y cinco intakes de centro cruzado rechazados compensatoriamente. Ninguno corresponde a una operación real.
