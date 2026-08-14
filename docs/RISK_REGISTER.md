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
