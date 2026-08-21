// Prueba de entrega: recorre el flujo completo sobre un entorno recién provisionado y
// comprueba que funciona con las cuentas, organizaciones y centros que se van a entregar.
//
// Solo usa las funciones que usa la aplicación, con la sesión del rol que corresponde. No
// escribe tablas directamente ni usa la clave administrativa, así que además de verificar
// que el recorrido avanza, verifica que los permisos entregados son suficientes y no más.
//
// Crea datos: una necesidad, dos aportes, un lote, un despacho, una entrega, una
// conciliación y un gasto. El historial es append-only y no se limpia. No lo ejecutes
// contra datos, fondos o actores reales.
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { createClient } from "@supabase/supabase-js";

const LOOPBACK = new Set(["127.0.0.1", "localhost", "::1"]);
const runId = randomUUID().slice(0, 8).toUpperCase();
const checks = [];

function fail(message) {
  throw new Error(message);
}

function requireEnv(name) {
  const value = process.env[name];
  if (!value) fail(`Falta la variable requerida ${name}`);
  return value;
}

function record(name, passed, detail = "") {
  checks.push({ name, passed });
  console.log(`${passed ? "  ok  " : " FALLA"} ${name}${detail ? ` · ${detail}` : ""}`);
  if (!passed) fail(`Falló la comprobación: ${name}`);
}

function value(label, result) {
  if (result.error) fail(`${label}: ${result.error.message}`);
  return result.data;
}

function denied(result) {
  return Boolean(result.error);
}

// Formato escrito por `bootstrap:environment`. Se lee solo para poder iniciar sesión con
// cada rol; ninguna contraseña se imprime ni se guarda en otro sitio.
function parseCredentials(contents) {
  const accounts = new Map();
  let current = null;
  for (const line of contents.split(/\r?\n/)) {
    const account = line.match(/^Cuenta:\s*([^\s(]+)/);
    if (account) current = { key: account[1] };
    const email = line.match(/^Correo:\s*(\S+)/);
    if (email && current) current.email = email[1];
    const password = line.match(/^Contraseña temporal:\s*(\S+)/);
    if (password && current) {
      current.password = password[1];
      accounts.set(current.key, current);
      current = null;
    }
  }
  return accounts;
}

const config = JSON.parse(await readFile(path.resolve(requireEnv("BOOTSTRAP_CONFIG_PATH")), "utf8"));
const supabaseUrl = requireEnv("SUPABASE_URL");
const publishableKey = requireEnv("SUPABASE_PUBLISHABLE_KEY");
const targetHost = new URL(supabaseUrl).hostname;
if (requireEnv("BOOTSTRAP_CONFIRM_TARGET") !== targetHost) {
  fail(`BOOTSTRAP_CONFIRM_TARGET debe repetir exactamente el host de destino (${targetHost}).`);
}
if (!LOOPBACK.has(targetHost) && process.env.BOOTSTRAP_ACKNOWLEDGE_REAL_EVENT !== "yes" && config.event?.simulated === false) {
  fail("El evento no está declarado como simulado. Esta prueba crea registros y requiere BOOTSTRAP_ACKNOWLEDGE_REAL_EVENT=yes.");
}
const credentials = parseCredentials(await readFile(path.resolve(requireEnv("BOOTSTRAP_CREDENTIALS_PATH")), "utf8"));
const eventId = config.event.id;

function client() {
  return createClient(supabaseUrl, publishableKey, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  });
}

async function sessionFor(key) {
  const account = credentials.get(key) ?? fail(`El archivo de accesos no trae la cuenta \`${key}\``);
  const session = client();
  const result = await session.auth.signInWithPassword({ email: account.email, password: account.password });
  if (result.error) fail(`Inicio de sesión de ${key}: ${result.error.message}`);
  return session;
}

// Los roles se deducen de la configuración, no de nombres fijos: un entorno puede llamar
// a sus cuentas como quiera mientras cubra los roles que el recorrido necesita.
function accountWithRole(role) {
  const account = (config.accounts ?? []).find((candidate) => (candidate.memberships ?? []).some((membership) => membership.roles.includes(role)));
  return account?.key ?? fail(`Ninguna cuenta declarada tiene el rol \`${role}\``);
}

const anon = client();
const admin = await sessionFor(accountWithRole("event_admin"));
const partner = await sessionFor(accountWithRole("partner_reporter"));
const warehouse = await sessionFor(accountWithRole("warehouse_operator"));
const requester = await sessionFor(accountWithRole("treasury_requester"));
const approver = await sessionFor(accountWithRole("treasury_approver"));

console.log(`\nRecorrido ${runId} sobre ${targetHost} · evento ${config.event.slug}\n`);

// ---------------------------------------------------------------- necesidad ciudadana

const needRows = value("reporte ciudadano", await anon.rpc("submit_need_report", {
  p_event_id: eventId,
  p_category: "Agua",
  p_description: `Ejercicio de entrega ${runId}: el punto temporal ficticio requiere agua potable para veinte hogares.`,
  p_public_location: `Zona de ensayo ${runId}`,
  p_quantity: 10,
  p_unit: "litro",
  p_exact_address_private: "",
  p_contact_private: {},
  p_bot_field: "",
}));
const needCode = (Array.isArray(needRows) ? needRows[0] : needRows)?.tracking_code;
record("Ciudadanía reporta una necesidad", /^NEC-[A-F0-9]{24}$/.test(needCode ?? ""), needCode);
record("El reporte no es legible para un visitante", denied(await anon.from("need_cases").select("id").eq("tracking_code", needCode)));

const need = value("necesidad", await admin.from("need_cases").select("id,status").eq("tracking_code", needCode).single());
const needItem = value("artículo de la necesidad", await admin.from("need_items").select("id,category,unit").eq("need_case_id", need.id).single());
value("verificación", await admin.rpc("review_need_case", { p_need_id: need.id, p_decision: "verify", p_note: `Verificación ${runId}`, p_confidence: 90, p_expires_at: null }));
value("publicación", await admin.rpc("review_need_case", { p_need_id: need.id, p_decision: "publish", p_note: `Publicación ${runId}`, p_confidence: 90, p_expires_at: null }));
const published = value("proyección pública", await anon.from("public_need_projections").select("published,covered_quantity").eq("source_need_id", need.id).single());
record("La necesidad verificada se publica sin datos privados", published.published === true && Number(published.covered_quantity) === 0);

// ---------------------------------------------------------------- aporte en especie

// `organization_delivery_points` no devuelve la organización porque el llamante ya la
// declara: aquí se resuelve desde la membresía `partner_reporter` de la configuración.
const partnerAccount = config.accounts.find((account) => account.key === accountWithRole("partner_reporter"));
const partnerMembership = partnerAccount.memberships.find((membership) => membership.roles.includes("partner_reporter"));
const partnerOrgId = config.organizations.find((organization) => organization.key === partnerMembership.organization).id;

const points = value("puntos del aliado", await partner.rpc("organization_delivery_points", {
  p_event_id: eventId,
  p_organization_id: partnerOrgId,
}));
const point = points.find((candidate) => (candidate.accepts ?? []).includes("Agua"))
  ?? fail("Ningún centro de acopio del aliado acepta la categoría Agua: el recorrido de ensayo no puede continuar");
record("El aliado ve un centro de acopio compatible", Boolean(point.id), point.name);

const catalogs = value("catálogos", await partner.rpc("donation_flow_catalogs"));
const versions = Object.fromEntries(catalogs.map((row) => [row.key, row.version]));

async function submitIntake(kind, extra) {
  const rows = value(`aporte ${kind}`, await partner.rpc("submit_donation_intake_v2", {
    p_event_id: eventId,
    p_organization_id: partnerOrgId,
    p_kind: kind,
    p_idempotency_key: `${runId}-${kind}`,
    p_donor_name_private: `Donante de ensayo ${runId}`,
    p_contact_private: { email: `${runId.toLowerCase()}@example.invalid`, phone: "" },
    p_attribution_kind: "anonymous",
    p_public_attribution: "",
    p_attribution_authorized: false,
    p_declared_status: "comprometida",
    p_items: extra.items ?? [],
    p_declared_amount: extra.amount ?? null,
    p_preferred_location_id: kind === "in_kind" ? point.id : null,
    p_reporting_context: {},
    p_catalog_versions: versions,
    p_declared_category_code: kind === "money" ? "apoyo_economico_recursos" : null,
    p_need_case_id: extra.needCaseId ?? null,
  }));
  return Array.isArray(rows) ? rows[0] : rows;
}

const inKind = await submitIntake("in_kind", {
  items: [{ category: "Agua", category_code: "agua_potable", description: `Botellas selladas ${runId}`, quantity: 10, unit: "litro", condition: "sellado", storage_requirement: "ambiente", declared_estimated_value_cop: null, expires_on: null }],
});
record("El aliado registra un aporte en especie", /^APO-[A-F0-9]{24}$/.test(inKind.tracking_code ?? ""), inKind.tracking_code);
record(
  "El aliado no puede aprobar su propio aporte",
  denied(await partner.rpc("review_donation_intake", { p_intake_id: inKind.intake_id, p_decision: "approve", p_note: "Intento que debe fallar" })),
);

const donationId = value("aprobación", await admin.rpc("review_donation_intake", { p_intake_id: inKind.intake_id, p_decision: "approve", p_note: `Aprobación ${runId}` }));
const donationItem = value("artículo operacional", await warehouse.from("donation_items").select("id").eq("donation_id", donationId).single());
record("Administración aprueba y se crea la donación operacional", Boolean(donationId));

// ---------------------------------------------------------------- bodega y logística

const receiveKey = `${runId}-receive`;
const lotId = value("recepción", await warehouse.rpc("receive_donation", {
  p_donation_item_id: donationItem.id, p_location_id: point.id, p_accepted: 10, p_rejected: 0, p_condition: "sellado", p_idempotency_key: receiveKey,
}));
const repeatedLotId = value("reintento de recepción", await warehouse.rpc("receive_donation", {
  p_donation_item_id: donationItem.id, p_location_id: point.id, p_accepted: 10, p_rejected: 0, p_condition: "sellado", p_idempotency_key: receiveKey,
}));
record("Bodega recibe y el reintento es idempotente", Boolean(lotId) && lotId === repeatedLotId);

record(
  "No se puede reservar más de lo que hay en el lote",
  denied(await warehouse.rpc("allocate_stock", { p_lot_id: lotId, p_need_item_id: needItem.id, p_quantity: 999, p_idempotency_key: `${runId}-overallocate` })),
);
const allocationId = value("asignación", await warehouse.rpc("allocate_stock", {
  p_lot_id: lotId, p_need_item_id: needItem.id, p_quantity: 10, p_idempotency_key: `${runId}-allocate`,
}));
record("El lote se reserva contra la necesidad publicada", Boolean(allocationId));

// ---------------------------------------------------------------- despacho

const dispatchPoints = value("puntos de despacho", await warehouse.rpc("organization_dispatch_points", {
  p_event_id: eventId, p_organization_id: partnerOrgId,
}));
const origin = dispatchPoints[0] ?? fail("Ningún punto de la organización está habilitado para despachar: el recorrido de ensayo no puede continuar");
record("Existe un punto habilitado como origen del despacho", Boolean(origin.id), origin.name);

const receptionOnly = points.find((candidate) => !dispatchPoints.some((dispatch) => dispatch.id === candidate.id));
if (receptionOnly) {
  record(
    "Un punto que solo recibe no puede usarse como origen",
    denied(await warehouse.rpc("create_shipment", {
      p_allocation_id: allocationId, p_transfer_request_id: null,
      p_origin_location_id: receptionOnly.id, p_destination_location_id: null,
      p_public_destination: `Zona de ensayo ${runId}`, p_transport: {
    mode: "transportadora", company: `Transportes de ensayo ${runId}`,
    contact_name: `Conductor ${runId}`, contact_document: `CC-${runId}`,
    contact_phone: "6040000000", vehicle: "Camión sencillo",
    plate: "ABC123", responsible: `Responsable ${runId}`,
  }, p_idempotency_key: `${runId}-badorigin`,
    })),
  );
} else {
  // Una comprobación omitida en silencio se lee como cobertura que no existe.
  console.log("  omitida  Un punto que solo recibe no puede usarse como origen · esta organización no declara ninguno");
}
record(
  "El destino público rechaza teléfonos, cuentas y enlaces",
  denied(await warehouse.rpc("create_shipment", {
    p_allocation_id: allocationId, p_transfer_request_id: null,
    p_origin_location_id: origin.id, p_destination_location_id: null,
    p_public_destination: "Entregar y llamar al 3001234567", p_transport: {
    mode: "transportadora", company: `Transportes de ensayo ${runId}`,
    contact_name: `Conductor ${runId}`, contact_document: `CC-${runId}`,
    contact_phone: "6040000000", vehicle: "Camión sencillo",
    plate: "ABC123", responsible: `Responsable ${runId}`,
  }, p_idempotency_key: `${runId}-baddestination`,
  })),
);

const shipmentKey = `${runId}-shipment`;
// Fase 12: un despacho puede prepararse sin saber quién lo lleva, pero no puede salir sin saberlo.
const shipmentId = value("despacho", await warehouse.rpc("create_shipment", {
  p_allocation_id: allocationId, p_transfer_request_id: null,
  p_origin_location_id: origin.id, p_destination_location_id: null,
  p_public_destination: `Zona de ensayo ${runId}`, p_transport: {}, p_idempotency_key: shipmentKey,
}));
record("Un despacho sin datos de transporte no puede salir", denied(await warehouse.rpc("dispatch_shipment", { p_shipment_id: shipmentId })));
value("transporte del despacho", await warehouse.rpc("set_shipment_transport", {
  p_shipment_id: shipmentId, p_transport: {
    mode: "transportadora", company: `Transportes de ensayo ${runId}`,
    contact_name: `Conductor ${runId}`, contact_document: `CC-${runId}`,
    contact_phone: "6040000000", vehicle: "Camión sencillo",
    plate: "ABC123", responsible: `Responsable ${runId}`,
  },
}));
const repeatedShipmentId = value("reintento de despacho", await warehouse.rpc("create_shipment", {
  p_allocation_id: allocationId, p_transfer_request_id: null,
  p_origin_location_id: origin.id, p_destination_location_id: null,
  p_public_destination: `Zona de ensayo ${runId}`, p_transport: {}, p_idempotency_key: shipmentKey,
}));
record("El despacho queda con origen registrado y el reintento es idempotente", Boolean(shipmentId) && shipmentId === repeatedShipmentId);

const shipmentRow = value("origen del despacho", await warehouse.from("shipments").select("origin_location_id,status,transport_plate,public_destination").eq("id", shipmentId).single());
record("El despacho conserva desde dónde salió", shipmentRow.origin_location_id === origin.id);
record("El despacho nace en preparación y no en movimiento", shipmentRow.status === "preparing");
record("La salida física exige el transporte completo", value("salida", await warehouse.rpc("dispatch_shipment", { p_shipment_id: shipmentId })) === "dispatched");
record("El seguimiento avanza a EN MOVIMIENTO", value("movimiento", await warehouse.rpc("advance_shipment", { p_shipment_id: shipmentId, p_next_state: "in_transit" })) === "in_transit");
record("El seguimiento registra la llegada", value("llegada", await warehouse.rpc("advance_shipment", { p_shipment_id: shipmentId, p_next_state: "arrived" })) === "arrived");
record("El transportador no viaja a la superficie pública", !("transport_plate" in (value("proyección logística", await anon.from("public_logistics_projections").select("*").eq("source_id", shipmentId).maybeSingle()) ?? {})));

// ---------------------------------------------------------------- entrega

// Se recibe producto a producto: la conciliación es por línea del despacho, no por una
// sola cifra que sumaría unidades distintas cuando el despacho lleva varios productos.
const shipmentLines = value("líneas del despacho", await warehouse.from("shipment_items").select("id,quantity").eq("shipment_id", shipmentId));
record(
  "La entrega debe conciliar con lo despachado",
  denied(await warehouse.rpc("register_delivery", {
    p_shipment_id: shipmentId,
    p_lines: shipmentLines.map((line) => ({ shipment_item_id: line.id, delivered: 3, damaged: 0, missing: 0 })),
    p_idempotency_key: `${runId}-baddelivery`,
  })),
);
const deliveryId = value("entrega", await warehouse.rpc("register_delivery", {
  p_shipment_id: shipmentId,
  p_lines: shipmentLines.map((line) => ({ shipment_item_id: line.id, delivered: Number(line.quantity), damaged: 0, missing: 0 })),
  p_idempotency_key: `${runId}-delivery`,
}));
const reconciliation = value("conciliación", await warehouse.rpc("shipment_reconciliation", { p_shipment_id: shipmentId }));
record("La conciliación declara CONFORME cuando lo recibido cuadra", (Array.isArray(reconciliation) ? reconciliation[0] : reconciliation)?.outcome === "CONFORME");
record("Se registra la entrega conciliada con el despacho", Boolean(deliveryId));
record(
  "Quien entrega no puede validar su propia entrega",
  denied(await warehouse.rpc("validate_delivery", { p_delivery_id: deliveryId, p_note: "Intento que debe fallar" })),
);
value("validación independiente", await admin.rpc("validate_delivery", { p_delivery_id: deliveryId, p_note: `Validación ${runId}` }));
const covered = value("cobertura publicada", await anon.from("public_need_projections").select("covered_quantity").eq("source_need_id", need.id).single());
record("La entrega validada mueve la cobertura pública", Number(covered.covered_quantity) === 10, `${covered.covered_quantity} litros`);

// ---------------------------------------------------------------- dinero y gasto

const fund = config.funds?.[0];
if (fund) {
  const money = await submitIntake("money", { amount: 250000 });
  record("El aliado declara un aporte económico", /^APO-[A-F0-9]{24}$/.test(money.tracking_code ?? ""), money.tracking_code);
  const moneyDonationId = value("aprobación económica", await admin.rpc("review_donation_intake", { p_intake_id: money.intake_id, p_decision: "approve", p_note: `Aprobación económica ${runId}` }));
  record(
    "El aliado no puede conciliar su propio aporte económico",
    denied(await partner.rpc("reconcile_money_donation", { p_donation_id: moneyDonationId, p_fund_id: fund.id, p_provider_reference_private: `INTENTO-${runId}`, p_idempotency_key: `${runId}-badreconcile` })),
  );
  const reconcileKey = `${runId}-reconcile`;
  const reconciled = value("conciliación", await approver.rpc("reconcile_money_donation", {
    p_donation_id: moneyDonationId, p_fund_id: fund.id, p_provider_reference_private: `SOPORTE-${runId}`, p_idempotency_key: reconcileKey,
  }));
  const repeatedReconcile = value("reintento de conciliación", await approver.rpc("reconcile_money_donation", {
    p_donation_id: moneyDonationId, p_fund_id: fund.id, p_provider_reference_private: `SOPORTE-${runId}`, p_idempotency_key: reconcileKey,
  }));
  const firstTx = (Array.isArray(reconciled) ? reconciled[0] : reconciled);
  const repeatTx = (Array.isArray(repeatedReconcile) ? repeatedReconcile[0] : repeatedReconcile);
  record("Tesorería concilia contra un soporte y el reintento no duplica el movimiento", firstTx.transaction_id === repeatTx.transaction_id && repeatTx.was_duplicate === true);

  const moneyProjection = value("proyección económica pública", await anon.from("public_donation_projections").select("reconciled_amount,published").eq("donation_id", moneyDonationId).single());
  record("El monto conciliado se publica sin la referencia privada del soporte", moneyProjection.published === true && Number(moneyProjection.reconciled_amount) === 250000);
  record(
    "La referencia privada del soporte no es legible para un visitante",
    denied(await anon.from("financial_transactions").select("provider_reference_private").eq("donation_id", moneyDonationId)),
  );

  const expenseId = value("solicitud de gasto", await requester.rpc("request_expense", { p_fund_id: fund.id, p_amount: 100000, p_purpose: `Gasto de ensayo ${runId}` }));
  record(
    "Quien solicita no puede aprobar su propia solicitud",
    denied(await requester.rpc("approve_expense", { p_expense_id: expenseId, p_decision: "approved", p_note: "Intento que debe fallar" })),
  );
  value("aprobación de gasto", await approver.rpc("approve_expense", { p_expense_id: expenseId, p_decision: "approved", p_note: `Aprobación ${runId}` }));
  record("La aprobación financiera está segregada de la solicitud", true);
}

// ---------------------------------------------------------------- trazabilidad

const tracked = value("seguimiento público", await anon.rpc("track_public_code", { p_tracking_code: inKind.tracking_code }));
record("El código de seguimiento responde sin exponer datos privados", tracked.length === 1 && !("contact_private" in tracked[0]));

// El punto que más importa: el APO del donante debe heredar el avance de su DON.
const journey = value("cadena de trazabilidad", await anon.rpc("track_public_journey", { p_tracking_code: inKind.tracking_code }));
const stages = journey.map((step) => step.stage_key);
for (const expected of ["intake_reported", "intake_approved", "donation_opened", "stock_received", "stock_allocated", "shipment_dispatched", "delivery_registered", "delivery_validated"]) {
  record(`El código del aporte muestra el hito «${expected}»`, stages.includes(expected));
}
record("Los hitos llegan en el orden del proceso", journey.every((entry, index) => index === 0 || entry.step >= journey[index - 1].step));
record("Cada hito trae su fecha", journey.every((entry) => Boolean(entry.occurred_at)));
record("Las cantidades se leen sin decimales colgando", journey.every((entry) => !/\d\.\s/.test(entry.detail)));
record(
  "La cadena expone el código operacional además del reportado",
  new Set(journey.map((step) => step.related_code)).size > 1,
);
const journeyText = JSON.stringify(journey);
record("La cadena no filtra transportador, dirección ni contacto", !journeyText.includes("Transporte de ensayo") && !journeyText.includes("@example.invalid"));

const needJourney = value("cadena de la necesidad", await anon.rpc("track_public_journey", { p_tracking_code: needCode }));
record("La necesidad ciudadana también tiene cadena comprobable", needJourney.map((step) => step.stage_key).includes("need_published"));

for (const session of [admin, partner, warehouse, requester, approver]) {
  await session.auth.signOut();
}

console.log(`\n${checks.length}/${checks.length} comprobaciones del recorrido en verde.`);
console.log("El entorno queda con los registros de ensayo creados: el historial es append-only y no se limpia.");
