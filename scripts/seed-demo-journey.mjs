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
 *   $env:DEMO_SUPABASE_URL = 'https://<ref>.supabase.co'
 *   $env:DEMO_SUPABASE_KEY = '<clave publicable>'
 *   $env:DEMO_PASSWORD     = '<contrasena de las cuentas del sandbox>'
 *   node scripts/seed-demo-journey.mjs
 *
 * Opcional: DEMO_COUNT (4 por defecto) y DEMO_ALLY / DEMO_ADMIN / DEMO_WAREHOUSE.
 */
import { createClient } from "@supabase/supabase-js";

const url = process.env.DEMO_SUPABASE_URL;
const key = process.env.DEMO_SUPABASE_KEY;
const password = process.env.DEMO_PASSWORD;
const count = Number(process.env.DEMO_COUNT ?? 4);

if (!url || !key || !password) {
  console.error("Faltan DEMO_SUPABASE_URL, DEMO_SUPABASE_KEY o DEMO_PASSWORD.");
  process.exit(1);
}

const CUENTAS = {
  aliado: process.env.DEMO_ALLY ?? "aliado@rutasolidaria.local",
  admin: process.env.DEMO_ADMIN ?? "admin@rutasolidaria.local",
  bodega: process.env.DEMO_WAREHOUSE ?? "bodega@rutasolidaria.local",
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

async function sesion(email) {
  const cliente = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const { error } = await cliente.auth.signInWithPassword({ email, password });
  if (error) throw new Error(`no se pudo entrar como ${email}: ${error.message}`);
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
let origen = null, destino = null;
for (const u of ubicaciones ?? []) {
  if (!u.dispatches_shipments) continue;
  const pareja = (ubicaciones ?? []).find((v) => v.organization_id === u.organization_id && v.accepts_donations && v.id !== u.id);
  if (pareja) { origen = u; destino = pareja; break; }
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
    p_category: CATEGORIA, p_unit: UNIDAD, p_quantity: cantidad,
    p_justification: `Reposición de ${CATEGORIA} para la jornada de demostración ${sufijo}`,
    p_idempotency_key: `demo-tr-${marca}-${sufijo}`,
  });
  if (error) throw error;
  return Array.isArray(data) ? data[0] : data;
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
      const { error: autorizaError } = await admin.rpc("decide_stock_transfer", {
        p_request_id: solicitud.request_id, p_decision: "authorize",
        p_quantity_authorized: 10, p_note: "Autorizado para la demostración",
      });
      if (autorizaError) throw autorizaError;
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
      const { error: autorizaError } = await admin.rpc("decide_stock_transfer", {
        p_request_id: solicitud.request_id, p_decision: "authorize",
        p_quantity_authorized: 10, p_note: "Autorizado para la demostración",
      });
      if (autorizaError) throw autorizaError;
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
