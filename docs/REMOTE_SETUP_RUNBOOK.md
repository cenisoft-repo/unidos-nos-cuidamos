# Runbook · Preparar Supabase remoto y desplegar en Vercel

Estado de partida: la aplicación está verificada en local (26 unitarias, 94 pgTAP, RLS, concurrencia, 24 E2E, build de producción con CSP). `preflight:deploy` está **bloqueado** porque no existe base remota.

> **Regla que no se negocia:** `supabase/seed.sql` crea cinco cuentas con la contraseña `RutaSolidaria2026!`, publicada en el README y en el manual de usuario. **Nunca debe ejecutarse contra un entorno remoto.** `supabase db push` solo aplica migraciones, así que el procedimiento de abajo es seguro; el riesgo aparece únicamente si alguien ejecuta `db reset` apuntando a remoto.

---

## Paso 1 · Crear el proyecto (lo haces tú)

Las credenciales las manejas tú; yo no debo introducirlas ni verlas.

1. Crea un proyecto en Supabase (región cercana a Colombia, p. ej. `us-east-1` o `sa-east-1`).
2. Guarda la **contraseña de base de datos** en tu gestor de contraseñas.
3. Anota la **referencia del proyecto** (`<project-ref>`), visible en la URL del panel.
4. En *Project Settings → API* copia:
   - **Project URL** → `https://<project-ref>.supabase.co`
   - **Publishable / anon key** (la pública, **no** la `service_role`)

> La clave `service_role` no se usa en esta aplicación y no debe llegar nunca al frontend ni a Vercel.

---

## Paso 2 · Enlazar y aplicar el esquema

`supabase login` y `supabase link` piden credenciales: ejecútalos tú.

```bash
npx supabase login
```

```bash
npx supabase link --project-ref <project-ref>
```

Después, aplicar las 14 migraciones (esto sí puedo ejecutarlo yo una vez enlazado):

```bash
npx supabase db push
```

Verificar que quedaron todas:

```bash
npx supabase migration list
```

Las migraciones son portables: solo requieren `pgcrypto` y `postgis`, ambas disponibles en Supabase, y no referencian roles privilegiados. Aplican limpiamente desde cero — comprobado en local con `db reset` + 94 pruebas pgTAP.

---

## Paso 3 · Configurar Auth en el panel remoto

`supabase/config.toml` gobierna **solo el entorno local**. Estos valores hay que replicarlos a mano en *Authentication → Providers / Policies*:

| Ajuste | Valor | Motivo |
|---|---|---|
| Enable signup | **Desactivado** | El acceso es por membresía, no por auto-registro |
| Anonymous sign-ins | Desactivado | — |
| Manual linking | Desactivado | — |
| Minimum password length | **12** | Coincide con el local |
| Password requirements | Mayúsculas, minúsculas, dígitos y símbolos | — |
| **Leaked password protection** | **Activar** | Cierra el gap **G-007** |
| Site URL | `https://<dominio-de-produccion>` | Enlaces de correo válidos |
| Redirect URLs | El mismo dominio | Evita redirecciones abiertas |
| JWT expiry | 3600 | — |
| Refresh token rotation | Activado | — |

---

## Paso 4 · Variables de entorno en Vercel

En *Project → Settings → Environment Variables*, para **Production** y **Preview**:

| Variable | Valor |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | `https://<project-ref>.supabase.co` |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | La clave publicable (nunca `service_role`) |
| `NEXT_PUBLIC_APP_URL` | `https://<dominio-de-produccion>` |
| `NEXT_PUBLIC_APP_ENV` | `sandbox` |

### Sobre `NEXT_PUBLIC_APP_ENV`

Déjala en `sandbox` mientras la base contenga datos que no sean operaciones reales. Es lo que mantiene visible el aviso "Datos de práctica".

Cámbiala a `production` **únicamente** cuando se cumplan a la vez:

- la base sirve información real y verificada;
- el paquete `docs/PILOT_APPROVAL_PACKET.md` está firmado;
- los gaps G-003 (política humanitaria), G-004 (proveedor financiero), G-005 (DPIA y base legal) y G-006 (autorización de marca) están cerrados.

Declararla antes convertiría registros de práctica en cifras presentadas como reales ante donantes y entidades.

> La CSP deriva sus orígenes de estas variables en cada petición, así que `connect-src` incorporará el dominio remoto y su WebSocket (`wss://`) automáticamente. No hay que editar la política.

---

## Paso 5 · Verificar antes de publicar

```bash
npm run preflight:deploy
```

Debe pasar de `blocked` a sin bloqueos de configuración. Los gaps de gobernanza (G-002 a G-006) seguirán abiertos hasta que existan las aprobaciones humanas: son decisiones, no configuración.

Con el entorno enlazado, conviene repetir contra el remoto:

```bash
npm run test:rls
```

---

## Paso 6 · Desplegar

Solo después de los pasos anteriores:

```bash
npx vercel deploy
```

Para producción:

```bash
npx vercel deploy --prod
```

Tras el despliegue, comprobar:

1. `https://<dominio>/api/health` responde `{"status":"ok"}` con `database: connected`.
2. La portada carga necesidades reales y **no** la pantalla de "No mostraremos cifras incompletas".
3. La cabecera `content-security-policy` viaja en las respuestas de documento.
4. El aviso "Datos de práctica" aparece o no, según lo declarado en `NEXT_PUBLIC_APP_ENV`.

---

## Pendiente de decisión

El repositorio ya está enlazado a un proyecto de Vercel (`unidos-nos-cuidamos`) y `.env.local` recibió un `VERCEL_OIDC_TOKEN` que **no** generó este trabajo. Ambos están cubiertos por `.gitignore`, de modo que no se versionan. Antes de continuar conviene confirmar que ese enlace es intencional; si no lo es, retirar `.vercel/` y **rotar el token desde el panel de Vercel** (esa rotación la haces tú).

Mientras exista el enlace, `npm run preflight:local` falla a propósito y detiene `npm run verify`. Es el comportamiento correcto: la barrera funciona.
