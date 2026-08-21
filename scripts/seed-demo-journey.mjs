/*
 * Deja el recorrido de despacho con trabajo pendiente en cada etapa, para poder aprobar
 * en vivo sin esperar a que alguien cree algo primero.
 *
 * No inserta nada a mano: todo pasa por las mismas RPC que usa la aplicación, así que lo
 * sembrado es indistinguible de lo que hace una persona y deja la misma auditoría. Si una
 * regla lo rechaza, el sembrado falla — que es lo que se quiere: un atajo que evite las
 * validaciones no demostraría nada.
 *
 * Deja pendientes, en este orden:
 *   1. aportes esperando verificación
 *   2. aportes aprobados esperando recepción en bodega
 *   3. traslados esperando autorización
 *   4. despachos armados esperando salida
 *   5. despachos en movimiento esperando recepción en destino
 *
 * Uso (PowerShell):
 *   $env:DEMO_PROJECT_REF = '<ref del proyecto>'
 *   $env:DEMO_PASSWORD    = '<contrasena comun>'
 *
 * Si cada cuenta tiene la suya, en vez de DEMO_PASSWORD:
 *   $env:DEMO_ALLY_PASSWORD / DEMO_ADMIN_PASSWORD / DEMO_WAREHOUSE_PASSWORD
 *   node scripts/seed-demo-journey.mjs
 *
 * La clave publicable la obtiene el script del CLI de Supabase para no tener que pegarla:
 * es larga y algunas terminales la enmascaran, lo que produce un error que no se parece
 * en nada a su causa. Para un entorno local, se pueden pasar DEMO_SUPABASE_URL y
 * DEMO_SUPABASE_KEY directamente.
 *
 * Opcional: DEMO_COUNT (4 por defecto) y DEMO_ALLY / DEMO_ADMIN / DEMO_WAREHOUSE.
 */
import { execFileSync } from "node:child_process";
import { createClient } from "@supabase/supabase-js";

/*
 * La clave publicable no se pega a mano. Es una cadena larga y algunas terminales y
 * gestores de portapapeles la enmascaran al pegarla —sustituyen los caracteres por
 * viñetas—, y entonces el fallo aparece como un críptico «Cannot convert argument to a
 * ByteString» que no tiene nada que ver con la causa. Se le pide al CLI de Supabase, que
 * ya está autenticado en la máquina.
 */
function claveDelProyecto(ref) {
  const salida = execFileSync("npx", ["supabase", "projects", "api-keys", "--project-ref", ref, "-o", "json"], {
    encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], shell: process.platform === "win32",
  });
  const anon = JSON.parse(salida).find((c) => c.name === "anon");
  if (!anon?.api_key) throw new Error(`el proyecto ${ref} no devolvió una clave publicable`);
  return anon.api_key;
}

const ref = process.env.DEMO_PROJECT_REF;
let url = process.env.DEMO_SUPABASE_URL;
let key = process.env.DEMO_SUPABASE_KEY;
const password = process.env.DEMO_PASSWORD?.trim().replace(/^<(.*)>$/, "$1");
const count = Number(process.env.DEMO_COUNT ?? 4);

if (ref && !key) {
  url = url ?? `https://${ref}.supabase.co`;
  console.log(`Obteniendo la clave publicable de ${ref} con el CLI de Supabase...`);
  key = claveDelProyecto(ref);
}

const hayAlgunaClave = password
  || (process.env.DEMO_ALLY_PASSWORD && process.env.DEMO_ADMIN_PASSWORD && process.env.DEMO_WAREHOUSE_PASSWORD);
if (!url || !key || !hayAlgunaClave) {
  console.error("Falta configuración. Usa una de las dos formas:");
  console.error("  DEMO_PROJECT_REF=<ref> DEMO_PASSWORD=<clave>            (recomendado: toma la clave del CLI)");
  console.error("  DEMO_SUPABASE_URL=<url> DEMO_SUPABASE_KEY=<clave publicable> DEMO_PASSWORD=<clave>");
  process.exit(1);
}

// Si algo enmascaró la clave al pegarla, decirlo por su nombre en vez de fallar adentro.
if (!/^[ -~]+$/.test(key)) {
  console.error("La clave publicable trae caracteres que no son ASCII: casi seguro tu terminal la enmascaró al pegarla.");
  console.error("Usa DEMO_PROJECT_REF=vcgwfyhytzgyzicfbikf y deja que el script la obtenga solo.");
  process.exit(1);
}

/*
 * Cada cuenta puede tener su propia contrasena. En un proyecto provisionado desde cero no
 * tienen por que compartirla, y obligar a igualarlas solo para poder sembrar seria pedir
 * que se debilite el entorno para comodidad de una herramienta.
 */
/*
 * Los marcadores de posicion se pegan enteros mas a menudo de lo que parece: si el valor
 * viene envuelto en < >, casi seguro es eso y no una contrasena que empieza y termina en
 * signos de comparacion. Se limpia y se avisa, en vez de dejar que el servicio conteste
 * «Invalid login credentials» y perder cinco minutos buscando en el sitio equivocado.
 */
function limpiarClave(valor, nombre) {
  if (!valor) return valor;
  const podado = valor.trim();
  if (podado.startsWith("<") && podado.endsWith(">")) {
    console.warn(`   aviso: ${nombre} venia entre < >; se usa el contenido sin los signos.`);
    return podado.slice(1, -1);
  }
  return podado;
}

const CUENTAS = {
  aliado: {
    email: process.env.DEMO_ALLY ?? "aliado@rutasolidaria.local",
    password: limpiarClave(process.env.DEMO_ALLY_PASSWORD, "DEMO_ALLY_PASSWORD") ?? password,
  },
  admin: {
    email: process.env.DEMO_ADMIN ?? "admin@rutasolidaria.local",
    password: limpiarClave(process.env.DEMO_ADMIN_PASSWORD, "DEMO_ADMIN_PASSWORD") ?? password,
  },
  bodega: {
    email: process.env.DEMO_WAREHOUSE ?? "bodega@rutasolidaria.local",
    password: limpiarClave(process.env.DEMO_WAREHOUSE_PASSWORD, "DEMO_WAREHOUSE_PASSWORD") ?? password,
  },
};

const TRANSPORTE = {
  mode: "institucional",
  contact_name: "Conductor de demostración",
  contact_document: "CC-00000099",
  contact_phone: "6040000099",
  vehicle: "Camioneta institucional",
  plate: "DEM123",
  responsible: "Coordinación de bodega",
};

const marca = Date.now().toString(36);
const resumen = [];
let fallos = 0;

const anotar = (etapa, hechos) => { resumen.push({ etapa, hechos }); console.log(`  ${hechos ? "ok" : "--"} ${etapa}: ${hechos}`); };
const fallar = (donde, error) => { fallos += 1; console.error(`  !! ${donde}: ${error?.message ?? error}`); };

async function sesion(cuenta) {
  if (!cuenta.password) {
    throw new Error(`falta la contrasena de ${cuenta.email}: usa DEMO_PASSWORD o la variable propia de esa cuenta`);
  }
  const cliente = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const { error } = await cliente.auth.signInWithPassword({ email: cuenta.email, password: cuenta.password });
  if (error) throw new Error(`no se pudo entrar como ${cuenta.email}: ${error.message}`);
  return cliente;
}

const aliado = await sesion(CUENTAS.aliado);
const admin = await sesion(CUENTAS.admin);
const bodega = await sesion(CUENTAS.bodega);

// ------------------------------------------------------------------ descubrimiento --
const { data: eventos } = await admin.from("emergency_events").select("id,name").eq("status", "active").limit(1);
if (!eventos?.length) throw new Error("no hay un evento activo");
const EVENT_ID = eventos[0].id;

const { data: membresias } = await aliado.from("memberships")
  .select("organization_id").eq("event_id", EVENT_ID).eq("role", "partner_reporter").eq("active", true).limit(1);
const ALLY_ORG = membresias?.[0]?.organization_id;
if (!ALLY_ORG) throw new Error("la cuenta aliada no tiene membresía partner_reporter activa");

const { data: catalogos } = await aliado.rpc("donation_flow_catalogs");
const categorias = (catalogos ?? []).find((f) => f.key === "donation_categories")?.values_json ?? [];
const unidades = (catalogos ?? []).find((f) => f.key === "units")?.values_json ?? [];
const { data: versiones } = await aliado.rpc("current_donation_catalog_versions");
const { data: puntos } = await aliado.rpc("organization_delivery_points", { p_event_id: EVENT_ID, p_organization_id: ALLY_ORG });
if (!puntos?.length) throw new Error("la organización del aliado no tiene puntos de entrega activos");

const punto = puntos.find((p) => (p.accepts ?? []).length) ?? puntos[0];
const aceptadas = punto.accepts ?? [];
const elegida = categorias.find((c) => c.kind === "in_kind" && aceptadas.includes(c.parent_category))
  ?? categorias.find((c) => c.kind === "in_kind");
if (!elegida) throw new Error("no hay categorías en especie en el catálogo");
const CATEGORIA = elegida.parent_category;
const CATEGORIA_CODE = elegida.value;
const UNIDAD = typeof unidades[0] === "string" ? unidades[0] : unidades[0]?.value;

/*
 * Origen y destino tienen que ser dos bodegas distintas de la MISMA organización: una que
 * despache y otra que reciba. Se prueban todas las parejas y no solo la primera bodega que
 * despacha, porque en el sandbox la que despacha es justamente la que no recibe.
 */
const { data: ubicaciones } = await bodega.from("inventory_locations")
  .select("id,name,organization_id,accepts_donations,dispatches_shipments")
  .eq("event_id", EVENT_ID).eq("active", true);
function buscarPareja(lista) {
  for (const u of lista ?? []) {
    if (!u.dispatches_shipments) continue;
    const pareja = (lista ?? []).find((v) => v.organization_id === u.organization_id && v.accepts_donations && v.id !== u.id);
    if (pareja) return { origen: u, destino: pareja };
  }
  return { origen: null, destino: null };
}

let { origen, destino } = buscarPareja(ubicaciones);

/*
 * Un entorno provisionado desde cero suele tener un solo punto por organizacion, y sin dos
 * bodegas no hay eje bodega a bodega que mostrar. Se crea la que falta por la misma RPC
 * que usa /operaciones/centros, asi que nace versionada y auditada igual que si la hubiera
 * creado una persona. La existente queda como destino y la nueva como origen de salida.
 */
if (!origen) {
  const puntoAliado = (ubicaciones ?? []).find((u) => u.id === punto.id);
  if (!puntoAliado) {
    console.warn("   no se pudo ubicar el punto del aliado para crear su bodega de salida");
  } else {
    const { data: detalle } = await admin.from("inventory_locations")
      .select("public_latitude,public_longitude,public_location_text").eq("id", puntoAliado.id).single();
    console.log("   creando una bodega de salida para poder demostrar el traslado...");
    const { error: creaError } = await admin.rpc("manage_delivery_point", {
      p_location_id: null,
      p_event_id: EVENT_ID,
      p_organization_id: puntoAliado.organization_id,
      p_name: `Bodega de salida ${puntoAliado.name}`.slice(0, 120),
      p_public_location_text: detalle?.public_location_text ?? "Zona logistica",
      p_exact_address_private: "Direccion operativa de demostracion, sin valor logistico real",
      p_public_instructions: "Punto de salida para traslados entre bodegas.",
      p_public_latitude: detalle?.public_latitude != null ? Number(detalle.public_latitude) + 0.01 : null,
      p_public_longitude: detalle?.public_longitude != null ? Number(detalle.public_longitude) + 0.01 : null,
      p_cold_chain_capable: false,
      p_active: true,
      p_accepts_donations: false,
      p_dispatches_shipments: true,
      p_accepted_categories: [],
      p_idempotency_key: `demo-bodega-${marca}`,
    });
    if (creaError) {
      console.warn(`   no se pudo crear la bodega de salida: ${creaError.message}`);
    } else {
      const { data: recargadas } = await bodega.from("inventory_locations")
        .select("id,name,organization_id,accepts_donations,dispatches_shipments")
        .eq("event_id", EVENT_ID).eq("active", true);
      ({ origen, destino } = buscarPareja(recargadas));
    }
  }
}

console.log(`Evento: ${eventos[0].name}`);
console.log(`Aporta: ${CATEGORIA} (${CATEGORIA_CODE}) en ${UNIDAD} hacia «${punto.name}»`);
console.log(origen ? `Traslado: ${origen.name} → ${destino.name}` : "Traslado: SIN PAREJA DE BODEGAS");

// --------------------------------------------------------------------- utilidades --
async function crearAporte(sufijo, cantidad) {
  const { data, error } = await aliado.rpc("submit_donation_intake_v2", {
    p_event_id: EVENT_ID,
    p_organization_id: ALLY_ORG,
    p_kind: "in_kind",
    p_idempotency_key: `demo-${marca}-${sufijo}`,
    p_donor_name_private: `Donante de demostración ${sufijo}`,
    p_contact_private: { email: `demo-${sufijo}@example.invalid`, phone: "" },
    p_attribution_kind: "anonymous",
    p_public_attribution: "",
    p_attribution_authorized: false,
    p_declared_status: "entregada",
    p_items: [{
      category: CATEGORIA, category_code: CATEGORIA_CODE,
      description: `Carga de demostración ${sufijo}`, quantity: cantidad, unit: UNIDAD,
      condition: "sellado", storage_requirement: "ambiente", expires_on: null,
      declared_estimated_value_cop: null,
    }],
    p_declared_amount: null,
    p_preferred_location_id: punto.id,
    p_reporting_context: { donor_type: "empresa", specific_destination: false, internal_contact: {} },
    p_catalog_versions: versiones,
    p_declared_category_code: null,
    p_need_case_id: null,
  });
  if (error) throw error;
  return (Array.isArray(data) ? data[0] : data).intake_id;
}

async function aprobar(intakeId) {
  const { error } = await admin.rpc("review_donation_intake", {
    p_intake_id: intakeId, p_decision: "approve", p_note: "Aprobado para la jornada de demostración",
  });
  if (error) throw error;
}

async function articuloDe(intakeId) {
  const { data, error } = await admin.from("donation_items")
    .select("id,quantity_promised,donations!inner(intake_id)").eq("donations.intake_id", intakeId).limit(1);
  if (error) throw error;
  if (!data?.length) throw new Error("el aporte aprobado no produjo artículos");
  return data[0];
}

async function recibirEn(locationId, articulo, sufijo) {
  const { error } = await bodega.rpc("receive_donation", {
    p_donation_item_id: articulo.id, p_location_id: locationId,
    p_accepted: Number(articulo.quantity_promised), p_rejected: 0,
    p_condition: "sellado", p_idempotency_key: `demo-rec-${marca}-${sufijo}`,
  });
  if (error) throw error;
}

async function solicitarTraslado(sufijo, cantidad) {
  const { data, error } = await bodega.rpc("request_stock_transfer", {
    p_origin_location_id: origen.id, p_destination_location_id: destino.id,
    p_items: [{ mode: "exact_quantity", category: CATEGORIA, unit: UNIDAD, quantity: cantidad }],
    p_justification: `Reposición de ${CATEGORIA} para la jornada de demostración ${sufijo}`,
    p_need_case_id: null, p_need_item_id: null,
    p_idempotency_key: `demo-tr-${marca}-${sufijo}`,
  });
  if (error) throw error;
  return Array.isArray(data) ? data[0] : data;
}

// Autoriza lo pedido tal cual: sin líneas explícitas, cada línea se autoriza por su modo.
async function autorizarTraslado(requestId) {
  const { error } = await admin.rpc("decide_stock_transfer", {
    p_request_id: requestId, p_decision: "authorize",
    p_lines: null, p_note: "Autorizado para la demostración",
  });
  if (error) throw error;
}

// ---------------------------------------------------- 1. esperando verificación --
console.log("\n1. Aportes esperando verificación");
let hechos = 0;
for (let i = 0; i < count; i += 1) {
  try { await crearAporte(`v${i}`, 60); hechos += 1; } catch (e) { fallar("aporte por verificar", e); }
}
anotar("aportes por verificar", hechos);

// ------------------------------------------------------- 2. esperando recepción --
console.log("\n2. Aportes aprobados esperando recepción");
hechos = 0;
for (let i = 0; i < count; i += 1) {
  try { await aprobar(await crearAporte(`r${i}`, 60)); hechos += 1; } catch (e) { fallar("aporte por recibir", e); }
}
anotar("aportes aprobados por recibir", hechos);

if (!origen) {
  fallar("traslados", new Error("ninguna organización tiene dos bodegas distintas, una que despache y otra que reciba"));
} else {
  // Existencia en el origen: sin ella, autorizar un traslado no puede reservar nada.
  console.log("\n   (sembrando existencia en la bodega de origen)");
  let unidadesEnOrigen = 0;
  for (let i = 0; i < count; i += 1) {
    try {
      const intake = await crearAporte(`s${i}`, 200);
      await aprobar(intake);
      const articulo = await articuloDe(intake);
      await recibirEn(origen.id, articulo, `s${i}`);
      unidadesEnOrigen += Number(articulo.quantity_promised);
    } catch (e) { fallar("existencia de origen", e); }
  }
  console.log(`   existencia disponible en ${origen.name}: ${unidadesEnOrigen} ${UNIDAD}`);

  // --------------------------------------------- 3. esperando autorización --
  console.log("\n3. Traslados esperando autorización");
  hechos = 0;
  for (let i = 0; i < count; i += 1) {
    try { await solicitarTraslado(`a${i}`, 10); hechos += 1; } catch (e) { fallar("traslado por autorizar", e); }
  }
  anotar("traslados por autorizar", hechos);

  // ------------------------------------------------- 4. esperando salida --
  console.log("\n4. Despachos armados esperando salida");
  hechos = 0;
  for (let i = 0; i < count; i += 1) {
    try {
      const solicitud = await solicitarTraslado(`p${i}`, 10);
      await autorizarTraslado(solicitud.request_id);
      const { error: envioError } = await bodega.rpc("create_shipment", {
        p_allocation_id: null, p_transfer_request_id: solicitud.request_id,
        p_origin_location_id: origen.id, p_destination_location_id: destino.id,
        p_public_destination: null, p_transport: TRANSPORTE,
        p_idempotency_key: `demo-env-${marca}-p${i}`,
      });
      if (envioError) throw envioError;
      hechos += 1;
    } catch (e) { fallar("despacho por salir", e); }
  }
  anotar("despachos por salir", hechos);

  // ------------------------------------- 5. en movimiento esperando recepción --
  console.log("\n5. Despachos en movimiento esperando recepción en destino");
  hechos = 0;
  for (let i = 0; i < count; i += 1) {
    try {
      const solicitud = await solicitarTraslado(`m${i}`, 10);
      await autorizarTraslado(solicitud.request_id);
      const { data: envio, error: envioError } = await bodega.rpc("create_shipment", {
        p_allocation_id: null, p_transfer_request_id: solicitud.request_id,
        p_origin_location_id: origen.id, p_destination_location_id: destino.id,
        p_public_destination: null, p_transport: TRANSPORTE,
        p_idempotency_key: `demo-env-${marca}-m${i}`,
      });
      if (envioError) throw envioError;
      const shipmentId = typeof envio === "string" ? envio : envio?.id ?? envio;
      const { error: salidaError } = await bodega.rpc("dispatch_shipment", { p_shipment_id: shipmentId });
      if (salidaError) throw salidaError;
      const { error: movimientoError } = await bodega.rpc("advance_shipment", { p_shipment_id: shipmentId, p_next_state: "in_transit" });
      if (movimientoError) throw movimientoError;
      hechos += 1;
    } catch (e) { fallar("despacho en movimiento", e); }
  }
  anotar("despachos en movimiento", hechos);
}

console.log("\n" + "=".repeat(58));
for (const fila of resumen) console.log(`${String(fila.hechos).padStart(3)}  ${fila.etapa}`);
console.log(fallos ? `\n${fallos} problema(s) — ver arriba.` : "\nSin errores.");
await Promise.all([aliado.auth.signOut(), admin.auth.signOut(), bodega.auth.signOut()]);
if (fallos) process.exit(1);
