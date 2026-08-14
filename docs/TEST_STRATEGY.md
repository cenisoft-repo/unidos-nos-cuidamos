# Estrategia de pruebas

- Unidad: transiciones, moderación, códigos y presentación.
- PostgreSQL/pgTAP: RLS, tenant, funciones, idempotencia, concurrencia y conciliación.
- Integración: Auth + RPC + Storage local.
- E2E Playwright: ocho escenarios A–H con datos sintéticos; escritorio y móvil.
- No funcional: teclado, contraste/axe, 320–1440 px, offline, carga, secretos y dependencias.
- Recuperación: `supabase db reset`, export/restore sandbox y conteos independientes.

Un fallo introducido bloquea el siguiente recorrido. Un servicio externo se reemplaza solo por adaptador fiel y queda rotulado como sandbox.
