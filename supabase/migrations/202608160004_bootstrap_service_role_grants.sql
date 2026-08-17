-- Provisión desde cero: privilegios mínimos y explícitos para `service_role`.
--
-- El evento, las organizaciones, los perfiles y las membresías son el arranque en frío del
-- sistema: no existe todavía ninguna sesión con rol que pueda crearlos, así que no pueden
-- pasar por las funciones `security definer` que gobiernan el resto de escrituras.
--
-- Hasta ahora esas escrituras dependían de los privilegios por defecto que la plataforma
-- concede a `service_role` en un proyecto nuevo, que el esquema local no reproduce: el mismo
-- procedimiento funcionaba en remoto y fallaba en local. Aquí se fija el contrato para que
-- el arranque sea idéntico en ambos.
--
-- El alcance es deliberadamente corto. `service_role` sigue sin poder tocar necesidades,
-- aportes, inventario, despachos, evidencias, transacciones ni auditoría: esas rutas
-- conservan actor, validación de estado, idempotencia e historial append-only.

grant select, insert, update on table
  public.organizations,
  public.emergency_events,
  public.profiles,
  public.memberships,
  public.funds
to service_role;

-- Los centros de acopio quedan deliberadamente fuera: el bootstrap los consulta con
-- `delivery_points_admin` y los escribe con `manage_delivery_point`, ambas bajo una sesión
-- con rol `event_admin`. Así la parametrización nace versionada y auditada, igual que si
-- se hubiera hecho desde /operaciones/centros.
