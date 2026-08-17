# Runbook · Montar el entorno desde cero y entregarlo

Procedimiento completo para pasar de **un proyecto vacío** a **un sistema con centros de acopio, cuentas por rol y el recorrido funcionando**, comprobado antes de entregar.

Sirve igual para un sandbox interno, un piloto o una instancia definitiva: lo que cambia es el archivo de declaración del entorno, no el procedimiento.

> **Lo que este runbook no autoriza.** Montar el entorno no habilita datos reales, PII, recaudo, comunicación institucional ni marcas. Esas decisiones son las brechas `G-002` a `G-006` del `docs/GAP_LEDGER.md` y se cierran con firmas humanas, no con configuración.

> **Regla que no se negocia.** `supabase/seed.sql` crea cinco cuentas con una contraseña publicada en el README. **Nunca debe ejecutarse contra un entorno remoto.** `supabase db push` solo aplica migraciones, así que este procedimiento es seguro; el riesgo aparece solo si alguien ejecuta `db reset` apuntando a remoto.

---

## Resumen del procedimiento

| Paso | Qué hace | Quién |
|---|---|---|
| 1 | Crear el proyecto y guardar sus claves | Tú |
| 2 | Aplicar las 19 migraciones | `supabase db push` |
| 3 | Endurecer Auth en el panel | Tú |
| 4 | Declarar evento, organizaciones, cuentas y **puntos de acopio/despacho** | Tú, en un JSON |
| 5 | Provisionar el entorno | `npm run bootstrap:environment` |
| 6 | Declarar variables en el hosting | Tú |
| 7 | Probar el recorrido completo | `npm run verify:environment-flow` |
| 8 | Desplegar y comprobar | `vercel deploy` |

---

## Paso 1 · Crear el proyecto

Las credenciales las manejas tú.

1. Crea un proyecto en Supabase, en una región cercana a Colombia (`us-east-1` o `sa-east-1`).
2. Guarda la **contraseña de base de datos** en tu gestor de contraseñas.
3. Anota la **referencia del proyecto** (`<project-ref>`), visible en la URL del panel.
4. En *Project Settings → API* copia tres valores:
   - **Project URL** → `https://<project-ref>.supabase.co`
   - **Publishable / anon key** — es la pública, viaja al navegador.
   - **Secret / service_role key** — solo la usa el comando de provisión, desde tu máquina. **Nunca** en `.env`, en el código, en el navegador ni en el hosting.

---

## Paso 2 · Aplicar el esquema

`supabase login` y `supabase link` piden credenciales: ejecútalos tú.

```bash
npx supabase login
```

```bash
npx supabase link --project-ref <project-ref>
```

```bash
npx supabase db push
```

Comprueba que quedaron las 19:

```bash
npx supabase migration list
```

Las migraciones son portables: solo requieren `pgcrypto` y `postgis`, ambas disponibles en Supabase, y no referencian roles privilegiados. Aplican limpiamente desde cero, comprobado con `db reset` y 174 pruebas pgTAP.

---

## Paso 3 · Endurecer Auth en el panel

`supabase/config.toml` gobierna **solo el entorno local**. Estos valores hay que replicarlos a mano en *Authentication → Providers / Policies*:

| Ajuste | Valor | Motivo |
|---|---|---|
| Enable signup | **Desactivado** | El acceso es por membresía, no por auto-registro |
| Anonymous sign-ins | Desactivado | — |
| Manual linking | Desactivado | — |
| Minimum password length | **12** | Coincide con el local |
| Password requirements | Mayúsculas, minúsculas, dígitos y símbolos | — |
| **Leaked password protection** | **Activar** | Cierra la brecha `G-007` |
| Site URL | `https://<dominio>` | Enlaces de correo válidos |
| Redirect URLs | El mismo dominio | Evita redirecciones abiertas |
| JWT expiry | 3600 | — |
| Refresh token rotation | Activado | — |

Deja el registro libre cerrado **antes** del paso 5: la provisión crea las cuentas por la API de administración y no necesita que nadie pueda registrarse solo.

---

## Paso 4 · Declarar el entorno

Aquí es donde defines **los puntos de acopio y de despacho**, quién opera y con qué roles.

```bash
cp supabase/bootstrap.config.example.json ../entorno-produccion.json
```

Guárdalo **fuera del repositorio**: describe direcciones privadas de tus puntos.

### Qué declara el archivo

- **`event`** — el evento que sirve la instancia. Su `id` es un UUID que eliges tú y que queda fijo para siempre. `simulated: true` mientras los datos sean de práctica.
- **`organizations`** — cada organización con su UUID, nombre y `slug`. Se crean verificadas y activas.
- **`accounts`** — una cuenta por función, con sus membresías. Las contraseñas **no** se declaran: el comando las genera.
- **`deliveryPoints`** — los puntos, cada uno con su propósito: acopio, despacho o ambos.
- **`funds`** — los fondos del evento, si hay tesorería.

### Un centro de acopio

```json
{
  "organization": "coordinacion",
  "name": "Centro de acopio Norte",
  "publicLocationText": "Medellín · zona norte aproximada",
  "privateAddress": "Calle y número exactos, uso interno",
  "publicInstructions": "Recepción de lunes a sábado. Presenta el código APO al llegar.",
  "latitude": 6.267,
  "longitude": -75.56,
  "coldChainCapable": false,
  "active": true,
  "acceptsDonations": true,
  "dispatchesShipments": true,
  "accepts": ["Agua", "Alimentos", "Higiene", "Refugio", "Logística"]
}
```

### Un centro de despacho

Un punto puede recibir, despachar o ambas cosas. Una base que solo despacha no declara categorías, no aparece en el mapa público ni en el paso «Punto de entrega» del aliado, y solo sirve como **origen** de una salida:

```json
{
  "organization": "coordinacion",
  "name": "Base logística Sur",
  "publicLocationText": "Medellín · zona sur aproximada",
  "privateAddress": "Calle y número exactos, uso interno",
  "latitude": 6.198,
  "longitude": -75.585,
  "coldChainCapable": false,
  "active": true,
  "acceptsDonations": false,
  "dispatchesShipments": true,
  "accepts": []
}
```

Sin ningún punto con `dispatchesShipments`, la organización puede recibir aportes pero **no puede despachar nada**: la consola de bodega lo dirá explícitamente. Si omites ambos campos, el punto se toma como centro de acopio, que es el caso común.

Lo que hace cumplir el sistema:

- `publicLocationText` es lo **único territorial que se publica**. `privateAddress` no sale de la base y no aparece en ninguna proyección ni exportación.
- `latitude`/`longitude` son la coordenada **aproximada** del mapa público, no la puerta. Deben caer dentro de Colombia.
- `accepts` solo admite categorías del catálogo vigente, máximo ocho: `Alimentos`, `Agua`, `Higiene`, `Salud`, `Refugio`, `Protección`, `Logística`, `Otro`. Lo que no declares queda registrado como **prohibido** para ese punto, con su versión y su fecha.
- `coldChainCapable: false` bloquea los aportes que pidan cadena de frío. El formulario lo valida antes de enviar y la base lo vuelve a validar.
- Un aliado solo ve los puntos **activos de su propia organización**. Declarar un punto en la organización equivocada es el error más caro de este archivo.

**Sin al menos un punto activo, el aliado de esa organización no puede registrar bienes.** El comando falla si no declaras ninguno.

### Roles disponibles

`event_admin`, `verifier`, `partner_reporter`, `warehouse_operator`, `logistics_operator`, `treasury_requester`, `treasury_approver`, `auditor`.

Alguna cuenta debe tener `event_admin`: es la única que puede parametrizar centros. Y `treasury_requester` y `treasury_approver` **deben ser personas distintas**: la base rechaza que alguien apruebe su propia solicitud.

---

## Paso 5 · Provisionar

```bash
BOOTSTRAP_CONFIG_PATH=../entorno-produccion.json \
SUPABASE_URL=https://<project-ref>.supabase.co \
SUPABASE_SECRET_KEY=<secret key> \
SUPABASE_PUBLISHABLE_KEY=<publishable key> \
BOOTSTRAP_CONFIRM_TARGET=<project-ref>.supabase.co \
BOOTSTRAP_CREDENTIALS_PATH=../accesos-temporales.txt \
npm run bootstrap:environment
```

`BOOTSTRAP_CONFIRM_TARGET` tiene que repetir exactamente el host de destino. Es la barrera contra provisionar el proyecto equivocado.

El comando:

1. Comprueba que el esquema está aplicado leyendo los catálogos con la clave pública.
2. Crea el evento y las organizaciones.
3. Crea las cuentas con contraseñas generadas, sus perfiles y sus membresías.
4. Crea los centros de acopio **iniciando sesión como administración y llamando a `manage_delivery_point`**, la misma función que usa `/operaciones/centros`. La parametrización nace versionada y auditada, igual que si la hubieras hecho a mano en la interfaz.
5. Verifica que cada cuenta inicia sesión, que tiene exactamente los roles declarados, y que un aliado **no** alcanza los puntos de otra organización.
6. Escribe los accesos temporales en un archivo solo legible por ti e imprime las variables del paso 6.

Es **idempotente**: puedes reejecutarlo. Un centro que ya coincide con lo declarado no se reescribe, así que no genera versiones de reglas ni auditoría sin cambio real.

Si el evento está declarado con `simulated: false` sobre un destino remoto, exige además `BOOTSTRAP_ACKNOWLEDGE_REAL_EVENT=yes`. Es deliberado: pasar a datos no simulados es una decisión, no un parámetro.

---

## Paso 6 · Variables de entorno en el hosting

En *Project → Settings → Environment Variables*, para **Production** y **Preview**:

| Variable | Valor |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | `https://<project-ref>.supabase.co` |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | La clave publicable (**nunca** la secreta) |
| `NEXT_PUBLIC_APP_URL` | `https://<dominio>` |
| `NEXT_PUBLIC_APP_ENV` | `sandbox` |
| `NEXT_PUBLIC_EVENT_ID` | Lo imprime el paso 5 |
| `NEXT_PUBLIC_EVENT_SLUG` | Lo imprime el paso 5 |

Sin `NEXT_PUBLIC_EVENT_ID` la aplicación usa el evento sintético local y la instancia se ve vacía. Es el olvido más común.

### Sobre `NEXT_PUBLIC_APP_ENV`

Déjala en `sandbox` mientras la base contenga cualquier cosa que no sean operaciones reales. Es lo que mantiene visible el aviso "Datos de práctica".

Cámbiala a `production` **únicamente** cuando se cumplan a la vez:

- la base sirve información real y verificada;
- `docs/PILOT_APPROVAL_PACKET.md` está firmado;
- `G-003` (política humanitaria), `G-004` (proveedor financiero), `G-005` (DPIA y base legal) y `G-006` (autorización de marca) están cerradas.

Declararla antes convertiría registros de práctica en cifras presentadas como reales ante donantes y entidades.

> La CSP deriva sus orígenes de estas variables en cada petición, así que `connect-src` incorpora el dominio remoto y su WebSocket automáticamente. No hay que editar la política.

---

## Paso 7 · Probar el recorrido completo

```bash
BOOTSTRAP_CONFIG_PATH=../entorno-produccion.json \
SUPABASE_URL=https://<project-ref>.supabase.co \
SUPABASE_PUBLISHABLE_KEY=<publishable key> \
BOOTSTRAP_CONFIRM_TARGET=<project-ref>.supabase.co \
BOOTSTRAP_CREDENTIALS_PATH=../accesos-temporales.txt \
npm run verify:environment-flow
```

Recorre el flujo con las cuentas que vas a entregar, usando solo las funciones que usa la aplicación:

reporte ciudadano → verificación y publicación → aporte en especie → aprobación → recepción → asignación → despacho → entrega → validación independiente → aporte económico → conciliación → solicitud y aprobación de gasto → cadena de trazabilidad.

De paso comprueba lo que suele romperse en silencio:

- **Separación de funciones:** el aliado no aprueba su propio aporte ni concilia su propio dinero, quien entrega no valida su entrega, quien solicita no aprueba su gasto.
- **Idempotencia:** recepción, despacho y conciliación repetidos no duplican nada.
- **Límites operativos:** no se reserva más de lo que hay, no se despacha desde un punto que solo recibe, la entrega debe conciliar con lo despachado y el destino público rechaza teléfonos, cuentas y enlaces.
- **Privacidad:** el reporte ciudadano no es legible para un visitante, el transportador no llega a la proyección pública y la referencia privada del soporte financiero no es consultable.
- **Trazabilidad:** el código `APO-*` del donante recorre los ocho hitos hasta la validación de la entrega, con fecha y con el código operacional visible.

**No usa la clave secreta.** Si pasa, los permisos que entregas son suficientes; si falla por permisos, faltan roles en el paso 4.

Deja registros creados a propósito: una necesidad, dos aportes, un lote, un despacho, una entrega, una conciliación y un gasto. El historial es append-only y no se limpia. Ejecútalo **antes** de entregar, no sobre datos reales.

Conviene añadir también:

```bash
npm run test:rls
```

---

## Paso 8 · Desplegar

```bash
npx vercel deploy
```

Para producción:

```bash
npx vercel deploy --prod
```

Después comprueba, en este orden:

1. `https://<dominio>/api/health` responde `{"status":"ok"}` con `database: connected`.
2. La portada carga las necesidades del evento declarado y **no** la pantalla de "No mostraremos cifras incompletas". Si sale vacía, revisa `NEXT_PUBLIC_EVENT_ID`.
3. La cabecera `content-security-policy` viaja en las respuestas de documento.
4. El aviso "Datos de práctica" aparece o no, según `NEXT_PUBLIC_APP_ENV`.
5. Entra como aliado a `/donar`: el paso **Punto de entrega** muestra los centros que declaraste, y solo los de su organización.

---

## Entregar los accesos

El archivo de `BOOTSTRAP_CREDENTIALS_PATH` contiene contraseñas temporales en claro.

- Entrégalas **una por persona**, por un canal controlado. Nunca el archivo completo.
- Pide rotación en el primer ingreso.
- Borra el archivo cuando termines la entrega.
- No lo guardes en el repositorio: el comando se niega a escribirlo dentro del proyecto.

---

## Dos entornos locales que no pueden coexistir

La base local sirve para dos cosas incompatibles, y conviene saber en cuál estás.

| | Entorno de suite | Entorno de entrega |
|---|---|---|
| Datos | `supabase/seed.sql`: necesidades, aportes y cuentas de demostración | Solo lo que declara tu JSON |
| `NEXT_PUBLIC_APP_ENV` | `sandbox` | `production` |
| Aviso «Datos de práctica» | Visible | Oculto |
| Para qué sirve | `npm run verify`, pgTAP y Playwright | Aceptación del producto entregado |

**Ir al entorno de entrega:**

```bash
npm run env:entrega
```

Después ejecuta `bootstrap:environment` y pon `NEXT_PUBLIC_APP_ENV=production` junto con `NEXT_PUBLIC_EVENT_ID` y `NEXT_PUBLIC_EVENT_SLUG` en `.env.local`.

**Volver al entorno de suite:**

```bash
npm run env:suite
```

Y devuelve `NEXT_PUBLIC_APP_ENV` a `sandbox` quitando las dos variables del evento.

> Si ejecutas `npm run verify`, `supabase test db` o Playwright estando en el entorno de entrega, fallarán en masa. No es un defecto del producto: esas pruebas comprueban el conjunto de datos sintéticos que ya no está. Vuelve al entorno de suite antes de validar código.

---

## Cambios posteriores

**Añadir o modificar un centro de acopio.** Hay dos caminos equivalentes:

- Desde la aplicación, en `/operaciones/centros`, con una cuenta `event_admin`.
- Editando el JSON y reejecutando `bootstrap:environment`.

Ambos pasan por `manage_delivery_point`, así que ambos versionan las reglas y dejan traza. Editar el JSON y reejecutar actualiza el punto existente por nombre, no lo duplica.

**Añadir una cuenta.** Agrégala al JSON y reejecuta. Ojo: reejecutar **rota la contraseña de todas las cuentas declaradas**, también las que ya funcionaban. Si solo quieres agregar una persona sin invalidar el acceso de las demás, créala desde el panel de Supabase y añade su membresía a mano.

**Renombrar el evento.** El `name` y el `publicSummary` se actualizan al reejecutar. El `id` y el `slug` no deberían cambiar nunca: el `slug` viaja en `NEXT_PUBLIC_EVENT_SLUG` y el `id` es la clave de todo lo creado.

---

## Errores frecuentes

| Síntoma | Causa | Salida |
|---|---|---|
| `El destino no tiene catálogos` | Faltan las migraciones | Ejecuta el paso 2 |
| `BOOTSTRAP_CONFIRM_TARGET debe repetir…` | El host no coincide | Revisa que apuntas al proyecto correcto |
| `permission denied for table organizations` | Falta la migración `202608160004` | `npx supabase db push` |
| `Solo administración del evento puede parametrizar…` | Ninguna cuenta tiene `event_admin` en ese evento | Corrige `accounts` en el JSON |
| `Una categoría aceptada no pertenece al catálogo` | Categoría mal escrita en `accepts` | Usa exactamente las ocho del paso 4 |
| La portada sale vacía tras desplegar | Falta `NEXT_PUBLIC_EVENT_ID` | Paso 6 |
| El aliado no ve ningún punto en `/donar` | El punto quedó en otra organización, inactivo, o solo despacha | Revisa `organization`, `active` y `acceptsDonations` |
| «Esta organización no tiene ningún punto habilitado para despachar» | Ningún punto de esa organización tiene `dispatchesShipments` | Actívalo en Puntos de entrega o en el JSON |
| `Ese punto no está habilitado para despachar salidas` | Se eligió como origen un punto que solo recibe | Marca «Centro de despacho» en ese punto |
| `db reset` falla con `LegacyDbSetupError` | Reinicio de contenedores intermitente | Repite el comando |

---

## Estado del enlace actual del repositorio

El repositorio ya está enlazado a un proyecto de Vercel (`unidos-nos-cuidamos`) y `.env.local` recibió un `VERCEL_OIDC_TOKEN` que no generó este trabajo. Ambos están cubiertos por `.gitignore`. Antes de continuar conviene confirmar que ese enlace es intencional; si no lo es, retirar `.vercel/` y **rotar el token desde el panel de Vercel**.

Mientras exista el enlace, `npm run preflight:local` falla a propósito y detiene `npm run verify`. Es el comportamiento correcto: la barrera funciona.

---

## Procedimiento anterior

`npm run provision:sandbox-access` y `npm run simulate:sandbox` siguen existiendo, pero están fijados al sandbox `vcgwfyhytzgyzicfbikf` y a sus dos centros sintéticos. Para cualquier entorno nuevo usa `bootstrap:environment` y `verify:environment-flow`, que no están atados a ningún proyecto.
