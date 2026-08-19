# Auditoría de consolidación · flujo donaciones → inventario → logística

Fecha: 2026-08-19 · Fase 1 del loop de consolidación · Base auditada: `main` en `e413b12`,
26 migraciones, 18 pantallas/componentes, 12 scripts operativos.

Esta fase **no agrega** pantallas, tablas ni servicios. Solo clasifica lo que existe y nombra
las duplicaciones que deben resolverse antes de implementar.

## 1. Clasificación por módulo

| Módulo | Qué existe hoy | Clasificación | Motivo |
|---|---|---|---|
| Necesidades | `need_cases`, `need_items`, `need_verifications`, `submit_need_report`, `review_need_case`, `public_need_projections`, `public_need_map` | **REUTILIZAR + REFACTORIZAR** | La entidad única ya existe y admite varios artículos. Le falta el eje comprometido/pendiente: `need_items` solo tiene `quantity_required` y `quantity_covered`, y `quantity_covered` se mueve únicamente al validar la entrega final. |
| Registro de usuarios | `auth.users` + `handle_new_user` + `memberships`; altas por `scripts/bootstrap-environment.mjs` y `scripts/provision-sandbox-access.mjs`; `auth.enable_signup = false` | **FUSIONAR + CREAR** | Hay **dos** caminos de alta administrativa (ver §2). No existe ningún camino de autorregistro con confirmación de correo. |
| Roles y permisos | `public.app_role` (8 roles), `memberships(user_id, organization_id, event_id, role, active)`, `has_any_role`, `has_event_role`, `is_org_member`, `is_event_member` | **REUTILIZAR + REFACTORIZAR** | El modelo es correcto y único. El alcance llega hasta organización+evento; no llega hasta la bodega concreta, que es lo que pide la Fase 7. |
| Donaciones | `submit_donation_intake_v2` (activa) sobre `submit_donation_intake` (interna), `donation_intakes`, `donation_intake_items`, `review_donation_intake`, `donations`, `donation_items` | **REUTILIZAR** | Un solo camino expuesto: la firma antigua ya está revocada para `authenticated` y solo se invoca desde la v2. No hay duplicación real, sí una capa de compatibilidad que conviene documentar. |
| Evidencias | `evidence`, `donation_intake_evidence`, `prepare_intake_photo_evidence`, `confirm_intake_photo_evidence`, bucket privado con RLS | **REUTILIZAR** | Sistema general de archivos ya existente, con hash, ruta de servidor y vínculo auditado. La Fase 5 exige explícitamente no crear un módulo de fotos aparte. |
| Puntos de acopio | `inventory_locations` + `accepts_donations`/`dispatches_shipments`, `manage_delivery_point`, `delivery_points_admin`, `organization_delivery_points`, `organization_dispatch_points`, `public_collection_centers` | **REUTILIZAR + REFACTORIZAR** | Punto de acopio y bodega ya son **la misma tabla** con propósito declarado: eso es exactamente lo que pide la Fase 7. Falta ordenar por proximidad a la ubicación del aliado (Fase 6). |
| Bodegas | Misma tabla `inventory_locations`; consola `/operaciones/bodega` | **MANTENER** | No existe una segunda estructura de bodega que fusionar. |
| Inventario | `inventory_lots`, `stock_movements` (append-only, inmutable), `inventory_counts` | **REFACTORIZAR** | El Kardex existe y es la fuente correcta, pero **nadie lo lee para presentar la posición**: la consola muestra `quantity_initial` (el saldo del día de la recepción) y la usa como tope de reserva. No hay ninguna vista que derive físico/disponible/reservado/en movimiento/entregado. |
| Despachos | `allocations`, `shipments`, `shipment_items`, `create_shipment` | **REFACTORIZAR + CREAR** | `create_shipment` despacha **solo contra una necesidad** y **siempre la asignación completa**. No existe el eje bodega→bodega (ver §2). Tampoco existe el estado «preparando»: la RPC nace en `dispatched`. |
| Transporte | Columnas `shipments.carrier_name` y `custodian_private` | **REFACTORIZAR** | `p_carrier_name` es opcional («Opcional y privado» en la UI) y no hay tipo de transporte, identificación, vehículo ni placa. La Fase 12 exige datos mínimos obligatorios antes de EN MOVIMIENTO. |
| Entregas | `deliveries`, `register_delivery`, `validate_delivery` | **REFACTORIZAR** | Concilia `entregado + dañado = despachado`, así que un faltante hay que registrarlo como daño. Falta separar **faltante** de **dañado** y falta que la recepción cree inventario en el destino. |
| Reportes | `public_event_dashboard`, `transparency-dashboard`, dos exportaciones Excel, `treasury_balance` | **REUTILIZAR + CREAR** | La superficie pública y la de tesorería están cubiertas. Falta el tablero operativo de la Fase 16 (stock, reservas, en movimiento, pendientes, por centro, por aliado, por necesidad, historial). |

## 2. Validaciones principales: ¿hay más de una manera de hacer lo mismo?

| Operación | Implementaciones encontradas | Veredicto |
|---|---|---|
| **Crear usuarios** | `scripts/bootstrap-environment.mjs` (declarativo por JSON, sin proyecto fijado, crea cuentas y membresías llamando RPC) y `scripts/provision-sandbox-access.mjs` (mismo trabajo con `PROJECT_REF`, `EVENT_ID` y dos organizaciones **fijados en código**) | **Duplicado real.** El segundo es un caso particular del primero. `ELIMINAR` `provision-sandbox-access.mjs`. |
| **Crear donaciones** | `submit_donation_intake_v2` (única concedida a `authenticated`) → `submit_donation_intake` (revocada, interna) | **No es duplicación.** Es una capa de traducción de catálogos sobre un contrato único. `MANTENER`, documentado. |
| **Actualizar inventario** | `receive_donation` es el único creador de lotes; `allocate_stock`, `create_shipment` y `place_lot_control` son los únicos escritores de `stock_movements`. RLS expone todas las tablas operativas **solo para `select`** | **Fuente única correcta.** No hay escritura directa de stock desde la interfaz (Fase 11 satisfecha en este punto). |
| **Mover productos entre bodegas** | **Ninguna.** Los valores `transfer_in`/`transfer_out` del enum `stock_movement_type` están declarados y **no se usan en ninguna parte** del repositorio | **Funcionalidad ausente**, no duplicada. `CREAR`. Es el hueco que impide los pasos 12 a 19 de la Fase 17. |
| **Registrar entregas** | `register_delivery` (único) + `validate_delivery` (verificación independiente) | **Camino único.** `REFACTORIZAR` por lo dicho en §1. |
| **Administrar bodegas** | `manage_delivery_point` (único, idempotente, versiona reglas y audita) | **Camino único.** `MANTENER`. |
| **Consultar trazabilidad** | `track_public_code` (cuatro etapas fijas) y `track_public_journey` (cadena real de hitos) | **Duplicado real.** El front ya usa las dos en la misma pantalla. `FUSIONAR` bajo `track_public_journey`. |

## 3. Consecuencia para el orden de implementación

La cadena que pide el principio arquitectónico final se rompe en tres puntos, y solo en tres:

1. **Antes de la donación**: no hay ALIADO autorregistrado ni confirmación de correo, y la donación
   no puede nacer desde una necesidad (`donation_intakes` no tiene ningún vínculo con `need_cases`).
2. **Dentro del inventario**: el Kardex es correcto pero no se deriva; la UI lee un contador
   independiente (`quantity_initial`) que sí puede desincronizarse.
3. **Después del inventario**: no existe bodega→bodega, el transporte es opcional y la recepción en
   destino no crea inventario ni distingue faltante de daño.

Todo lo demás del loop ya está construido y debe reutilizarse tal cual.
