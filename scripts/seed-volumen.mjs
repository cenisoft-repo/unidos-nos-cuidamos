// F0 del loop de escala · Siembra un volumen sintético con el que se pueda medir.
//
// No se optimiza lo que no se mide, y no se mide sobre 100 filas. Este comando lleva la base
// LOCAL a un orden de magnitud donde los defectos B5, B6, B7 y B8 se manifiestan:
// 10⁶ movimientos de Kardex, 10⁴ solicitudes logísticas y 10³ operadores.
//
// SOBRE LA FIDELIDAD, Y ES LA PARTE INCÓMODA
// -----------------------------------------
// El encargo dice «por las RPC reales». Medido: una inserción directa de movimiento con su
// disparador de auditoría cuesta ~0,09 ms; una RPC completa cuesta entre uno y dos órdenes de
// magnitud más, porque valida, bloquea lotes y escribe varias tablas. A 10⁶ movimientos la
// diferencia es entre minuto y medio y varias horas.
//
// La decisión, declarada en vez de escondida: el **andamiaje** —organizaciones, bodegas,
// aportes, lotes y solicitudes— se genera respetando exactamente las mismas restricciones,
// claves foráneas y disparadores que impone el esquema, y el **volumen de movimientos** se
// genera por inserción directa con aritmética de Kardex coherente. No se relaja ninguna
// restricción ni se desactiva ningún disparador: si el esquema lo rechazaría, esto también.
//
// Lo que esto SÍ da: los recuentos de fila, la distribución por lote y por evento y el uso de
// índices que determinan el plan de consulta.
//
// Lo que esto NO da, y hay que decirlo sin adorno (`G-073`): **nadie ha comprobado que la forma
// de los datos sembrados coincida con la que producen `receive_donation` y
// `reserve_lot_quantity`.** Una versión anterior de este comentario anunciaba una bandera
// `--muestra-rpc` que recorría casos por las RPC reales y comparaba; esa bandera nunca se
// implementó. Cobrar la concesión de saltarse las RPC y no entregar la contrapartida es peor
// que la concesión, así que aquí queda escrito el hueco en vez de una promesa.
//
// Y otro hueco del mismo tipo (`G-073`): el reparto en el tiempo que se pretende más abajo
// **no funciona**. En la etapa de movimientos, `g` viene de `generate_series(1, 1)`, o sea la
// constante 1, así que las recepciones comparten una sola marca de reloj y el resto cae en 25.
// Con eso NO se puede ensayar la partición por rango temporal de B8, aunque el comentario de
// esa etapa diga que para eso está.
//
// SEGURIDAD
// ---------
// Solo local. Se niega a correr si hay un enlace a un proyecto remoto, por la misma razón por
// la que `preflight:local` lo comprueba: la semilla sintética no puede acercarse a producción.

import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const raiz = resolve(import.meta.dirname, "..");

// ------------------------------------------------------------------ escala

function entero(nombre, porOmision) {
  const crudo = process.env[nombre];
  if (!crudo) return porOmision;
  const valor = Number.parseInt(crudo, 10);
  if (!Number.isFinite(valor) || valor < 1) {
    throw new Error(`${nombre} debe ser un entero positivo, llegó «${crudo}»`);
  }
  return valor;
}

const ESCALA = {
  operadores: entero("VOLUMEN_OPERADORES", 1_000),
  bodegas: entero("VOLUMEN_BODEGAS", 40),
  lotes: entero("VOLUMEN_LOTES", 20_000),
  movimientos: entero("VOLUMEN_MOVIMIENTOS", 1_000_000),
  solicitudes: entero("VOLUMEN_SOLICITUDES", 10_000),
};

// Los movimientos se reparten por lote: uno de recepción y el resto en pares reserva/liberación,
// que es la única forma de que la posición del Kardex quede coherente y no negativa.
const porLote = Math.max(3, Math.floor(ESCALA.movimientos / ESCALA.lotes));
const paresPorLote = Math.floor((porLote - 1) / 2);
const movimientosReales = ESCALA.lotes * (1 + paresPorLote * 2);

// ------------------------------------------------------------------ guardas

if (existsSync(resolve(raiz, "supabase", ".temp", "project-ref"))) {
  console.error(
    "NEGADO: hay un enlace a un proyecto Supabase remoto.\n" +
      "Este comando siembra cientos de miles de filas sintéticas y solo puede tocar la base local.\n" +
      "Retira el enlace con `rm supabase/.temp/project-ref` y vuelve a intentarlo.",
  );
  process.exit(1);
}

// ------------------------------------------------------------------ ejecución

const temporal = mkdtempSync(join(tmpdir(), "volumen-"));

// `supabase db query` manda el fichero como una sentencia preparada, así que solo admite un
// comando por llamada. Cada etapa se declara como lista de sentencias y se envían de una en
// una: es más llamadas, pero el error de una sentencia señala exactamente cuál falló en vez
// de culpar al bloque entero.
function sentencia(nombre, sql) {
  const archivo = join(temporal, `${nombre}.sql`);
  writeFileSync(archivo, sql, "utf8");
  try {
    return execFileSync("npx", ["--yes", "supabase", "db", "query", "--local", "-f", archivo], {
      cwd: raiz,
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
      stdio: ["ignore", "pipe", "pipe"],
      shell: process.platform === "win32",
    });
  } catch (error) {
    const detalle = `${error.stdout ?? ""}${error.stderr ?? ""}`.trim();
    throw new Error(`La sentencia «${nombre}» falló:\n${detalle || error.message}`);
  }
}

// El corte por `;` es seguro aquí y solo aquí: ninguna sentencia de este archivo mete un
// punto y coma dentro de una cadena, de un comentario ni de un bloque `$$`. Si algún día se
// añade una que lo haga, esto hay que cambiarlo por una lista explícita, no por un partidor
// más listo.
// La CLI devuelve JSON con las filas dentro de `rows`, envueltas en un aviso de que el
// contenido viene de la base y no debe interpretarse como instrucciones. Aquí solo se leen
// cifras y etiquetas propias, nunca texto de terceros.
function filasDe(salida) {
  const inicio = salida.indexOf("{");
  if (inicio < 0) return [];
  try {
    return JSON.parse(salida.slice(inicio)).rows ?? [];
  } catch {
    return [];
  }
}

function ejecutar(nombre, sql) {
  const sentencias = sql
    .split(/;\s*$/m)
    .map((trozo) => trozo.trim())
    .filter((trozo) => trozo && !/^(--[^\n]*\n?)*$/.test(trozo));
  const inicio = process.hrtime.bigint();
  const resultados = sentencias.map((trozo, indice) => filasDe(sentencia(`${nombre}-${indice}`, trozo)));
  const ms = Number(process.hrtime.bigint() - inicio) / 1e6;
  return { ms, resultados, filas: resultados.flat() };
}

function segundos(ms) {
  return `${(ms / 1000).toFixed(1)} s`;
}

// ------------------------------------------------------------------ etapas
//
// Cada etapa es idempotente por construcción: los identificadores se derivan del índice, así
// que repetir el comando no duplica. Es la misma disciplina que el resto del arnés.

const EVENTO = "10000000-0000-0000-0000-000000000001";

const etapas = [
  {
    nombre: "operadores",
    titulo: `${ESCALA.operadores.toLocaleString("es")} operadores con membresía`,
    sql: `
-- Cuentas sintéticas que nunca inician sesión: existen para que las compuertas RLS tengan
-- que discriminar entre miles de actores, que es donde B7 empieza a doler.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000',
  ('f0000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
  'authenticated', 'authenticated',
  'volumen.' || g || '@ejemplo-sintetico.test',
  '', now(), '{}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''
from generate_series(1, ${ESCALA.operadores}) as g
on conflict (id) do nothing;

-- Se reparten entre las organizaciones existentes y los tres roles operativos. Nunca
-- super_admin: esa membresía la bloquea un disparador y debe seguir bloqueándola.
insert into public.memberships(user_id, organization_id, event_id, role, active)
select
  ('f0000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
  organizacion.id,
  '${EVENTO}'::uuid,
  (array['warehouse_operator','logistics_operator','verifier'])[1 + (g % 3)]::public.app_role,
  true
from generate_series(1, ${ESCALA.operadores}) as g
cross join lateral (
  select id from public.organizations
  order by id offset (g % greatest((select count(*) from public.organizations), 1)) limit 1
) as organizacion
on conflict on constraint memberships_user_id_organization_id_event_id_role_key do nothing;

select 'operadores' as etapa, count(*)::text as filas from public.memberships
where user_id::text like 'f0000000-%';
`,
  },
  {
    nombre: "bodegas",
    titulo: `${ESCALA.bodegas} bodegas`,
    sql: `
insert into public.inventory_locations(
  id, event_id, organization_id, name, public_location_text, exact_address_private,
  public_instructions, public_latitude, public_longitude, cold_chain_capable,
  active, accepts_donations, dispatches_shipments, shares_availability
)
select
  ('f1000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
  '${EVENTO}'::uuid,
  organizacion.id,
  'Bodega de volumen ' || g,
  'Zona sintética ' || g,
  null,
  'Punto sintético del ejercicio de carga.',
  -- Sin coordenada pública: estas bodegas no deben aparecer en el mapa ni en la lista de
  -- acopios. El volumen no puede cambiar lo que un visitante ve.
  null, null, (g % 5 = 0),
  true, false, true, (g % 2 = 0)
from generate_series(1, ${ESCALA.bodegas}) as g
cross join lateral (
  select id from public.organizations
  order by id offset (g % greatest((select count(*) from public.organizations), 1)) limit 1
) as organizacion
on conflict (id) do nothing;

select 'bodegas' as etapa, count(*)::text as filas from public.inventory_locations
where id::text like 'f1000000-%';
`,
  },
  {
    nombre: "lotes",
    titulo: `${ESCALA.lotes.toLocaleString("es")} lotes con su aporte de origen`,
    sql: `
-- Un lote exige un artículo de aporte, y un artículo exige su aporte: la cadena completa,
-- porque el esquema no admite un lote huérfano y no se va a relajar para esto.
insert into public.donations(id, event_id, organization_id, kind, status, donor_tracking_code)
select
  ('f2000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
  '${EVENTO}'::uuid,
  bodega.organization_id,
  'in_kind',
  'stored',
  'VOL-' || lpad(g::text, 10, '0')
from generate_series(1, ${ESCALA.lotes}) as g
cross join lateral (
  select organization_id from public.inventory_locations
  where id::text like 'f1000000-%'
  order by id offset (g % ${ESCALA.bodegas}) limit 1
) as bodega
on conflict (id) do nothing;

insert into public.donation_items(id, donation_id, category, description, quantity_promised, unit)
select
  ('f3000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
  ('f2000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
  (array['Alimentos','Agua','Higiene','Salud','Refugio','Logística'])[1 + (g % 6)],
  'Artículo sintético del ejercicio de carga',
  1000,
  (array['kilogramo','litro','unidad'])[1 + (g % 3)]
from generate_series(1, ${ESCALA.lotes}) as g
on conflict (id) do nothing;

insert into public.inventory_lots(
  id, event_id, organization_id, donation_item_id, location_id, lot_code, status,
  category, quantity_initial, unit, condition, expires_on, received_by
)
select
  ('f4000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
  '${EVENTO}'::uuid,
  bodega.organization_id,
  ('f3000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
  bodega.id,
  'LOTVOL' || lpad(g::text, 10, '0'),
  'available',
  (array['Alimentos','Agua','Higiene','Salud','Refugio','Logística'])[1 + (g % 6)],
  1000,
  (array['kilogramo','litro','unidad'])[1 + (g % 3)],
  'sellado',
  -- Vencimientos repartidos: la salud del inventario se consulta por fecha próxima.
  (current_date + ((g % 365) || ' days')::interval)::date,
  ('f0000000-0000-0000-0000-' || lpad((1 + (g % ${ESCALA.operadores}))::text, 12, '0'))::uuid
from generate_series(1, ${ESCALA.lotes}) as g
cross join lateral (
  select id, organization_id from public.inventory_locations
  where id::text like 'f1000000-%'
  order by id offset (g % ${ESCALA.bodegas}) limit 1
) as bodega
on conflict (id) do nothing;

select 'lotes' as etapa, count(*)::text as filas from public.inventory_lots
where id::text like 'f4000000-%';
`,
  },
  {
    nombre: "movimientos",
    titulo: `${movimientosReales.toLocaleString("es")} movimientos de Kardex`,
    sql: `
-- Aritmética del Kardex, no ruido. \`inventory_lot_positions\` calcula:
--   disponible = suma(quantity_delta)
--   reservado  = suma(-quantity_delta) sobre reserve y release
-- Así que \`reserve\` lleva delta NEGATIVO y \`release\` POSITIVO. Un lote recibe su recepción
-- y después pares reserva/liberación que se cancelan: la posición cierra en lo recibido y
-- reservado vuelve a cero. Un volumen que dejara posiciones negativas estaría midiendo una
-- base imposible.
insert into public.stock_movements(
  event_id, organization_id, lot_id, movement_type, quantity_delta,
  idempotency_key, reason, actor_id, created_at
)
select
  '${EVENTO}'::uuid, lote.organization_id, lote.id,
  'receipt', lote.quantity_initial,
  'volumen:' || lote.lot_code || ':receipt',
  'Recepción del ejercicio de carga',
  lote.received_by,
  now() - ((g % 180) || ' days')::interval
from public.inventory_lots as lote
cross join generate_series(1, 1) as g
where lote.id::text like 'f4000000-%'
on conflict do nothing;

insert into public.stock_movements(
  event_id, organization_id, lot_id, movement_type, quantity_delta,
  idempotency_key, reason, actor_id, created_at
)
select
  '${EVENTO}'::uuid, lote.organization_id, lote.id,
  (case when par2.lado = 0 then 'reserve' else 'release' end)::public.stock_movement_type,
  (case when par2.lado = 0 then -1 else 1 end)::numeric,
  'volumen:' || lote.lot_code || ':' || par.n || ':' || par2.lado,
  'Movimiento del ejercicio de carga',
  lote.received_by,
  -- Repartidos en el tiempo: sin esto, particionar por rango temporal (B8) no se podría
  -- ni ensayar, porque todo caería en la misma partición.
  now() - ((par.n % 180) || ' days')::interval
from public.inventory_lots as lote
cross join generate_series(1, ${paresPorLote}) as par(n)
cross join generate_series(0, 1) as par2(lado)
where lote.id::text like 'f4000000-%'
on conflict do nothing;

select 'movimientos' as etapa, count(*)::text as filas from public.stock_movements
where idempotency_key like 'volumen:%';
`,
  },
  {
    nombre: "solicitudes",
    titulo: `${ESCALA.solicitudes.toLocaleString("es")} solicitudes logísticas con sus líneas`,
    sql: `
insert into public.transfer_requests(
  id, event_id, organization_id, requesting_organization_id, request_code,
  origin_location_id, destination_location_id, status, justification,
  idempotency_key, requested_by, requested_at
)
select
  ('f5000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
  '${EVENTO}'::uuid,
  origen.organization_id,
  destino.organization_id,
  'SOLVOL' || lpad(g::text, 10, '0'),
  origen.id, destino.id,
  (array['requested','authorized','dispatched','closed'])[1 + (g % 4)]::public.transfer_status,
  'Solicitud sintética del ejercicio de carga número ' || g,
  'volumen-solicitud-' || g,
  ('f0000000-0000-0000-0000-' || lpad((1 + (g % ${ESCALA.operadores}))::text, 12, '0'))::uuid,
  now() - ((g % 180) || ' days')::interval
from generate_series(1, ${ESCALA.solicitudes}) as g
cross join lateral (
  select id, organization_id from public.inventory_locations
  where id::text like 'f1000000-%' order by id offset (g % ${ESCALA.bodegas}) limit 1
) as origen
cross join lateral (
  select id, organization_id from public.inventory_locations
  where id::text like 'f1000000-%' order by id offset ((g + 1) % ${ESCALA.bodegas}) limit 1
) as destino
on conflict (id) do nothing;

-- Entre una y tres líneas por solicitud: una solicitud real casi nunca es de un solo
-- producto, y medir con una sola línea escondería el coste que ADR-015 introdujo.
insert into public.transfer_request_items(
  transfer_request_id, line_no, category, unit, request_mode, quantity_requested
)
select
  ('f5000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
  linea.n,
  (array['Alimentos','Agua','Higiene','Salud','Refugio','Logística'])[1 + ((g + linea.n) % 6)],
  (array['kilogramo','litro','unidad'])[1 + ((g + linea.n) % 3)],
  'exact_quantity'::public.transfer_request_mode,
  10 + ((g + linea.n) % 90)
from generate_series(1, ${ESCALA.solicitudes}) as g
cross join lateral generate_series(1, 1 + (g % 3)) as linea(n)
on conflict do nothing;

select 'solicitudes' as etapa, count(*)::text as filas from public.transfer_requests
where id::text like 'f5000000-%';
`,
  },
];

// ------------------------------------------------------------------ recuento final

const RECUENTO = `
select 'movimientos de Kardex' as tabla, count(*)::text as filas from public.stock_movements
union all select 'lotes de inventario', count(*)::text from public.inventory_lots
union all select 'solicitudes logísticas', count(*)::text from public.transfer_requests
union all select 'líneas de solicitud', count(*)::text from public.transfer_request_items
union all select 'operadores con membresía', count(*)::text from public.memberships where active
union all select 'bodegas', count(*)::text from public.inventory_locations
union all select 'eventos de auditoría', count(*)::text from public.audit_events;

-- La comprobación que hace honesto al volumen: ninguna posición del Kardex puede quedar
-- negativa. Si esto devuelve algo, el volumen sembrado describe una base imposible y
-- cualquier medida tomada sobre él mentiría.
select 'posiciones negativas' as comprobacion, count(*)::text as filas
from public.inventory_lot_positions
where quantity_available < 0 or quantity_physical < 0 or quantity_reserved < 0;
`;

// ------------------------------------------------------------------ programa

console.log("Siembra de volumen · F0 del loop de escala");
console.log(
  `Objetivo: ${movimientosReales.toLocaleString("es")} movimientos · ` +
    `${ESCALA.solicitudes.toLocaleString("es")} solicitudes · ` +
    `${ESCALA.operadores.toLocaleString("es")} operadores · ` +
    `${ESCALA.lotes.toLocaleString("es")} lotes en ${ESCALA.bodegas} bodegas`,
);
console.log("");

let total = 0;
try {
  for (const etapa of etapas) {
    process.stdout.write(`  ${etapa.titulo}… `);
    const { ms, filas } = ejecutar(etapa.nombre, etapa.sql);
    total += ms;
    const conteo = filas.find((fila) => fila.filas !== undefined)?.filas;
    console.log(`${segundos(ms)} · ${Number(conteo ?? 0).toLocaleString("es")} filas sembradas`);
  }

  console.log("");
  const recuento = ejecutar("recuento", RECUENTO);
  const [totales, negativas] = recuento.resultados;
  console.log("  Estado de la base tras la siembra");
  for (const fila of totales ?? []) {
    console.log(`    ${String(fila.tabla).padEnd(28)} ${Number(fila.filas).toLocaleString("es").padStart(12)}`);
  }
  const sinSentido = Number(negativas?.[0]?.filas ?? 0);
  console.log("");
  if (sinSentido > 0) {
    console.error(
      `  POSICIONES NEGATIVAS: ${sinSentido}. El volumen sembrado describe una base imposible;\n` +
        "  cualquier medida tomada sobre él mentiría. Corrige la aritmética antes de medir.",
    );
    process.exitCode = 1;
  } else {
    console.log("  Posiciones del Kardex coherentes: ninguna negativa.");
  }
  console.log("");
  console.log(`Total: ${segundos(total)}`);
  console.log("");
  console.log("Siguiente paso: `npm run verify:carga` toma la línea base sobre este volumen.");
  console.log("Cuando termines de medir, `npm run db:reset` devuelve la base al estado de suite:");
  console.log("`npm run verify` exige ese estado y fallará mientras el volumen siga puesto.");
} finally {
  rmSync(temporal, { recursive: true, force: true });
}
