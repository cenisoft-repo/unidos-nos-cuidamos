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
assert.equal(publicCenters.length, 2, "Anon solo ve los dos centros sintéticos proyectados");
assert.equal("exact_address_private" in publicCenters[0], false, "La proyección de centros no expone direcciones exactas");

const { data: publicLogistics, error: logisticsError } = await anonymous.rpc("public_logistics_map", {
  p_event_id: "10000000-0000-0000-0000-000000000001",
});
assert.equal(logisticsError, null, "Anon debe consultar la proyección logística pública");
assert.equal(publicLogistics.filter((row) => row.source_type === "collection_center").length, 2, "La logística pública contiene los dos centros activos");
assert.equal("exact_address_private" in publicLogistics[0], false, "La logística pública no expone direcciones exactas");
assert.equal("transport_plate" in publicLogistics[0], false, "La logística pública no expone transportadores ni placas");

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

await partner.auth.signOut();
console.log("RLS PASS: mapa/logística seguros, anonimato, aislamiento de tenant y escalamiento bloqueado");
