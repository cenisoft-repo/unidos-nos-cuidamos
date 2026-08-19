-- Limpieza (Fase 22 del loop).
--
-- `submit_donation_intake_v2_catalogs_v1` era la implementacion interna a la que el
-- contrato publico delegaba mientras el envoltorio vivia en `202608160003`. La funcion
-- de la Fase 4 (`202608190002`) la sustituyo por completo: hoy el contrato publico valida
-- y delega directamente en `submit_donation_intake`, y nadie mas la invoca.
--
-- Se retira porque una funcion `security definer` sin llamadores es superficie viva sin
-- duenno: sigue existiendo, sigue teniendo privilegios que revisar y ya no la cubre
-- ninguna prueba de comportamiento. Las migraciones que la crearon se conservan: son
-- historia aplicada, no codigo muerto.
drop function if exists public.submit_donation_intake_v2_catalogs_v1(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text, boolean,
  text, jsonb, numeric, uuid, jsonb, jsonb, text
);
