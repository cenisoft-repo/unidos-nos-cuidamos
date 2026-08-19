-- SUPER_ADMIN se incorpora al RBAC que ya existe, no a uno nuevo: es un valor mas del
-- enum `app_role` y se concede como cualquier otro rol, con una fila en `memberships`.
-- Lo que cambia no es la forma del permiso sino su alcance, y ese alcance vive en las
-- cuatro funciones de compuerta (`is_org_member`, `has_any_role`, `has_event_role`,
-- `has_location_scope`), que son las que ya usan todas las politicas y todas las RPC.
--
-- El valor va en su propia migracion porque PostgreSQL no permite usar un valor de enum
-- recien anadido dentro de la misma transaccion que lo anade.
alter type public.app_role add value if not exists 'super_admin';
