// F0 del loop de escala · La línea base del camino caliente.
//
// Cronometra las consultas que la aplicación ejecuta de verdad al cargar sus pantallas más
// usadas, y falla si alguna se sale de su línea base. Sin esto, cualquier «lo optimicé» es
// una opinión: §5 del loop dice que ninguna optimización se acepta sin su línea base.
//
// CÓMO MIDE, Y POR QUÉ ASÍ
// -----------------------
// Mide con `EXPLAIN (ANALYZE, BUFFERS)` y lee el `Execution Time` que informa PostgreSQL.
// No mide con un cronómetro alrededor del proceso: arrancar la CLI cuesta más de un segundo
// y ahogaría por completo una consulta de cinco milisegundos. Lo que interesa es lo que
// tarda el motor, no lo que tarda Node en existir.
//
// Guarda además el **plan**: una consulta puede estar dentro de su tiempo y aun así recorrer
// la tabla entera porque hoy tiene pocas filas. `Seq Scan` sobre una tabla que crece es una
// bomba con fecha, y se anota aunque el tiempo pase.
//
// Va por `psql` dentro del contenedor y no por `supabase db query` porque necesita una
// SESIÓN: las funciones con compuerta leen `auth.uid()` del ajuste `request.jwt.claims`, y
// medirlas sin actor mediría una consulta que no devuelve nada. El nombre del contenedor se
// deriva de `project_id` en `supabase/config.toml`, no se incrusta.

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";

const raiz = resolve(import.meta.dirname, "..");
const LINEA_BASE = resolve(raiz, "docs", "carga", "linea-base.json");

// Margen sobre la línea base antes de dar por rota una consulta. Ni tan estrecho que el
// ruido de la máquina lo dispare, ni tan ancho que una regresión real quepa dentro.
const MARGEN = Number(process.env.CARGA_MARGEN ?? 1.5);
const REPETICIONES = Number(process.env.CARGA_REPETICIONES ?? 5);
// Techo por consulta. Lo que se pase de aqui no se cronometra: se declara agotado, que es
// una respuesta mas util que un numero enorme y mucho mas util que un arnes colgado.
const TECHO_MS = Number(process.env.CARGA_TECHO_MS ?? 20000);
// Suelo de ruido. Una consulta de 0,027 ms que pasa a 0,043 no ha empeorado: ha sido medida
// dos veces en una maquina que hace otras cosas. Sin este suelo, el margen relativo convierte
// el jitter en una puerta roja, y una puerta que se dispara sola deja de mirarse.
const RUIDO_MS = Number(process.env.CARGA_RUIDO_MS ?? 1);
const EVENTO = "10000000-0000-0000-0000-000000000001";

// ------------------------------------------------------------------ conexión

function contenedor() {
  const config = readFileSync(resolve(raiz, "supabase", "config.toml"), "utf8");
  const proyecto = /^\s*project_id\s*=\s*"([^"]+)"/m.exec(config)?.[1];
  if (!proyecto) throw new Error("No se pudo leer `project_id` de supabase/config.toml");
  return `supabase_db_${proyecto}`;
}

const CONTENEDOR = contenedor();

function psql(sql) {
  try {
    return execFileSync("docker", ["exec", "-i", CONTENEDOR, "psql", "-U", "postgres", "-d", "postgres", "-t", "-A", "-c", sql], {
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch (error) {
    const detalle = `${error.stdout ?? ""}${error.stderr ?? ""}`.trim();
    throw new Error(detalle || error.message);
  }
}

// ------------------------------------------------------------------ el catálogo
//
// Sale de leer qué consulta cada pantalla, no de imaginarlo. Las quince primeras son el
// camino caliente —lo que se ejecuta al abrir una pantalla— y las cuatro últimas son las
// búsquedas de idempotencia de B5, que corren en cada recepción y en cada reserva.

const ACTOR_BODEGA = `(select user_id from public.memberships where role = 'warehouse_operator' and active limit 1)`;
const ACTOR_ADMIN = `(select user_id from public.memberships where role = 'event_admin' and active limit 1)`;

const CATALOGO = [
  {
    id: "bodega:posiciones-kardex",
    grupo: "camino caliente",
    pantalla: "/operaciones/bodega",
    nota: "B6 · el Kardex se agrega entero en cada lectura",
    actor: ACTOR_BODEGA,
    sql: `select lot_id, lot_code, category, unit, status, organization_id, location_id,
                 quantity_physical, quantity_available, quantity_reserved,
                 quantity_in_transit, quantity_delivered
          from public.inventory_lot_positions where event_id = '${EVENTO}'`,
  },
  {
    id: "bodega:solicitudes-logisticas",
    grupo: "camino caliente",
    pantalla: "/operaciones/bodega",
    nota: "B6 · subconsulta correlacionada por línea de solicitud",
    actor: ACTOR_BODEGA,
    sql: `select * from public.logistics_requests('${EVENTO}')`,
  },
  {
    id: "bodega:disponibilidad-compartida",
    grupo: "camino caliente",
    pantalla: "/operaciones/bodega",
    nota: "atraviesa el tenant con compuerta explícita (ADR-016)",
    actor: ACTOR_BODEGA,
    sql: `select * from public.shared_stock_availability('${EVENTO}', null)`,
  },
  {
    id: "bodega:conciliacion-despachos",
    grupo: "camino caliente",
    pantalla: "/operaciones/bodega",
    nota: "líneas de conciliación de todos los despachos del evento",
    actor: ACTOR_BODEGA,
    sql: `select * from public.shipment_reconciliation_lines(null, '${EVENTO}')`,
  },
  {
    id: "bodega:asignaciones",
    grupo: "camino caliente",
    pantalla: "/operaciones/bodega",
    nota: "sin cota declarada (G-057)",
    actor: ACTOR_BODEGA,
    sql: `select a.id, a.quantity, a.status, a.organization_id, a.transfer_request_id,
                 l.lot_code, l.category, l.unit
          from public.allocations a
          left join public.inventory_lots l on l.id = a.lot_id
          where a.event_id = '${EVENTO}' order by a.created_at desc`,
  },
  {
    id: "bodega:despachos",
    grupo: "camino caliente",
    pantalla: "/operaciones/bodega",
    nota: "sin cota declarada (G-057)",
    actor: ACTOR_BODEGA,
    sql: `select s.id, s.shipment_code, s.status, s.public_destination, s.origin_location_id,
                 s.destination_location_id, s.transfer_request_id, s.transport_mode,
                 coalesce(sum(si.quantity), 0) as total
          from public.shipments s
          left join public.shipment_items si on si.shipment_id = s.id
          where s.event_id = '${EVENTO}' group by s.id order by s.created_at desc`,
  },
  {
    id: "bodega:entregas",
    grupo: "camino caliente",
    pantalla: "/operaciones/bodega",
    nota: "sin cota declarada (G-057)",
    actor: ACTOR_BODEGA,
    sql: `select d.id, d.status, d.quantity_delivered, d.quantity_damaged, d.quantity_missing,
                 s.shipment_code
          from public.deliveries d
          join public.shipments s on s.id = d.shipment_id
          where s.event_id = '${EVENTO}' order by d.created_at desc`,
  },
  {
    id: "bodega:aportes-por-recibir",
    grupo: "camino caliente",
    pantalla: "/operaciones/bodega",
    nota: "sin cota declarada (G-057)",
    actor: ACTOR_BODEGA,
    sql: `select di.id, di.category, di.description, di.quantity_promised, di.quantity_received,
                 di.quantity_rejected, di.unit, d.donor_tracking_code, d.status
          from public.donation_items di
          join public.donations d on d.id = di.donation_id
          where d.event_id = '${EVENTO}'`,
  },
  {
    id: "consola:necesidades-abiertas",
    grupo: "camino caliente",
    pantalla: "/operaciones",
    nota: "con cota de 8 declarada",
    actor: ACTOR_ADMIN,
    sql: `select n.id, n.tracking_code, n.category, n.status, n.created_at, n.priority_score
          from public.need_cases n
          where n.event_id = '${EVENTO}' and n.status in ('reported','in_verification','verified')
          order by n.created_at limit 8`,
  },
  {
    id: "consola:aportes-en-cola",
    grupo: "camino caliente",
    pantalla: "/operaciones",
    nota: "cola de verificación",
    actor: ACTOR_ADMIN,
    sql: `select i.id, i.tracking_code, i.kind, i.status, i.submitted_at, i.declared_amount
          from public.donation_intakes i
          where i.event_id = '${EVENTO}' order by i.submitted_at desc limit 12`,
  },
  {
    id: "consola:conteo-auditoria",
    grupo: "camino caliente",
    pantalla: "/operaciones",
    nota: "B8 · conteo sobre la tabla que más crece",
    actor: ACTOR_ADMIN,
    sql: `select count(*) from public.audit_events where event_id = '${EVENTO}'`,
  },
  {
    id: "tesoreria:saldo",
    grupo: "camino caliente",
    pantalla: "/operaciones/tesoreria",
    nota: "B10 · suma sin agrupar por moneda",
    actor: ACTOR_ADMIN,
    sql: `select * from public.treasury_balance('${EVENTO}')`,
  },
  {
    id: "portal:acopios-publicos",
    grupo: "camino caliente",
    pantalla: "/",
    nota: "ejecutable por anon · G-055 le añadió la compuerta de habilitación",
    actor: null,
    sql: `select * from public.public_collection_centers('${EVENTO}')`,
  },
  {
    id: "portal:necesidades-publicadas",
    grupo: "camino caliente",
    pantalla: "/",
    nota: "tabla legible por anon y en Realtime",
    actor: null,
    sql: `select id, category, summary, location_label, latitude, longitude, status
          from public.public_need_projections
          where event_id = '${EVENTO}' and published order by verified_at desc`,
  },
  {
    id: "portal:mapa-logistico",
    grupo: "camino caliente",
    pantalla: "/",
    nota: "proyección del mapa, legible por anon",
    actor: null,
    sql: `select source_type, public_code, label, origin_label, destination_label
          from public.public_logistics_projections
          where event_id = '${EVENTO}' and published`,
  },
  {
    id: "idempotencia:movimiento",
    grupo: "idempotencia (B5)",
    pantalla: "receive_donation",
    nota: "acotada por organización (ADR-023): el índice compuesto que ya existía pasa a servir",
    actor: null,
    sql: `select l.id from public.inventory_lots l
          join public.stock_movements s on s.lot_id = l.id
          where s.idempotency_key = 'volumen:LOTVOL0000009999:receipt'
            and s.organization_id = (
              select organization_id from public.inventory_lots where lot_code = 'LOTVOL0000009999'
            )`,
  },
  {
    id: "idempotencia:asignacion",
    grupo: "idempotencia (B5)",
    pantalla: "reserve_lot_quantity",
    nota: "acotada por la organización dueña del lote (ADR-023)",
    actor: null,
    sql: `select existing.id from public.allocations as existing
          where existing.idempotency_key = 'no-existe-a-proposito'
            and existing.organization_id = '20000000-0000-0000-0000-000000000001'`,
  },
  {
    id: "idempotencia:despacho",
    grupo: "idempotencia (B5)",
    pantalla: "create_shipment",
    nota: "acotada por la organización de la bodega de origen (ADR-023)",
    actor: null,
    sql: `select existing.id from public.shipments as existing
          where existing.idempotency_key = 'no-existe-a-proposito'
            and existing.organization_id = '20000000-0000-0000-0000-000000000001'`,
  },
  {
    id: "idempotencia:financiero",
    grupo: "idempotencia (B5)",
    pantalla: "reconcile_sandbox_payment",
    nota: "acotada por la organización del fondo (ADR-023)",
    actor: null,
    sql: `select id from public.financial_transactions
          where idempotency_key = 'no-existe-a-proposito'
            and organization_id = '20000000-0000-0000-0000-000000000001'`,
  },
];

// ------------------------------------------------------------------ medida

// Una sola sesión por medida: fija el actor, ejecuta el plan y devuelve el JSON. El `set` es
// local a la transacción para que una medida no contamine la siguiente.
function medirUna(entrada) {
  const fijarActor = entrada.actor
    ? `select set_config('request.jwt.claims', json_build_object('sub', ${entrada.actor}, 'role', 'authenticated')::text, true);`
    : `select set_config('request.jwt.claims', '{"role":"anon"}', true);`;
  // Techo obligatorio. Sin él, una consulta patológica —y la línea base existe justamente
  // para encontrarlas— cuelga el arnés en vez de reportarla, y una puerta que puede colgarse
  // no es una puerta. Pasarse del techo es un resultado, no un fallo del arnés.
  const sql =
    `begin; set local statement_timeout = '${TECHO_MS}ms'; ${fijarActor} ` +
    `explain (analyze, buffers, format json) ${entrada.sql}; rollback;`;
  let salida;
  try {
    salida = psql(sql);
  } catch (error) {
    if (/statement timeout|canceling statement due to statement timeout/i.test(error.message)) {
      return { ms: Number.POSITIVE_INFINITY, agotada: true, plan: null };
    }
    throw new Error(`No se pudo medir ${entrada.id}: ${error.message}`);
  }
  const inicio = salida.indexOf("[");
  if (inicio < 0) throw new Error(`No se obtuvo plan para ${entrada.id}:\n${salida.slice(0, 400)}`);
  const plan = JSON.parse(salida.slice(inicio, salida.lastIndexOf("]") + 1))[0];
  return {
    ms: plan["Execution Time"],
    planificacion: plan["Planning Time"],
    plan: plan.Plan,
    agotada: false,
  };
}

// Recorre el plan buscando los recorridos secuenciales, que son los que no escalan.
function recorridosSecuenciales(nodo, acumulado = []) {
  if (!nodo) return acumulado;
  if (nodo["Node Type"] === "Seq Scan") {
    acumulado.push({ tabla: nodo["Relation Name"], filas: nodo["Actual Rows"] });
  }
  for (const hijo of nodo.Plans ?? []) recorridosSecuenciales(hijo, acumulado);
  return acumulado;
}

function percentil(valores, p) {
  const ordenados = [...valores].sort((a, b) => a - b);
  return ordenados[Math.min(ordenados.length - 1, Math.floor((p / 100) * ordenados.length))];
}

// ------------------------------------------------------------------ programa

const escribir = process.argv.includes("--establecer-linea-base");
const base = existsSync(LINEA_BASE) ? JSON.parse(readFileSync(LINEA_BASE, "utf8")) : null;

if (!base && !escribir) {
  console.error(
    "No hay línea base todavía.\n" +
      "Siembra el volumen con `node scripts/seed-volumen.mjs` y después toma la primera medida con:\n" +
      "  node scripts/verify-carga.mjs --establecer-linea-base\n" +
      "Una medida tomada sobre la base de la suite, con cien filas, no es una línea base de nada.",
  );
  process.exit(1);
}

const volumen = JSON.parse(
  psql(
    `select json_build_object(
       'movimientos', (select count(*) from public.stock_movements),
       'lotes', (select count(*) from public.inventory_lots),
       'solicitudes', (select count(*) from public.transfer_requests),
       'auditoria', (select count(*) from public.audit_events),
       'operadores', (select count(*) from public.memberships where active)
     )`,
  ).trim(),
);

console.log("Línea base del camino caliente · F0");
console.log(
  `Volumen medido: ${volumen.movimientos.toLocaleString("es")} movimientos · ` +
    `${volumen.lotes.toLocaleString("es")} lotes · ${volumen.solicitudes.toLocaleString("es")} solicitudes · ` +
    `${volumen.auditoria.toLocaleString("es")} eventos de auditoría · ${volumen.operadores.toLocaleString("es")} operadores`,
);
console.log(`Cada consulta se ejecuta ${REPETICIONES} veces; se reporta la mediana y el p95.`);
console.log("");

const medidas = [];
for (const entrada of CATALOGO) {
  const tomas = [];
  let ultima;
  for (let i = 0; i < REPETICIONES; i += 1) {
    ultima = medirUna(entrada);
    tomas.push(ultima.ms);
    // Si la primera toma ya se pasa del techo, repetirla cuatro veces mas solo gasta minutos
    // para volver a saber lo mismo.
    if (ultima.agotada) break;
  }
  const agotada = tomas.some((valor) => !Number.isFinite(valor));
  medidas.push({
    id: entrada.id,
    grupo: entrada.grupo,
    pantalla: entrada.pantalla,
    nota: entrada.nota,
    agotada,
    mediana: agotada ? null : Number(percentil(tomas, 50).toFixed(3)),
    p95: agotada ? null : Number(percentil(tomas, 95).toFixed(3)),
    recorridos_secuenciales: agotada ? [] : recorridosSecuenciales(ultima.plan),
  });
}

// ------------------------------------------------------------------ informe

const anchoId = Math.max(...medidas.map((m) => m.id.length));
let roto = 0;
let agotadas = 0;
let grupoActual = "";

for (const medida of medidas) {
  if (medida.grupo !== grupoActual) {
    grupoActual = medida.grupo;
    console.log(`  ${grupoActual.toUpperCase()}`);
  }
  if (medida.agotada) {
    console.log(
      `    ${medida.id.padEnd(anchoId)}  AGOTADA · no termina en ${(TECHO_MS / 1000).toFixed(0)} s  ← ${medida.nota}`,
    );
    agotadas += 1;
    continue;
  }
  const previa = base?.medidas?.find((m) => m.id === medida.id);
  let veredicto = "";
  if (previa && previa.p95 !== null) {
    const techo = Math.max(previa.p95 * MARGEN, previa.p95 + RUIDO_MS);
    if (medida.p95 > techo) {
      veredicto = `  ROTA · línea base p95 ${previa.p95} ms, techo ${techo.toFixed(3)} ms`;
      roto += 1;
    } else {
      const delta = ((medida.p95 - previa.p95) / Math.max(previa.p95, 0.001)) * 100;
      veredicto = `  (base ${previa.p95} ms · ${delta >= 0 ? "+" : ""}${delta.toFixed(0)} %)`;
    }
  }
  const seq = medida.recorridos_secuenciales.length
    ? `  Seq Scan: ${medida.recorridos_secuenciales.map((s) => `${s.tabla} (${s.filas.toLocaleString("es")} filas)`).join(", ")}`
    : "";
  console.log(
    `    ${medida.id.padEnd(anchoId)}  p95 ${String(medida.p95).padStart(9)} ms  ` +
      `mediana ${String(medida.mediana).padStart(9)} ms${veredicto}`,
  );
  if (seq) console.log(`    ${" ".repeat(anchoId)}  ${seq}`);
}

console.log("");
const lentas = medidas.filter((m) => !m.agotada && m.p95 > 200);
console.log(
  `  ${medidas.length} consultas medidas · ${agotadas} agotan el techo de ${(TECHO_MS / 1000).toFixed(0)} s · ` +
    `${lentas.length} entre 200 ms y el techo`,
);
console.log(`  La puerta de F3 exige p95 por debajo de 200 ms: hoy la incumplen ${agotadas + lentas.length}.`);
const conSeq = medidas.filter((m) => m.recorridos_secuenciales.length);
console.log(`  ${conSeq.length} con al menos un recorrido secuencial en su plan`);

if (escribir) {
  mkdirSync(dirname(LINEA_BASE), { recursive: true });
  writeFileSync(
    LINEA_BASE,
    `${JSON.stringify({ tomada: new Date().toISOString(), volumen, margen: MARGEN, medidas }, null, 2)}\n`,
    "utf8",
  );
  console.log("");
  console.log(`  Línea base escrita en docs/carga/linea-base.json`);
  console.log("  A partir de ahora `npm run verify:carga` falla si una consulta se sale de ella.");
} else if (roto > 0) {
  console.error("");
  console.error(`  ${roto} consulta(s) por encima de su línea base. La puerta de carga está ROJA.`);
  process.exitCode = 1;
} else {
  console.log("");
  console.log("  Ninguna consulta se salió de su línea base.");
}
