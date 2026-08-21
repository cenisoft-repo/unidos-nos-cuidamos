/*
 * Fase 16 del loop: dos personas reservan al mismo tiempo contra la misma existencia.
 *
 * Con 25 unidades disponibles y dos reservas simultáneas de 20, solo una puede
 * completarse. La garantía no vive en el formulario —dos pestañas abiertas la
 * esquivarían— sino en la transacción: `reserve_lot_quantity` toma el lote con
 * `select ... for update` y recalcula lo disponible desde el Kardex ya con el
 * bloqueo puesto, así que la segunda operación ve la existencia que dejó la primera.
 *
 * El escenario se monta por el recorrido real —aporte, aprobación, recepción— para
 * que el lote nazca del Kardex y no de una inserción a mano.
 */
import assert from "node:assert/strict";
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
assert.ok(url && key, "Faltan variables públicas de Supabase local");

const EVENT_ID = "10000000-0000-0000-0000-000000000001";
const ALLY_ORGANIZATION_ID = "20000000-0000-0000-0000-000000000002";
const ALLY_WAREHOUSE_ID = "70000000-0000-0000-0000-000000000002";
const WATER_NEED_ITEM_ID = "61000000-0000-0000-0000-000000000001";
const PASSWORD = "RutaSolidaria2026!";

async function signedIn(email) {
  const supabase = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const { error } = await supabase.auth.signInWithPassword({ email, password: PASSWORD });
  assert.equal(error, null, `La cuenta ${email} debe autenticar: ${error?.message ?? ""}`);
  return supabase;
}

const ally = await signedIn("aliado@rutasolidaria.local");
const coordination = await signedIn("admin@rutasolidaria.local");
const warehouse = await signedIn("bodega@rutasolidaria.local");

// ---------------------------------------------------------------- escenario --
const { data: catalogVersions, error: catalogError } = await ally.rpc("current_donation_catalog_versions");
assert.equal(catalogError, null, `Los catálogos deben estar disponibles: ${catalogError?.message ?? ""}`);

const suffix = crypto.randomUUID();
const { data: intakeRows, error: intakeError } = await ally.rpc("submit_donation_intake_v2", {
  p_event_id: EVENT_ID,
  p_organization_id: ALLY_ORGANIZATION_ID,
  p_kind: "in_kind",
  p_idempotency_key: `reserva-${suffix}`,
  p_donor_name_private: "Donante sintético de concurrencia",
  p_contact_private: { email: "reserva@example.invalid", phone: "" },
  p_attribution_kind: "anonymous",
  p_public_attribution: "",
  p_attribution_authorized: false,
  p_declared_status: "entregada",
  p_items: [{
    category: "Agua",
    category_code: "agua_potable",
    description: "Botellas selladas para la prueba de reserva concurrente",
    quantity: 25,
    unit: "unidad",
    condition: "sellado",
    storage_requirement: "ambiente",
    expires_on: null,
    declared_estimated_value_cop: null,
  }],
  p_declared_amount: null,
  p_preferred_location_id: ALLY_WAREHOUSE_ID,
  p_reporting_context: {
    donor_type: "empresa",
    economic_sector: "tecnologia",
    specific_destination: false,
    estimated_beneficiaries: "",
    internal_contact: {},
  },
  p_catalog_versions: catalogVersions,
  p_declared_category_code: null,
  p_need_case_id: null,
});
assert.equal(intakeError, null, `El aporte de montaje debe registrarse: ${intakeError?.message ?? ""}`);
const intakeId = (Array.isArray(intakeRows) ? intakeRows[0] : intakeRows)?.intake_id;
assert.ok(intakeId, "El aporte de montaje debe devolver un identificador");

const { error: reviewError } = await coordination.rpc("review_donation_intake", {
  p_intake_id: intakeId,
  p_decision: "approve",
  p_note: "Aprobado para la prueba de reserva concurrente",
});
assert.equal(reviewError, null, `La aprobación de montaje debe pasar: ${reviewError?.message ?? ""}`);

const { data: donationItems, error: itemsError } = await coordination
  .from("donation_items")
  .select("id,quantity_promised,donations!inner(intake_id)")
  .eq("donations.intake_id", intakeId);
assert.equal(itemsError, null, `Los artículos aprobados deben ser legibles: ${itemsError?.message ?? ""}`);
assert.equal(donationItems.length, 1, "El aporte de montaje tiene un solo artículo");
const donationItemId = donationItems[0].id;

const { data: lotId, error: receiveError } = await warehouse.rpc("receive_donation", {
  p_donation_item_id: donationItemId,
  p_location_id: ALLY_WAREHOUSE_ID,
  p_accepted: 25,
  p_rejected: 0,
  p_condition: "sellado",
  p_idempotency_key: `recepcion-${suffix}`,
});
assert.equal(receiveError, null, `La recepción de montaje debe pasar: ${receiveError?.message ?? ""}`);
assert.ok(lotId, "La recepción debe crear el lote");

async function available() {
  const { data, error } = await coordination.from("stock_movements").select("quantity_delta").eq("lot_id", lotId);
  assert.equal(error, null, `El Kardex del lote debe ser legible: ${error?.message ?? ""}`);
  return data.reduce((total, row) => total + Number(row.quantity_delta), 0);
}

assert.equal(await available(), 25, "El lote nace con 25 unidades disponibles en el Kardex");

// ------------------------------------------------------ reservas simultáneas --
const [first, second] = await Promise.all([
  warehouse.rpc("allocate_stock", {
    p_lot_id: lotId,
    p_need_item_id: WATER_NEED_ITEM_ID,
    p_quantity: 20,
    p_idempotency_key: `reserva-a-${suffix}`,
  }),
  coordination.rpc("allocate_stock", {
    p_lot_id: lotId,
    p_need_item_id: WATER_NEED_ITEM_ID,
    p_quantity: 20,
    p_idempotency_key: `reserva-b-${suffix}`,
  }),
]);

const outcomes = [first, second];
const granted = outcomes.filter((result) => result.error === null);
const refused = outcomes.filter((result) => result.error !== null);

assert.equal(granted.length, 1, "Exactamente una de las dos reservas simultáneas puede completarse");
assert.equal(refused.length, 1, "La otra tiene que ser rechazada, no silenciada");
assert.match(
  refused[0].error.message,
  /Existencia insuficiente/,
  `La reserva perdedora debe rechazarse por existencia, no por otro motivo: ${refused[0].error.message}`,
);
assert.ok(granted[0].data, "La reserva ganadora devuelve su asignación");

assert.equal(await available(), 5, "El Kardex queda con las 5 unidades que sobran, no con -15");

const { data: allocations, error: allocationsError } = await coordination
  .from("allocations")
  .select("id,quantity")
  .eq("lot_id", lotId);
assert.equal(allocationsError, null);
assert.equal(allocations.length, 1, "Solo queda una asignación registrada contra el lote");
assert.equal(Number(allocations[0].quantity), 20, "La asignación conserva la cantidad reservada");

// El reintento de la operación ganadora es idempotente: no vuelve a descontar.
const { data: retryId, error: retryError } = await warehouse.rpc("allocate_stock", {
  p_lot_id: lotId,
  p_need_item_id: WATER_NEED_ITEM_ID,
  p_quantity: 20,
  p_idempotency_key: granted[0] === first ? `reserva-a-${suffix}` : `reserva-b-${suffix}`,
});
assert.equal(retryError, null, "Reintentar con la misma clave no debe fallar");
assert.equal(retryId, granted[0].data, "El reintento devuelve la misma asignación");
assert.equal(await available(), 5, "El reintento no descuenta una segunda vez");

/*
 * Segunda garantía: la misma existencia, pedida a la vez por dos solicitudes logísticas en
 * modo «todo lo disponible». Aquí la cantidad no la escribe nadie: la resuelve la base al
 * autorizar. Si la resolviera antes de bloquear, las dos autorizaciones verían el mismo
 * saldo y reservarían el doble de lo que hay. Se autorizan simultáneamente desde dos
 * sesiones distintas, que es como ocurriría de verdad.
 */
const REQUEST_ORIGIN_ID = "70000000-0000-0000-0000-000000000001";
const requester = await signedIn("manizales@rutasolidaria.local");

const { data: sharedRows, error: sharedError } = await requester.rpc("shared_stock_availability", {
  p_event_id: EVENT_ID,
  p_category: "Refugio",
});
assert.equal(sharedError, null, `La disponibilidad compartida debe consultarse: ${sharedError?.message ?? ""}`);
const compartida = (sharedRows ?? []).find((row) => row.location_id === REQUEST_ORIGIN_ID);
assert.ok(compartida, "La bodega proveedora publica su disponibilidad de refugio");
const disponibleAntes = Number(compartida.quantity_available);
assert.ok(disponibleAntes > 0, "Hay existencia sobre la que competir");

async function pedirTodoLoDisponible(marca) {
  const { data, error } = await requester.rpc("request_stock_transfer", {
    p_origin_location_id: REQUEST_ORIGIN_ID,
    p_destination_location_id: ALLY_WAREHOUSE_ID,
    p_items: [{ mode: "all_available", category: compartida.category, unit: compartida.unit }],
    p_justification: "Prueba sintética de dos autorizaciones simultáneas sobre la misma existencia.",
    p_need_case_id: null,
    p_need_item_id: null,
    p_idempotency_key: `traslado-${marca}-${suffix}`,
  });
  assert.equal(error, null, `La solicitud ${marca} debe crearse: ${error?.message ?? ""}`);
  return (Array.isArray(data) ? data[0] : data).request_id;
}

const primeraSolicitud = await pedirTodoLoDisponible("a");
const segundaSolicitud = await pedirTodoLoDisponible("b");

const [decisionA, decisionB] = await Promise.all([
  coordination.rpc("decide_stock_transfer", {
    p_request_id: primeraSolicitud,
    p_decision: "authorize",
    p_lines: null,
    p_note: "Autorización simultánea A",
  }),
  warehouse.rpc("decide_stock_transfer", {
    p_request_id: segundaSolicitud,
    p_decision: "authorize",
    p_lines: null,
    p_note: "Autorización simultánea B",
  }),
]);

const decisiones = [decisionA, decisionB];
const autorizadas = decisiones.filter((result) => result.error === null);
const rechazadas = decisiones.filter((result) => result.error !== null);
assert.equal(autorizadas.length, 1, "Solo una de las dos autorizaciones simultáneas puede reservar la existencia");
assert.equal(rechazadas.length, 1, "La otra tiene que rechazarse con su razón, no quedar autorizada y vacía");
assert.match(
  rechazadas[0].error.message,
  /No hay existencia disponible para autorizar/,
  `La autorización perdedora debe rechazarse por existencia: ${rechazadas[0].error.message}`,
);

const { data: lineasAutorizadas, error: lineasError } = await coordination
  .from("transfer_request_items")
  .select("quantity_authorized,transfer_request_id")
  .in("transfer_request_id", [primeraSolicitud, segundaSolicitud]);
assert.equal(lineasError, null, `Las líneas deben ser legibles: ${lineasError?.message ?? ""}`);
const totalAutorizado = lineasAutorizadas.reduce((total, row) => total + Number(row.quantity_authorized), 0);
assert.equal(
  totalAutorizado,
  disponibleAntes,
  `Entre las dos solicitudes no puede autorizarse más de lo que había: ${totalAutorizado} contra ${disponibleAntes}`,
);

const { data: quedaDisponible } = await requester.rpc("shared_stock_availability", {
  p_event_id: EVENT_ID,
  p_category: "Refugio",
});
const restante = (quedaDisponible ?? []).find((row) => row.location_id === REQUEST_ORIGIN_ID);
assert.equal(restante, undefined, "Tras reservarlo todo, la bodega deja de publicar existencia de esa categoría");

await Promise.all([ally.auth.signOut(), coordination.auth.signOut(), warehouse.auth.signOut(), requester.auth.signOut()]);
console.log(`RESERVATION CONCURRENCY PASS: 25 disponibles con dos reservas de 20 simultáneas dejan 5, y dos solicitudes «todo lo disponible» autorizadas a la vez reservan ${disponibleAntes}, nunca ${disponibleAntes * 2}`);
