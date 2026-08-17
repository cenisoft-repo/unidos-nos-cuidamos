// Provisiona un entorno desde cero: evento, organizaciones, cuentas por rol, centros de
// acopio y fondos, sobre un esquema que ya tiene las migraciones aplicadas.
//
// No está atado a ningún proyecto: el destino se declara y se confirma en cada ejecución.
// Los centros de acopio se crean con `manage_delivery_point`, la misma función auditada,
// versionada e idempotente que usa /operaciones/centros, en lugar de escribir las tablas
// directamente. Así el entorno entregado nace con la misma historia que produciría la UI.
import { createHash, randomBytes } from "node:crypto";
import { chmod, mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { createClient } from "@supabase/supabase-js";

const ROLES = new Set([
  "event_admin", "verifier", "partner_reporter", "warehouse_operator",
  "logistics_operator", "treasury_requester", "treasury_approver", "auditor",
]);
const CATEGORIES = new Set(["Alimentos", "Agua", "Higiene", "Salud", "Refugio", "Protección", "Logística", "Otro"]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SLUG = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const LOOPBACK = new Set(["127.0.0.1", "localhost", "::1"]);

function fail(message) {
  throw new Error(message);
}

function requireEnv(name) {
  const value = process.env[name];
  if (!value) fail(`Falta la variable requerida ${name}`);
  return value;
}

function assertSuccess(label, result) {
  if (result.error) fail(`${label}: ${result.error.message}`);
  return result.data;
}

// ---------------------------------------------------------------- configuración

function validateConfig(config) {
  const event = config.event ?? fail("La configuración no declara `event`");
  if (!UUID.test(event.id ?? "")) fail("`event.id` debe ser un UUID");
  if (!SLUG.test(event.slug ?? "")) fail("`event.slug` debe usar minúsculas, dígitos y guiones simples");
  if (!event.name?.trim()) fail("`event.name` es obligatorio");
  if (typeof event.simulated !== "boolean") fail("`event.simulated` debe ser true o false, sin ambigüedad");

  const organizations = config.organizations ?? [];
  if (!organizations.length) fail("Declara al menos una organización");
  const orgByKey = new Map();
  for (const organization of organizations) {
    if (!organization.key?.trim()) fail("Cada organización necesita `key`");
    if (orgByKey.has(organization.key)) fail(`La organización \`${organization.key}\` está declarada dos veces`);
    if (!UUID.test(organization.id ?? "")) fail(`\`${organization.key}.id\` debe ser un UUID`);
    if (!SLUG.test(organization.slug ?? "")) fail(`\`${organization.key}.slug\` debe usar minúsculas, dígitos y guiones simples`);
    if (!organization.name?.trim()) fail(`\`${organization.key}.name\` es obligatorio`);
    orgByKey.set(organization.key, organization);
  }

  const accounts = config.accounts ?? [];
  if (!accounts.length) fail("Declara al menos una cuenta");
  const emails = new Set();
  for (const account of accounts) {
    if (!account.key?.trim()) fail("Cada cuenta necesita `key`");
    if (!/^\S+@\S+\.\S+$/.test(account.email ?? "")) fail(`\`${account.key}.email\` no es un correo válido`);
    if (emails.has(account.email.toLowerCase())) fail(`El correo ${account.email} está declarado dos veces`);
    emails.add(account.email.toLowerCase());
    if (!account.fullName?.trim()) fail(`\`${account.key}.fullName\` es obligatorio`);
    for (const membership of account.memberships ?? []) {
      if (!orgByKey.has(membership.organization)) fail(`\`${account.key}\` referencia la organización desconocida \`${membership.organization}\``);
      if (!membership.roles?.length) fail(`\`${account.key}\` declara una membresía sin roles`);
      for (const role of membership.roles) {
        if (!ROLES.has(role)) fail(`\`${account.key}\` declara el rol desconocido \`${role}\``);
      }
    }
  }
  const admins = accounts.filter((account) => (account.memberships ?? []).some((membership) => membership.roles.includes("event_admin")));
  if (!admins.length) fail("Alguna cuenta debe tener `event_admin`: sin ella no se pueden parametrizar centros de acopio");

  const deliveryPoints = config.deliveryPoints ?? [];
  if (!deliveryPoints.length) fail("Declara al menos un centro de acopio: sin punto activo el aliado no puede reportar bienes");
  const pointNames = new Set();
  for (const point of deliveryPoints) {
    const label = point.name ?? "(sin nombre)";
    if (!orgByKey.has(point.organization)) fail(`El punto \`${label}\` referencia la organización desconocida \`${point.organization}\``);
    const fingerprint = `${point.organization}::${point.name}`;
    if (pointNames.has(fingerprint)) fail(`El punto \`${label}\` está declarado dos veces para la misma organización`);
    pointNames.add(fingerprint);
    if ((point.name ?? "").trim().length < 3 || point.name.trim().length > 120) fail(`\`${label}\`: el nombre debe tener entre 3 y 120 caracteres`);
    if ((point.publicLocationText ?? "").trim().length < 3) fail(`\`${label}\`: declara la ciudad y zona aproximada pública`);
    if ((point.privateAddress ?? "").trim().length < 5) fail(`\`${label}\`: declara la dirección exacta privada`);
    if (typeof point.latitude !== "number" || point.latitude < -4.5 || point.latitude > 13.5) fail(`\`${label}\`: la latitud aproximada queda fuera de Colombia`);
    if (typeof point.longitude !== "number" || point.longitude < -82 || point.longitude > -66.5) fail(`\`${label}\`: la longitud aproximada queda fuera de Colombia`);
    // Un punto sin propósito declarado se toma como centro de acopio, que es el caso común.
    const accepts = point.accepts ?? [];
    const acceptsDonations = point.acceptsDonations ?? true;
    const dispatchesShipments = point.dispatchesShipments ?? false;
    if (!acceptsDonations && !dispatchesShipments) fail(`\`${label}\`: debe recibir aportes, despachar salidas o ambas cosas`);
    if (acceptsDonations && (accepts.length < 1 || accepts.length > 8)) fail(`\`${label}\`: un punto que recibe aportes declara entre 1 y 8 categorías`);
    if (!acceptsDonations && accepts.length) fail(`\`${label}\`: un punto que solo despacha no declara categorías de recepción`);
    for (const category of accepts) {
      if (!CATEGORIES.has(category)) fail(`\`${label}\`: la categoría \`${category}\` no pertenece al catálogo vigente (${[...CATEGORIES].join(", ")})`);
    }
  }

  for (const fund of config.funds ?? []) {
    if (!orgByKey.has(fund.organization)) fail(`El fondo \`${fund.name}\` referencia la organización desconocida \`${fund.organization}\``);
    if (!UUID.test(fund.id ?? "")) fail(`\`${fund.name}.id\` debe ser un UUID`);
  }

  return { event, organizations, orgByKey, accounts, deliveryPoints, funds: config.funds ?? [] };
}

// ---------------------------------------------------------------- destino y permisos

const configPath = path.resolve(requireEnv("BOOTSTRAP_CONFIG_PATH"));
const config = validateConfig(JSON.parse(await readFile(configPath, "utf8")));
const supabaseUrl = requireEnv("SUPABASE_URL");
const secretKey = requireEnv("SUPABASE_SECRET_KEY");
const publishableKey = requireEnv("SUPABASE_PUBLISHABLE_KEY");
const targetHost = new URL(supabaseUrl).hostname;
const isRemote = !LOOPBACK.has(targetHost);

if (requireEnv("BOOTSTRAP_CONFIRM_TARGET") !== targetHost) {
  fail(`BOOTSTRAP_CONFIRM_TARGET debe repetir exactamente el host de destino (${targetHost}). Es la barrera contra provisionar el proyecto equivocado.`);
}
if (isRemote && !config.event.simulated && process.env.BOOTSTRAP_ACKNOWLEDGE_REAL_EVENT !== "yes") {
  fail("El evento está declarado como no simulado sobre un destino remoto. Requiere BOOTSTRAP_ACKNOWLEDGE_REAL_EVENT=yes y una autorización humana previa.");
}

const credentialsPath = path.resolve(requireEnv("BOOTSTRAP_CREDENTIALS_PATH"));
const workspace = path.resolve(process.cwd());
if (credentialsPath.toLowerCase().startsWith(`${workspace.toLowerCase()}${path.sep}`)) {
  fail("El archivo de accesos debe quedar fuera del repositorio");
}

const admin = createClient(supabaseUrl, secretKey, {
  auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
});

function anonClient() {
  return createClient(supabaseUrl, publishableKey, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  });
}

// ---------------------------------------------------------------- 1. esquema

// Los catálogos se consultan con la clave pública a propósito: `donation_flow_catalogs`
// solo está concedida a `anon` y `authenticated`, así que esta comprobación verifica a la
// vez que las migraciones están aplicadas y que la superficie pública responde.
const catalogs = assertSuccess("lectura de catálogos", await anonClient().rpc("donation_flow_catalogs"));
if (!catalogs?.length) {
  fail("El destino no tiene catálogos: aplica primero las migraciones con `npx supabase db push`.");
}
console.log(`[1/6] Esquema verificado · ${catalogs.length} catálogos vigentes`);

// ---------------------------------------------------------------- 2. evento y organizaciones

assertSuccess(
  "organizaciones",
  await admin.from("organizations").upsert(
    config.organizations.map((organization) => ({
      id: organization.id,
      name: organization.name,
      slug: organization.slug,
      verified: true,
      status: "active",
    })),
    { onConflict: "id" },
  ),
);
assertSuccess(
  "evento",
  await admin.from("emergency_events").upsert({
    id: config.event.id,
    name: config.event.name,
    slug: config.event.slug,
    status: "active",
    simulated: config.event.simulated,
    starts_at: config.event.startsAt ?? null,
    public_summary: config.event.publicSummary ?? "",
    timezone: config.event.timezone ?? "America/Bogota",
  }, { onConflict: "id" }),
);
console.log(`[2/6] Evento \`${config.event.slug}\` y ${config.organizations.length} organizaciones verificadas`);

// ---------------------------------------------------------------- 3. cuentas y membresías

const existingUsers = [];
for (let page = 1; ; page += 1) {
  const data = assertSuccess("consulta de usuarios Auth", await admin.auth.admin.listUsers({ page, perPage: 200 }));
  existingUsers.push(...data.users);
  if (data.users.length < 200) break;
}

const provisioned = [];
for (const account of config.accounts) {
  const password = `Rs!9-${randomBytes(18).toString("base64url")}`;
  const existing = existingUsers.find((user) => user.email?.toLowerCase() === account.email.toLowerCase());
  const attributes = {
    email: account.email,
    password,
    email_confirm: true,
    user_metadata: { full_name: account.fullName },
  };
  const user = existing
    ? assertSuccess(`actualización de ${account.key}`, await admin.auth.admin.updateUserById(existing.id, attributes)).user
    : assertSuccess(`creación de ${account.key}`, await admin.auth.admin.createUser(attributes)).user;
  if (!user?.id) fail(`Auth no devolvió el identificador de ${account.key}`);
  provisioned.push({ ...account, id: user.id, password, rotated: Boolean(existing) });
}

assertSuccess(
  "perfiles",
  await admin.from("profiles").upsert(
    provisioned.map((account) => ({ id: account.id, full_name: account.fullName, locale: "es-CO" })),
    { onConflict: "id" },
  ),
);

const memberships = provisioned.flatMap((account) => (account.memberships ?? []).flatMap((membership) => membership.roles.map((role) => ({
  user_id: account.id,
  organization_id: config.orgByKey.get(membership.organization).id,
  event_id: config.event.id,
  role,
  active: true,
}))));
assertSuccess(
  "membresías",
  await admin.from("memberships").upsert(memberships, { onConflict: "user_id,organization_id,event_id,role" }),
);

const administrator = provisioned.find((account) => (account.memberships ?? []).some((membership) => membership.roles.includes("event_admin")));
assertSuccess(
  "actor del evento",
  await admin.from("emergency_events").update({ created_by: administrator.id }).eq("id", config.event.id),
);
console.log(`[3/6] ${provisioned.length} cuentas y ${memberships.length} membresías provisionadas`);

// ---------------------------------------------------------------- 4. centros de acopio

const adminSession = anonClient();
assertSuccess(
  "sesión de administración",
  await adminSession.auth.signInWithPassword({ email: administrator.email, password: administrator.password }),
);

// La parametrización vigente se lee con la misma función que usa /operaciones/centros.
// Un punto que ya coincide con lo declarado no se vuelve a escribir: reejecutar el
// bootstrap no debe crear versiones de reglas ni entradas de auditoría sin cambio real.
const currentPoints = assertSuccess(
  "parametrización vigente",
  await adminSession.rpc("delivery_points_admin", { p_event_id: config.event.id }),
);

function matchesDeclared(current, point, organizationId) {
  const declaredInstructions = point.publicInstructions?.trim() || null;
  return current.organization_id === organizationId
    && current.public_location_text === point.publicLocationText.trim()
    && current.exact_address_private === point.privateAddress.trim()
    && (current.public_instructions ?? null) === declaredInstructions
    && Number(current.public_latitude) === point.latitude
    && Number(current.public_longitude) === point.longitude
    && current.cold_chain_capable === Boolean(point.coldChainCapable)
    && current.active === (point.active !== false)
    && current.accepts_donations === (point.acceptsDonations ?? true)
    && current.dispatches_shipments === (point.dispatchesShipments ?? false)
    && [...(current.accepted_categories ?? [])].sort().join("|") === [...(point.accepts ?? [])].sort().join("|");
}

const centers = [];
for (const point of config.deliveryPoints) {
  const organizationId = config.orgByKey.get(point.organization).id;
  const existing = currentPoints.find((current) => current.organization_id === organizationId && current.name === point.name.trim());
  if (existing && matchesDeclared(existing, point, organizationId)) {
    centers.push({ ...point, organizationId, id: existing.id, unchanged: true });
    continue;
  }
  // La clave idempotente incorpora el punto de destino porque la función calcula su propia
  // huella con `p_location_id`: crear y actualizar son solicitudes distintas.
  const fingerprint = createHash("sha256")
    .update(JSON.stringify([config.event.id, organizationId, existing?.id ?? null, point]))
    .digest("hex");
  const result = assertSuccess(
    `parametrización de \`${point.name}\``,
    await adminSession.rpc("manage_delivery_point", {
      p_location_id: existing?.id ?? null,
      p_event_id: config.event.id,
      p_organization_id: organizationId,
      p_name: point.name.trim(),
      p_public_location_text: point.publicLocationText.trim(),
      p_exact_address_private: point.privateAddress.trim(),
      p_public_instructions: point.publicInstructions?.trim() || null,
      p_public_latitude: point.latitude,
      p_public_longitude: point.longitude,
      p_cold_chain_capable: Boolean(point.coldChainCapable),
      p_active: point.active !== false,
      p_accepts_donations: point.acceptsDonations ?? true,
      p_dispatches_shipments: point.dispatchesShipments ?? false,
      p_accepted_categories: (point.acceptsDonations ?? true) ? point.accepts : [],
      p_idempotency_key: `bootstrap-${fingerprint.slice(0, 32)}`,
    }),
  );
  const row = Array.isArray(result) ? result[0] : result;
  centers.push({ ...point, organizationId, id: row.location_id, unchanged: false });
}
const unchanged = centers.filter((center) => center.unchanged).length;
console.log(`[4/6] ${centers.length} centros de acopio parametrizados (${unchanged} ya coincidían y no se reescribieron)`);

if (config.funds.length) {
  assertSuccess(
    "fondos",
    await admin.from("funds").upsert(
      config.funds.map((fund) => ({
        id: fund.id,
        event_id: config.event.id,
        organization_id: config.orgByKey.get(fund.organization).id,
        name: fund.name,
        currency: fund.currency ?? "COP",
        verified: fund.verified !== false,
        restrictions: fund.restrictions ?? null,
      })),
      { onConflict: "id" },
    ),
  );
}

// ---------------------------------------------------------------- 5. verificación

for (const account of provisioned) {
  const session = anonClient();
  assertSuccess(`inicio de sesión de ${account.key}`, await session.auth.signInWithPassword({ email: account.email, password: account.password }));
  const visible = assertSuccess(
    `roles visibles de ${account.key}`,
    await session.from("memberships").select("role,organization_id").eq("user_id", account.id).eq("active", true),
  );
  const granted = new Set(visible.map((membership) => `${membership.organization_id}:${membership.role}`));
  for (const membership of account.memberships ?? []) {
    for (const role of membership.roles) {
      const expected = `${config.orgByKey.get(membership.organization).id}:${role}`;
      if (!granted.has(expected)) fail(`La cuenta ${account.key} no recibió el rol ${role} en ${membership.organization}`);
    }
  }
  await session.auth.signOut();
}

// Un aliado debe ver los puntos activos de su organización y ninguno de las demás.
const reporter = provisioned.find((account) => (account.memberships ?? []).some((membership) => membership.roles.includes("partner_reporter")));
if (reporter) {
  const ownOrganizations = new Set(reporter.memberships.map((membership) => config.orgByKey.get(membership.organization).id));
  const session = anonClient();
  assertSuccess("sesión del aliado", await session.auth.signInWithPassword({ email: reporter.email, password: reporter.password }));
  for (const organizationId of ownOrganizations) {
    const own = assertSuccess(
      "puntos propios del aliado",
      await session.rpc("organization_delivery_points", { p_event_id: config.event.id, p_organization_id: organizationId }),
    );
    // Solo los puntos de acopio se ofrecen al aliado: una base que solo despacha no aparece.
    const expected = centers.filter((center) => center.organizationId === organizationId
      && center.active !== false
      && (center.acceptsDonations ?? true));
    if (own.length !== expected.length) {
      fail(`El aliado ve ${own.length} puntos de acopio de su organización y se esperaban ${expected.length}`);
    }
  }
  for (const organizationId of new Set(config.organizations.map((organization) => organization.id))) {
    if (ownOrganizations.has(organizationId)) continue;
    const foreign = await session.rpc("organization_delivery_points", { p_event_id: config.event.id, p_organization_id: organizationId });
    if (!foreign.error && (foreign.data ?? []).length) {
      fail("Aislamiento roto: el aliado alcanzó puntos de otra organización");
    }
  }
  await session.auth.signOut();
  console.log("[5/6] Accesos, roles y aislamiento entre organizaciones verificados");
} else {
  console.log("[5/6] Accesos y roles verificados · sin cuenta `partner_reporter` que permita probar el aislamiento");
}
await adminSession.auth.signOut();

// ---------------------------------------------------------------- 6. entrega

const lines = [
  "ACCESOS TEMPORALES DEL ENTORNO",
  `Destino: ${targetHost}`,
  `Evento: ${config.event.slug} (${config.event.id})`,
  `Generados: ${new Date().toISOString()}`,
  "",
  "Entrega cada contraseña por un canal controlado y pide que se rote en el primer ingreso.",
  "No compartas este archivo completo ni lo guardes en el repositorio.",
  "",
  ...provisioned.flatMap((account) => [
    `Cuenta: ${account.key}${account.rotated ? " (contraseña rotada sobre una cuenta existente)" : ""}`,
    `Correo: ${account.email}`,
    `Contraseña temporal: ${account.password}`,
    `Permisos: ${(account.memberships ?? []).map((membership) => `${membership.organization} → ${membership.roles.join(", ")}`).join(" · ")}`,
    "",
  ]),
  "CENTROS DE ACOPIO",
  ...centers.map((center) => {
    const purpose = [(center.acceptsDonations ?? true) ? `recibe ${center.accepts.join(", ")}` : null, (center.dispatchesShipments ?? false) ? "despacha salidas" : null]
      .filter(Boolean).join(" · ");
    return `- ${center.name} (${center.organization}) · ${center.publicLocationText} · ${purpose}`;
  }),
];
await mkdir(path.dirname(credentialsPath), { recursive: true });
await writeFile(credentialsPath, `${lines.join("\n")}\n`, { encoding: "utf8", flag: "w", mode: 0o600 });
await chmod(credentialsPath, 0o600);

console.log("[6/6] Entorno listo\n");
console.log("Declara estas variables en el hosting (además de las claves de Supabase):");
console.log(`NEXT_PUBLIC_EVENT_ID=${config.event.id}`);
console.log(`NEXT_PUBLIC_EVENT_SLUG=${config.event.slug}`);
console.log(`\nAccesos temporales escritos en ${credentialsPath} (solo lectura del propietario).`);
