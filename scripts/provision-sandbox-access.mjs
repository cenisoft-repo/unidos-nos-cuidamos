import { randomBytes } from "node:crypto";
import { chmod, mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { createClient } from "@supabase/supabase-js";

const PROJECT_REF = "vcgwfyhytzgyzicfbikf";
const EVENT_ID = "10000000-0000-0000-0000-000000000001";
const COORDINATION_ORG_ID = "20000000-0000-0000-0000-000000000001";
const PARTNER_ORG_ID = "20000000-0000-0000-0000-000000000002";

const requiredEnvironment = [
  "SUPABASE_SANDBOX_URL",
  "SUPABASE_SANDBOX_SECRET_KEY",
  "SUPABASE_SANDBOX_PUBLISHABLE_KEY",
  "SANDBOX_CREDENTIALS_PATH",
];

for (const name of requiredEnvironment) {
  if (!process.env[name]) throw new Error(`Falta la variable requerida ${name}`);
}

if (process.env.ALLOW_SYNTHETIC_REMOTE_BOOTSTRAP !== PROJECT_REF) {
  throw new Error("La provisión remota requiere una confirmación explícita para el proyecto sandbox esperado");
}
if (process.env.SANDBOX_ROTATE_PASSWORDS !== "yes") {
  throw new Error("La provisión requiere SANDBOX_ROTATE_PASSWORDS=yes para entregar accesos verificables");
}

const supabaseUrl = process.env.SUPABASE_SANDBOX_URL;
const expectedHost = `${PROJECT_REF}.supabase.co`;
if (new URL(supabaseUrl).hostname !== expectedHost) {
  throw new Error(`El destino no corresponde al sandbox esperado (${expectedHost})`);
}

const credentialsPath = path.resolve(process.env.SANDBOX_CREDENTIALS_PATH);
const workspacePath = path.resolve(process.cwd());
if (credentialsPath.toLowerCase().startsWith(`${workspacePath.toLowerCase()}${path.sep}`)) {
  throw new Error("El archivo de accesos temporales debe quedar fuera del repositorio");
}

const admin = createClient(supabaseUrl, process.env.SUPABASE_SANDBOX_SECRET_KEY, {
  auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
});

function assertSuccess(label, result) {
  if (result.error) throw new Error(`${label}: ${result.error.message}`);
  return result.data;
}

function temporaryPassword() {
  return `Rs!9-${randomBytes(18).toString("base64url")}`;
}

const organizations = [
  {
    id: COORDINATION_ORG_ID,
    name: "Coordinación Humanitaria · Sandbox",
    slug: "coordinacion-humanitaria-sandbox",
    verified: true,
    status: "active",
  },
  {
    id: PARTNER_ORG_ID,
    name: "Aliado Operativo · Sandbox",
    slug: "aliado-operativo-sandbox",
    verified: true,
    status: "active",
  },
];

assertSuccess(
  "organizaciones sintéticas",
  await admin.from("organizations").upsert(organizations, { onConflict: "id" }),
);
assertSuccess(
  "evento sintético",
  await admin.from("emergency_events").upsert({
    id: EVENT_ID,
    name: "Ejercicio de coordinación humanitaria · Sandbox",
    slug: "ejercicio-coordinacion-sandbox-2026",
    status: "active",
    simulated: true,
    starts_at: "2026-08-16T08:00:00-05:00",
    public_summary: "Ejercicio con información totalmente ficticia para validar coordinación, trazabilidad y seguridad.",
    timezone: "America/Bogota",
  }, { onConflict: "id" }),
);

const userDefinitions = [
  {
    key: "admin",
    email: "admin@rutasolidaria.local",
    fullName: "Coordinación Sandbox",
    memberships: [
      [COORDINATION_ORG_ID, "event_admin"],
      [COORDINATION_ORG_ID, "verifier"],
      [COORDINATION_ORG_ID, "auditor"],
      [PARTNER_ORG_ID, "event_admin"],
      [PARTNER_ORG_ID, "verifier"],
    ],
  },
  {
    key: "partner",
    email: "aliado@rutasolidaria.local",
    fullName: "Aliado Sandbox",
    memberships: [[PARTNER_ORG_ID, "partner_reporter"]],
  },
  {
    key: "warehouse",
    email: "bodega@rutasolidaria.local",
    fullName: "Bodega Sandbox",
    memberships: [
      [COORDINATION_ORG_ID, "warehouse_operator"],
      [COORDINATION_ORG_ID, "logistics_operator"],
      [PARTNER_ORG_ID, "warehouse_operator"],
      [PARTNER_ORG_ID, "logistics_operator"],
    ],
  },
  {
    key: "requester",
    email: "solicita@rutasolidaria.local",
    fullName: "Solicitudes Sandbox",
    memberships: [[COORDINATION_ORG_ID, "treasury_requester"]],
  },
  {
    key: "approver",
    email: "aprueba@rutasolidaria.local",
    fullName: "Aprobaciones Sandbox",
    memberships: [[COORDINATION_ORG_ID, "treasury_approver"]],
  },
];

const existingUsers = [];
for (let page = 1; ; page += 1) {
  const data = assertSuccess(
    "consulta de usuarios Auth",
    await admin.auth.admin.listUsers({ page, perPage: 200 }),
  );
  existingUsers.push(...data.users);
  if (data.users.length < 200) break;
}

const provisionedUsers = [];
for (const definition of userDefinitions) {
  const password = temporaryPassword();
  const existing = existingUsers.find((user) => user.email?.toLowerCase() === definition.email);
  const attributes = {
    email: definition.email,
    password,
    email_confirm: true,
    user_metadata: {
      full_name: definition.fullName,
      synthetic_sandbox: true,
    },
    app_metadata: {
      synthetic_sandbox: true,
    },
  };
  const user = existing
    ? assertSuccess(
      `actualización de ${definition.key}`,
      await admin.auth.admin.updateUserById(existing.id, attributes),
    ).user
    : assertSuccess(
      `creación de ${definition.key}`,
      await admin.auth.admin.createUser(attributes),
    ).user;
  if (!user?.id) throw new Error(`Auth no devolvió el identificador de ${definition.key}`);
  provisionedUsers.push({ ...definition, id: user.id, password });
}

assertSuccess(
  "perfiles sintéticos",
  await admin.from("profiles").upsert(
    provisionedUsers.map((user) => ({ id: user.id, full_name: user.fullName, locale: "es-CO" })),
    { onConflict: "id" },
  ),
);

const memberships = provisionedUsers.flatMap((user) => user.memberships.map(([organizationId, role]) => ({
  user_id: user.id,
  organization_id: organizationId,
  event_id: EVENT_ID,
  role,
  active: true,
})));
assertSuccess(
  "membresías por rol y organización",
  await admin.from("memberships").upsert(memberships, {
    onConflict: "user_id,organization_id,event_id,role",
  }),
);

const administrator = provisionedUsers.find((user) => user.key === "admin");
assertSuccess(
  "actor administrador del evento",
  await admin.from("emergency_events").update({ created_by: administrator.id }).eq("id", EVENT_ID),
);

const centers = [
  {
    id: "70000000-0000-0000-0000-000000000001",
    event_id: EVENT_ID,
    organization_id: COORDINATION_ORG_ID,
    name: "Centro de acopio Norte · Sandbox",
    public_location_text: "Medellín · zona norte aproximada",
    exact_address_private: "Ubicación sintética no operativa",
    cold_chain_capable: false,
    active: true,
    public_latitude: 6.267,
    public_longitude: -75.56,
  },
  {
    id: "70000000-0000-0000-0000-000000000002",
    event_id: EVENT_ID,
    organization_id: PARTNER_ORG_ID,
    name: "Centro de acopio Centro · Sandbox",
    public_location_text: "Manizales · zona centro aproximada",
    exact_address_private: "Ubicación sintética no operativa",
    cold_chain_capable: false,
    active: true,
    public_latitude: 5.066,
    public_longitude: -75.507,
  },
];
assertSuccess(
  "centros de acopio sintéticos",
  await admin.from("inventory_locations").upsert(centers, { onConflict: "id" }),
);

const acceptedCategories = ["Agua", "Alimentos", "Higiene", "Refugio", "Salud", "Protección", "Logística", "Otro"];
const acceptanceRules = centers.flatMap((center, centerIndex) => acceptedCategories.map((category, categoryIndex) => ({
  id: `91000000-0000-0000-0000-${String((centerIndex * 100) + categoryIndex + 1).padStart(12, "0")}`,
  organization_id: center.organization_id,
  event_id: EVENT_ID,
  location_id: center.id,
  category,
  decision: "accepted",
  rule_text: "Recepción habilitada únicamente para el ejercicio sandbox; inspección obligatoria al ingreso.",
  requires_cold_chain: false,
  version: 1,
  effective_from: "2026-08-16T00:00:00-05:00",
})));
assertSuccess(
  "reglas de aceptación por centro",
  await admin.from("item_acceptance_rules").upsert(acceptanceRules, { onConflict: "id" }),
);

assertSuccess(
  "fondo sintético",
  await admin.from("funds").upsert({
    id: "80000000-0000-0000-0000-000000000001",
    event_id: EVENT_ID,
    organization_id: COORDINATION_ORG_ID,
    name: "Fondo de respuesta · Sandbox",
    currency: "COP",
    verified: true,
    restrictions: "Ejercicio sin recaudo, pagos ni movimientos financieros reales.",
  }, { onConflict: "id" }),
);

for (const user of provisionedUsers) {
  const verifier = createClient(supabaseUrl, process.env.SUPABASE_SANDBOX_PUBLISHABLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  });
  assertSuccess(
    `inicio de sesión de ${user.key}`,
    await verifier.auth.signInWithPassword({ email: user.email, password: user.password }),
  );
  const visibleMemberships = assertSuccess(
    `permisos visibles de ${user.key}`,
    await verifier.from("memberships").select("role,organization_id").eq("user_id", user.id).eq("active", true),
  );
  const visibleRoles = new Set(visibleMemberships.map((membership) => membership.role));
  for (const [, role] of user.memberships) {
    if (!visibleRoles.has(role)) throw new Error(`La cuenta ${user.key} no recibió el rol ${role}`);
  }
  await verifier.auth.signOut();
}

const createdAt = new Date().toISOString();
const credentialLines = [
  "RUTA SOLIDARIA — ACCESOS TEMPORALES DEL SANDBOX",
  `Proyecto: ${PROJECT_REF}`,
  `Generados: ${createdAt}`,
  "",
  "Estas identidades y sus datos son totalmente sintéticos.",
  "No compartas este archivo ni reutilices estas contraseñas en otros servicios.",
  "",
  ...provisionedUsers.flatMap((user) => [
    `Rol: ${user.key}`,
    `Correo: ${user.email}`,
    `Contraseña temporal: ${user.password}`,
    `Permisos: ${user.memberships.map(([, role]) => role).join(", ")}`,
    "",
  ]),
];
await mkdir(path.dirname(credentialsPath), { recursive: true });
await writeFile(credentialsPath, `${credentialLines.join("\n")}\n`, { encoding: "utf8", flag: "w", mode: 0o600 });
await chmod(credentialsPath, 0o600);

console.log(`SANDBOX_USERS_VERIFIED=${provisionedUsers.length}`);
console.log(`SANDBOX_MEMBERSHIPS_VERIFIED=${memberships.length}`);
console.log(`SANDBOX_CENTERS_READY=${centers.length}`);
console.log(`CREDENTIALS_PATH=${credentialsPath}`);
