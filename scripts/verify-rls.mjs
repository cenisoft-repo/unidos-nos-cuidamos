import assert from "node:assert/strict";
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
assert.ok(url && key, "Faltan variables públicas de Supabase local");

function client() {
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

const anonymous = client();
const { data: publicNeeds, error: publicError } = await anonymous.from("public_need_projections").select("id");
assert.equal(publicError, null, "Anon debe leer proyecciones públicas");
assert.equal(publicNeeds.length, 2, "Anon solo ve las dos necesidades base publicadas");

const { data: publicMap, error: mapError } = await anonymous.rpc("public_need_map", {
  p_event_id: "10000000-0000-0000-0000-000000000001",
  p_min_longitude: -75.7,
  p_min_latitude: 6.1,
  p_max_longitude: -75.4,
  p_max_latitude: 6.4,
});
assert.equal(mapError, null, "Anon debe consultar la capa geoespacial pública");
assert.equal(publicMap.length, 1, "El encuadre PostGIS solo devuelve el punto público visible");
assert.equal("source_need_id" in publicMap[0], false, "La RPC geoespacial no filtra identificadores operacionales");

const { data: publicCenters, error: centerError } = await anonymous.rpc("public_collection_centers", {
  p_event_id: "10000000-0000-0000-0000-000000000001",
});
assert.equal(centerError, null, "Anon debe consultar centros públicos seguros");
/*
 * Antes esto fijaba el número de centros en 2 y se rompió cuando `202608170001`
 * promovió 21 aliados a puntos de acopio. Un conteo atado al seed no prueba
 * nada de privacidad y se cae con cada cambio de datos, así que se comprueban
 * las propiedades que sí importan y en TODAS las filas, no solo en la primera.
 *
 * `202608170002` decidió que la dirección de un acopio es pública —es un lugar
 * de entrega—, de modo que aquí se verifica que no se filtren las columnas
 * operacionales, no que la dirección esté oculta.
 */
assert.ok(publicCenters.length > 0, "La proyección pública de centros devuelve resultados");
const columnasOperacionales = ["exact_address_private", "organization_id", "event_id", "active", "created_at", "updated_at"];
for (const centro of publicCenters) {
  for (const columna of columnasOperacionales) {
    assert.equal(columna in centro, false, `La proyección de centros no expone ${columna}`);
  }
  assert.ok(centro.location_label?.length > 0, "Cada centro público declara dónde queda");
}
// La prueba real de RLS: la tabla operacional sigue cerrada a anónimo.
const { data: rawLocations } = await anonymous.from("inventory_locations").select("id").limit(1);
assert.equal(rawLocations?.length ?? 0, 0, "Anon no puede leer la tabla operacional de puntos");

const { data: publicLogistics, error: logisticsError } = await anonymous.rpc("public_logistics_map", {
  p_event_id: "10000000-0000-0000-0000-000000000001",
});
assert.equal(logisticsError, null, "Anon debe consultar la proyección logística pública");
assert.ok(
  publicLogistics.filter((row) => row.source_type === "collection_center").length > 0,
  "La logística pública contiene los centros activos",
);
/*
 * Unión de las dos ramas: la comprobación por propiedades en TODAS las filas
 * (no un conteo atado al seed, que se rompe cada vez que cambian los centros)
 * y el conjunto completo de columnas privadas que ninguna de las dos versiones
 * cubría entera: dirección exacta, transportador y placa.
 */
const columnasLogisticasPrivadas = ["exact_address_private", "carrier_name", "transport_plate", "transport_contact"];
for (const fila of publicLogistics) {
  for (const columna of columnasLogisticasPrivadas) {
    assert.equal(columna in fila, false, `La logística pública no expone ${columna}`);
  }
}

const { error: logisticsWriteError } = await anonymous.from("public_logistics_projections").insert({
  event_id: "10000000-0000-0000-0000-000000000001",
  source_type: "dispatch",
  source_id: crypto.randomUUID(),
  public_code: "DSP-ILEGAL",
  label: "Intento anónimo",
  status: "dispatched",
});
assert.ok(logisticsWriteError, "Anon no puede escribir la proyección logística");

const { error: operationalReadError } = await anonymous.from("need_cases").select("id");
assert.ok(operationalReadError, "Anon no debe leer la tabla operacional");

const partner = client();
const { error: signInError } = await partner.auth.signInWithPassword({ email: "aliado@rutasolidaria.local", password: "RutaSolidaria2026!" });
assert.equal(signInError, null, "La cuenta aliada sandbox debe autenticar");

const { data: partnerOrganizations, error: orgError } = await partner.from("organizations").select("id,slug");
assert.equal(orgError, null);
assert.deepEqual(partnerOrganizations.map((row) => row.slug), ["aliados-unidos-demo"], "RLS aísla la organización del aliado");

const { data: protectedFinance, error: financeError } = await partner.from("financial_transactions").select("id");
assert.equal(financeError, null);
assert.equal(protectedFinance.length, 0, "El aliado no puede leer finanzas de otra organización");

const { error: escalationError } = await partner.rpc("review_need_case", {
  p_need_id: "60000000-0000-0000-0000-000000000003",
  p_decision: "verify",
  p_note: "Intento no autorizado",
  p_confidence: 80,
  p_expires_at: null,
});
assert.ok(escalationError, "El aliado no puede elevar una necesidad a verificada");

/*
 * Escalamiento de privilegios (Fase 13). El aliado no puede administrar: ni asignarse
 * un rol, ni desactivar a nadie, ni tocar catálogos, ni leer el padrón de cuentas.
 * Se prueba contra la API real, con su sesión real, porque es ahí donde un cliente
 * alterado intentaría hacerlo.
 */
const { error: selfRoleError } = await partner.rpc("assign_membership_role", {
  p_user_id: "00000000-0000-0000-0000-000000000102",
  p_organization_id: "20000000-0000-0000-0000-000000000002",
  p_event_id: "10000000-0000-0000-0000-000000000001",
  p_role: "event_admin",
  p_active: true,
});
assert.ok(selfRoleError, "El aliado no puede asignarse un rol administrativo");

const { error: superRoleError } = await partner.rpc("assign_membership_role", {
  p_user_id: "00000000-0000-0000-0000-000000000102",
  p_organization_id: "20000000-0000-0000-0000-000000000002",
  p_event_id: "10000000-0000-0000-0000-000000000001",
  p_role: "super_admin",
  p_active: true,
});
assert.ok(superRoleError, "El aliado no puede concederse autoridad global");

const { error: grantExposedError } = await partner.rpc("grant_super_admin", {
  p_email: "aliado@rutasolidaria.local",
  p_organization_id: "20000000-0000-0000-0000-000000000002",
  p_event_id: "10000000-0000-0000-0000-000000000001",
  p_reason: "Intento desde el navegador",
});
assert.ok(grantExposedError, "La concesión de SUPER_ADMIN no está expuesta al cliente");

const { error: catalogWriteError } = await partner.rpc("manage_catalog_values", {
  p_key: "units",
  p_values: ["litro"],
  p_note: "Intento no autorizado",
});
assert.ok(catalogWriteError, "El aliado no puede modificar configuración");

const { data: partnerRoster } = await partner.rpc("platform_users_admin", {
  p_event_id: "10000000-0000-0000-0000-000000000001",
});
assert.equal(partnerRoster?.length ?? 0, 0, "El aliado no lee el padrón de cuentas");

const { data: partnerMemberships } = await partner.from("memberships").select("user_id,role");
assert.ok(
  (partnerMemberships ?? []).every((row) => row.user_id === "00000000-0000-0000-0000-000000000102"),
  "El aliado solo ve sus propias membresías",
);

await partner.auth.signOut();

/*
 * Alcance transversal de SUPER_ADMIN (Fase 12). No es un bypass: pasa por las mismas
 * políticas, con la misma sesión de PostgREST que cualquiera. Lo que cambia es que las
 * compuertas lo reconocen sin exigirle una membresía por organización.
 */
const platform = client();
const { error: superSignInError } = await platform.auth.signInWithPassword({
  email: "superadmin@rutasolidaria.local",
  password: "RutaSolidaria2026!",
});
assert.equal(superSignInError, null, "La cuenta de autoridad global debe autenticar");

const { data: allOrganizations, error: allOrgError } = await platform.from("organizations").select("id,slug");
assert.equal(allOrgError, null);
assert.ok(allOrganizations.length >= 2, "SUPER_ADMIN lee todas las organizaciones");
assert.ok(
  allOrganizations.some((row) => row.slug === "red-humanitaria-demo")
    && allOrganizations.some((row) => row.slug === "aliados-unidos-demo"),
  "SUPER_ADMIN atraviesa el aislamiento de tenant en lectura",
);

const { data: allLocations, error: allLocationsError } = await platform.from("inventory_locations").select("id,organization_id");
assert.equal(allLocationsError, null);
assert.ok(
  new Set(allLocations.map((row) => row.organization_id)).size >= 2,
  "SUPER_ADMIN consulta puntos de más de una organización",
);

const { error: movementsError } = await platform.from("stock_movements").select("id").limit(5);
assert.equal(movementsError, null, "SUPER_ADMIN consulta los movimientos globales");

const { data: roster, error: rosterError } = await platform.rpc("platform_users_admin", {
  p_event_id: "10000000-0000-0000-0000-000000000001",
});
assert.equal(rosterError, null);
assert.ok(roster.length >= 6, "SUPER_ADMIN lee el padrón completo de cuentas");
assert.ok(
  roster.some((row) => row.is_super_admin === true),
  "El padrón identifica quién tiene autoridad global",
);

/*
 * Fase 8: SUPER_ADMIN no es `RLS OFF`. Sin política de UPDATE sobre el inventario, un
 * intento de editar existencias por tabla no toca ninguna fila aunque quien lo intente
 * sea la autoridad global. El Kardex sigue siendo la única vía.
 */
const someLot = (await platform.from("inventory_lots").select("id,quantity_initial").limit(1)).data?.[0];
assert.ok(someLot, "El sandbox tiene al menos un lote para probar la escritura directa");
const { data: forcedStock } = await platform
  .from("inventory_lots")
  .update({ quantity_initial: Number(someLot.quantity_initial) + 999 })
  .eq("id", someLot.id)
  .select("id");
assert.equal(forcedStock?.length ?? 0, 0, "SUPER_ADMIN no puede escribir existencias saltándose el Kardex");
const { data: untouchedLot } = await platform.from("inventory_lots").select("quantity_initial").eq("id", someLot.id).single();
assert.equal(
  Number(untouchedLot.quantity_initial),
  Number(someLot.quantity_initial),
  "La existencia permanece exactamente como estaba",
);

const { error: selfPromotionError } = await platform.rpc("assign_membership_role", {
  p_user_id: "00000000-0000-0000-0000-000000000106",
  p_organization_id: "20000000-0000-0000-0000-000000000001",
  p_event_id: "10000000-0000-0000-0000-000000000001",
  p_role: "auditor",
  p_active: true,
});
assert.ok(selfPromotionError, "Ni SUPER_ADMIN edita su propia membresía");

await platform.auth.signOut();
console.log("RLS PASS: mapa/logística seguros, anonimato, aislamiento de tenant, escalamiento bloqueado y alcance global comprobado");
