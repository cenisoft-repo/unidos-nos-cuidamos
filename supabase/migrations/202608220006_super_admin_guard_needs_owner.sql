-- G-071 · La puerta de SUPER_ADMIN se saltaba poniendo la marca a mano.
--
-- `202608200002` cerro la escritura directa de una membresia SUPER_ADMIN con un disparador
-- que deja pasar cuando encuentra la marca de transaccion `app.super_admin_grant`, marca que
-- solo ponen `grant_super_admin()` y `revoke_super_admin()`. La idea era correcta; la
-- ejecucion tenia un agujero: **el disparador era `security definer`**, asi que dentro de el
-- `current_user` es siempre el dueno, y la unica condicion efectiva quedaba siendo la marca.
-- Y `set_config` lo puede llamar cualquiera.
--
-- Reproducido contra la base local antes de escribir esto, como `service_role`:
--
--   select set_config('app.super_admin_grant','on', true);
--   insert into public.memberships(..., role, ...) values (..., 'super_admin', ...);
--   -> INSERT 0 1
--   -> auditoria: SIN ACTOR
--   -> is_super_admin() para esa cuenta: true
--
-- `service_role` tiene INSERT y UPDATE sobre `memberships` desde `202608160004`, para el
-- arranque en frio. Es decir: la via sancionada era la dificil y la silenciosa seguia abierta,
-- que es literalmente lo que el comentario de `202608200002` decia haber cerrado.
--
-- Consecuencia, y por eso es P0: `is_super_admin()` no acota por organizacion ni por evento y
-- es la primera condicion de `is_org_member`, `has_any_role`, `has_event_role`,
-- `has_location_scope`, `manage_organization`, `assign_membership_role` y de la puerta de
-- habilitacion de `202608220001`. Quien se concede SUPER_ADMIN por este atajo pasa despues por
-- todas ellas como un decisor legitimo.
--
-- Lo encontro una revision adversaria de las migraciones de esta sesion. No es un defecto de
-- esta sesion: lleva desplegado desde el 20 de agosto.

CREATE OR REPLACE FUNCTION public.assert_super_admin_grant_path()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  -- La marca es local a la transaccion y solo la ponen `grant_super_admin` y
  -- `revoke_super_admin`. Cualquier otra ruta —incluida una escritura directa con
  -- `service_role`, que tiene INSERT y UPDATE sobre esta tabla— queda bloqueada.
  -- G-071 · La marca sola NO basta, y bastaba.
  --
  -- `set_config` lo puede llamar cualquiera, incluido `service_role`, que ademas tiene INSERT
  -- y UPDATE sobre esta tabla por el arranque en frio de `202608160004`. Comprobado antes de
  -- escribir esto: poniendo la marca a mano e insertando la fila, `service_role` concedia
  -- autoridad global a la cuenta que quisiera, sin actor en la auditoria, y despues
  -- `is_super_admin()` devolvia true.
  --
  -- La segunda condicion es que `current_user` sea el dueno de la tabla, cosa que solo ocurre
  -- dentro de una funcion `security definer` de este esquema —es decir, dentro de
  -- `grant_super_admin` o `revoke_super_admin`, que son las dos vias sancionadas— o en el
  -- arranque en frio como dueno. Una escritura directa desde la API llega como `service_role`
  -- o `authenticated` y queda fuera aunque logre poner la marca.
  --
  -- Y por eso esta funcion ya NO es `security definer`: con derechos del definidor,
  -- `current_user` seria siempre el dueno y la comprobacion no distinguiria nada. Es el mismo
  -- error que `assert_organization_habilitation_path` cometio y corrigio el 2026-08-21; aqui
  -- llevaba desde el 20 de agosto y estaba desplegado.
  if coalesce(current_setting('app.super_admin_grant', true), '') = 'on'
     and current_user = (
       select owner.relowner::regrole::text
       from pg_catalog.pg_class as owner where owner.oid = tg_relid
     ) then
    return new;
  end if;
  -- El orden importa para que cada mensaje diga la verdad: alterar una membresia que ya
  -- es SUPER_ADMIN no es «concederla», y con la comprobacion al reves ese caso caia
  -- siempre en el primer mensaje.
  if tg_op = 'UPDATE' and old.role = 'super_admin' then
    raise exception using
      errcode = '42501',
      message = 'La membresia SUPER_ADMIN no se modifica por escritura directa';
  end if;
  if new.role = 'super_admin' then
    raise exception using
      errcode = '42501',
      message = 'SUPER_ADMIN solo se concede o revoca con grant_super_admin() / revoke_super_admin()';
  end if;
  return new;
end;
$function$;
