import assert from "node:assert/strict";
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
assert.ok(url && key, "Faltan variables públicas de Supabase local");

const supabase = createClient(url, key, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const { error: signInError } = await supabase.auth.signInWithPassword({
  email: "aliado@rutasolidaria.local",
  password: "RutaSolidaria2026!",
});
assert.equal(signInError, null, "La cuenta aliada sandbox debe autenticar");

const { data: catalogVersions, error: catalogError } = await supabase.rpc("current_donation_catalog_versions");
assert.equal(catalogError, null, `Los catálogos deben estar disponibles: ${catalogError?.message ?? ""}`);
assert.ok(catalogVersions && typeof catalogVersions === "object", "Las versiones de catálogo deben ser un objeto");

const idempotencyKey = `concurrency-${crypto.randomUUID()}`;
const payload = {
  p_event_id: "10000000-0000-0000-0000-000000000001",
  p_organization_id: "20000000-0000-0000-0000-000000000002",
  p_kind: "in_kind",
  p_idempotency_key: idempotencyKey,
  p_donor_name_private: "Donante concurrente sintético",
  p_contact_private: { email: "concurrency@example.invalid", phone: "" },
  p_attribution_kind: "anonymous",
  p_public_attribution: "",
  p_attribution_authorized: false,
  p_declared_status: "comprometida",
  p_items: [{
    category: "Agua",
    category_code: "agua_potable",
    description: "Botellas selladas para prueba concurrente",
    quantity: 12,
    unit: "litro",
    condition: "sellado",
    storage_requirement: "ambiente",
    expires_on: null,
    declared_estimated_value_cop: null,
  }],
  p_declared_amount: null,
  p_preferred_location_id: "70000000-0000-0000-0000-000000000002",
  p_reporting_context: {
    donor_type: "empresa",
    economic_sector: "tecnologia",
    specific_destination: false,
    estimated_beneficiaries: "",
    internal_contact: {},
  },
  p_catalog_versions: catalogVersions,
  p_declared_category_code: null,
};

const results = await Promise.all([
  supabase.rpc("submit_donation_intake_v2", payload),
  supabase.rpc("submit_donation_intake_v2", payload),
]);

for (const result of results) {
  assert.equal(result.error, null, `El envío concurrente no debe fallar: ${result.error?.message ?? ""}`);
}

const rows = results.map((result) => Array.isArray(result.data) ? result.data[0] : result.data);
assert.ok(rows[0]?.intake_id, "El primer envío debe devolver un intake");
assert.equal(rows[0]?.intake_id, rows[1]?.intake_id, "Ambos envíos deben resolver al mismo intake");
assert.deepEqual(
  rows.map((row) => row?.was_duplicate).sort(),
  [false, true],
  "Solo una solicitud debe insertar y la otra debe ser un reintento",
);

await supabase.auth.signOut();
console.log("CONCURRENCY PASS: dos envíos simultáneos producen un solo intake y un reintento seguro");
