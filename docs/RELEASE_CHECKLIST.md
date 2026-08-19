# Checklist de salida

## G1 demo controlada

- [x] Ocho escenarios A–H y conciliaciones verdes en sandbox.
- [x] RLS/IDOR y privacidad sin P0/P1 conocidos en sandbox.
- [x] Migración y rollback ensayados con fixture sintético.
- [x] Build, responsive y semántica/teclado básica aprobados.
- [x] Antiabuso local, Auth cerrado a auto-registro, observabilidad mínima y recuperación sintética ensayados.
- [x] CI versionada, cola offline endurecida y runbooks/paquete de aprobación preparados.

## G2/G3 (bloqueado)

- [ ] Operador, autoridades, organizaciones, RACI y SLA nominales.
- [ ] DPIA, amenaza y cumplimiento validados.
- [ ] Proveedor/fondos/AML/KYB, contabilidad y certificados aprobados.
- [x] Backup/restauración local sintética con checksum y RTO medido.
- [ ] Backups remotos/PITR, monitoreo externo, alertas, incidentes y capacitación.
- [ ] Autorización explícita de despliegue, migración y recaudo.

---

# Salida de `integration/superadmin-consolidacion` a producción

Rama empujada el 2026-08-19. Diez migraciones pendientes en remoto
(`202608190001`…`202608200004`); el remoto conserva 28, hasta `202608170007`.

## Lo que hay que saber antes de empezar

**El orden no es indiferente y no hay orden sin interrupción.** Las migraciones
retiran la firma de dieciséis parámetros de `submit_donation_intake_v2` y cambian
`create_shipment` (5→7), `register_delivery` (4→5) y `shipments.carrier_name`. El
front que hoy está en producción llama a las firmas viejas; el front nuevo llama a
las nuevas. Cualquiera de los dos órdenes deja una ventana en la que uno de los dos
lados no encuentra lo que invoca.

Se aplica primero la base y de inmediato se despliega el front. La ventana afecta al
registro de aportes, a la consola de bodega y a reportes, y dura lo que tarde el
build de Vercel. **No empujar `main` antes de aplicar las migraciones**: la
integración de Git dispararía el build y el front nuevo quedaría vivo contra un
esquema viejo.

**`supabase db push` no toca la configuración de Auth.** El autorregistro ALIADO
necesita `enable_signup` y la confirmación de correo activas en el proyecto remoto, y
eso vive en el panel.

> ⚠️ **No usar `supabase config push` para eso.** `supabase/config.toml` declara
> `site_url = "http://127.0.0.1:3000"` y redirecciones a localhost, que son correctas
> para el sandbox. Empujarlas a producción dejaría todos los enlaces de confirmación
> apuntando a la máquina de quien lo ejecute. El cambio de Auth se hace en el panel, o
> primero se corrige `config.toml` con las URL reales de producción.

## Procedimiento

1. **Enlaces.** Ya restaurados desde `.local-backups/enlaces-remotos/` a
   `.vercel/project.json` y `supabase/.temp/project-ref`. Mientras estén puestos,
   `preflight:local` bloquea y con él `npm run verify`: es su propósito. Retirarlos al
   terminar.

2. **Credencial.** El CLI necesita la contraseña de la base del proyecto remoto:

   ```bash
   export SUPABASE_DB_PASSWORD='...'
   ```

3. **Respaldo antes de nada.** No es opcional; es lo único que hace reversible el paso 5.

   ```bash
   npx supabase db dump --linked -f .local-backups/prod-schema-pre-superadmin.sql
   ```

   ```bash
   npx supabase db dump --linked --data-only -f .local-backups/prod-data-pre-superadmin.sql
   ```

4. **Confirmar qué se va a aplicar.** Deben aparecer diez pendientes y ninguna
   discrepancia en las 28 ya aplicadas.

   ```bash
   npx supabase migration list --linked
   ```

5. **Aplicar.**

   ```bash
   npx supabase db push --linked
   ```

6. **Desplegar el front inmediatamente después.**

   ```bash
   npx vercel --prod
   ```

7. **Auth en el panel** (Authentication → Providers → Email): habilitar el registro y
   exigir confirmación de correo. Sin esto, `/registro` acepta el formulario y la
   activación nunca llega.

8. **Conceder la autoridad global.** No hay forma de hacerlo desde la aplicación —es
   deliberado, ADR-011— y la escritura directa sobre `memberships` está bloqueada por
   disparador. Con la clave de servicio del proyecto:

   ```sql
   select public.grant_super_admin('correo@dominio', '<organization_id>', '<event_id>', 'Motivo de la concesión');
   ```

## Comprobaciones posteriores

- `npx supabase migration list --linked` muestra 38 aplicadas y ninguna pendiente.
- `GET /api/health` responde 200 en el dominio de producción.
- Un aporte de prueba llega a la cola de verificación.
- `/operaciones/parametrizacion` abre para la autoridad global y redirige para el resto.
- Repetir el arnés de simulación remota para cerrar `G-022` globalmente.
- Retirar `.vercel/project.json` y `supabase/.temp/project-ref`, y comprobar que
  `npm run preflight:local` vuelve a pasar.

## Lo que sigue abierto y no lo resuelve este despliegue

`G-002` a `G-006` (operador, DPIA, política de aceptación, proveedor financiero,
marca) son decisiones humanas; `G-007`, `G-015` y `G-017` son administración de
entorno; las credenciales de base expuestas siguen sin rotar y no hay backups
remotos con PITR ni monitoreo externo. Nada de eso lo cambia aplicar estas
migraciones: el entorno sigue siendo G1 con datos sintéticos y **no debe recibir
datos reales, dinero ni comunicación institucional**.
