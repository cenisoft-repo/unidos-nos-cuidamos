# Registro de riesgos

| ID | Riesgo | Control de sandbox | Evidencia esperada |
|---|---|---|---|
| R-001 | Exposición de PII/ubicación | Modelo privado + proyección pública explícita + RLS | E2E C/H e IDOR |
| R-002 | Publicación o dinero no verificado | Estados separados; vista solo conciliada | E2E B/H |
| R-003 | Inventario negativo/doble | Locks, idempotencia y movimientos append-only | E2E A/D/G |
| R-004 | Autoaprobación de gasto | Segregación por actor y RPC | E2E B negativo |
| R-005 | Bien peligroso/cadena de frío | Reglas versionadas, hold/recall | E2E F |
| R-006 | Suplantación/tenant cruzado | Membresía derivada de Auth y RLS | SQL IDOR/roles |
| R-007 | Caída, bloqueo o costo inesperado del proveedor cartográfico | Endpoints configurables, fallback dual, atribución visible, sin precarga y sin clave propietaria en sandbox | E2E MapLibre/Leaflet + revisión de política antes de G2 |
| R-008 | Seguimiento logístico revele rutas/personas | Proyección origen-destino aproximada; sin GPS, dirección, transportador o custodio | RLS + E2E de proyección + DPIA bloqueante para GPS |
| R-009 | Un miembro no asignado consulta PII de una necesidad | Bloqueo de datos reales; corrección RLS `G-021` obligatoria | Matriz IDOR remota por rol y columnas privadas |
| R-010 | Punto de otro tenant crea un aporte imposible de recibir | Cerrado local: consulta por organización + validación transaccional + reglas versionadas; remoto sigue sintético hasta desplegar `G-022` | 152 SQL y Playwright UI/RPC prueban organización-punto; repetir IDOR remoto |
| R-011 | El QR informa un estado obsoleto y erosiona confianza | El código sigue siendo consultable; `G-023` pendiente | Recorrido único APO → DON → entrega/conciliación |
| R-012 | Auditoría huérfana o no correlacionada impide investigar una operación | Historial inmutable presente; `G-025/G-026` pendientes | Evento/organización/correlación común por transacción |
| R-013 | El tablero mezcla filas actuales con cortes de métricas antiguos | Fecha y fórmula visibles; `G-027` pendiente | Nuevo snapshot tras cierre y prueba de corte |
