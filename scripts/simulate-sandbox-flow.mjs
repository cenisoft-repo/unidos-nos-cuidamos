import { randomUUID } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { createClient } from "@supabase/supabase-js";
import { chromium } from "@playwright/test";

const PROJECT_REF = "vcgwfyhytzgyzicfbikf";
const EVENT_ID = "10000000-0000-0000-0000-000000000001";
const PARTNER_ORG_ID = "20000000-0000-0000-0000-000000000002";
const PARTNER_CENTER_ID = "70000000-0000-0000-0000-000000000002";
const COORDINATION_CENTER_ID = "70000000-0000-0000-0000-000000000001";
const FUND_ID = "80000000-0000-0000-0000-000000000001";
const APP_URL = process.env.PUBLISHED_APP_URL ?? "https://unidos-nos-cuidamos.vercel.app";

const requiredEnvironment = [
  "SUPABASE_SANDBOX_URL",
  "SANDBOX_CREDENTIALS_PATH",
  "SANDBOX_EVIDENCE_DIR",
];

for (const name of requiredEnvironment) {
  if (!process.env[name]) throw new Error(`Falta la variable requerida ${name}`);
}
if (process.env.ALLOW_SYNTHETIC_REMOTE_SIMULATION !== PROJECT_REF) {
  throw new Error("La simulación remota requiere confirmar explícitamente el proyecto sandbox esperado");
}

const supabaseUrl = process.env.SUPABASE_SANDBOX_URL;
let publishableKey = process.env.SUPABASE_SANDBOX_PUBLISHABLE_KEY ?? "";
if (new URL(supabaseUrl).hostname !== `${PROJECT_REF}.supabase.co`) {
  throw new Error("La URL remota no corresponde al proyecto sandbox permitido");
}
if (new URL(APP_URL).hostname !== "unidos-nos-cuidamos.vercel.app") {
  throw new Error("La aplicación publicada no corresponde al sandbox permitido");
}

const runId = `SIM-${new Date().toISOString().replace(/[-:.TZ]/g, "").slice(0, 14)}-${randomUUID().slice(0, 8)}`;
const startedAt = new Date().toISOString();
const evidenceDir = path.resolve(process.env.SANDBOX_EVIDENCE_DIR);
const evidencePath = path.join(evidenceDir, `${runId}.json`);
const screenshotPath = path.join(evidenceDir, `${runId}-qr.png`);
const evidence = {
  runId,
  target: { projectRef: PROJECT_REF, appUrl: APP_URL, eventId: EVENT_ID },
  startedAt,
  finishedAt: null,
  status: "running",
  checks: [],
  issues: [],
  artifacts: {},
};

function record(name, passed, detail = {}) {
  evidence.checks.push({ name, passed, detail });
  if (!passed) throw new Error(`Falló la comprobación: ${name}`);
}

function issue(id, severity, summary, detail = {}) {
  evidence.issues.push({ id, severity, summary, detail });
}

function valueOf(data) {
  if (Array.isArray(data)) return data[0];
  return data;
}

function success(label, result) {
  if (result.error) {
    const error = new Error(`${label}: ${result.error.message}`);
    error.code = result.error.code;
    throw error;
  }
  return result.data;
}

function denied(result) {
  return Boolean(result.error && (result.error.code === "42501" || /no puedes|permiso|permission|autentic/i.test(result.error.message)));
}

function createSandboxClient() {
  if (!publishableKey) throw new Error("No se ha resuelto la clave publicable del sandbox");
  return createClient(supabaseUrl, publishableKey, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  });
}

async function discoverPublishedApiKey() {
  if (publishableKey) return;
  const rootResponse = await fetch(APP_URL, { redirect: "error" });
  if (!rootResponse.ok) throw new Error("No fue posible inspeccionar la configuración pública desplegada");
  const rootHtml = await rootResponse.text();
  const candidates = [rootHtml];
  const scriptPaths = Array.from(rootHtml.matchAll(/<script[^>]+src="([^"]+)"/g), (match) => match[1]);
  for (const scriptPath of scriptPaths) {
    const scriptUrl = new URL(scriptPath, APP_URL);
    if (scriptUrl.origin !== new URL(APP_URL).origin) continue;
    const response = await fetch(scriptUrl, { redirect: "error" });
    if (response.ok) candidates.push(await response.text());
  }
  for (const candidate of candidates) {
    const match = candidate.match(/sb_publishable_[A-Za-z0-9_-]+/);
    if (match) {
      publishableKey = match[0];
      record("config:clave-publicable-desplegada", true, { source: "published-client-bundle" });
      return;
    }
  }
  throw new Error("La aplicación publicada no expone una clave publicable utilizable");
}

function parseCredentials(contents) {
  const roles = new Map();
  const pattern = /Rol:\s*([^\r\n]+)\r?\nCorreo:\s*([^\r\n]+)\r?\nContraseña temporal:\s*([^\r\n]+)\r?\nPermisos:/g;
  for (const match of contents.matchAll(pattern)) {
    roles.set(match[1].trim(), { email: match[2].trim(), password: match[3] });
  }
  for (const role of ["admin", "partner", "warehouse", "requester", "approver"]) {
    if (!roles.has(role)) throw new Error(`El archivo seguro no contiene la cuenta ${role}`);
  }
  return roles;
}

async function authenticatedClient(role, credentials) {
  const client = createSandboxClient();
  const account = credentials.get(role);
  const data = success(`inicio de sesión ${role}`, await client.auth.signInWithPassword(account));
  record(`auth:${role}`, Boolean(data.user?.id), { role });
  return { client, userId: data.user.id };
}

async function waitForReactHandler(page, selector) {
  await page.waitForFunction((targetSelector) => {
    const element = document.querySelector(targetSelector);
    return Boolean(element && Object.keys(element).some((key) => key.startsWith("__reactProps$")));
  }, selector);
}

async function submitViaPublishedUi(credentials) {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  try {
    await page.goto(`${APP_URL}/reportar`, { waitUntil: "domcontentloaded" });
    await page.getByLabel("Agua", { exact: true }).check();
    await page.getByLabel("Zona aproximada").fill(`Zona sintética ${runId}`);
    await page.getByLabel("Hechos observados").fill(`Ejercicio ${runId}: punto comunitario ficticio requiere agua sellada para validar el recorrido integral.`);
    await page.getByLabel("Cantidad aproximada").fill("10");
    await page.getByLabel("Unidad").selectOption("litro");
    await page.getByLabel("Ubicación exacta (privada y opcional)").fill(`Punto privado sintético ${runId}`);
    await page.getByLabel("Correo de contacto (privado y opcional)").fill(`${runId.toLowerCase()}-need@example.invalid`);
    await page.getByRole("checkbox").check();
    await page.getByRole("button", { name: "Enviar a verificación" }).click();
    await page.getByRole("heading", { name: "Reporte recibido, aún no publicado." }).waitFor();
    const needCode = (await page.locator(".form-success strong").textContent())?.trim();
    record("ui:reporte-ciudadano", /^NEC-[A-F0-9]{24}$/.test(needCode ?? ""), { code: needCode });

    await page.goto(`${APP_URL}/ingresar?next=/donar`, { waitUntil: "domcontentloaded" });
    const partner = credentials.get("partner");
    await page.getByLabel("Correo").fill(partner.email);
    await page.getByLabel("Contraseña").fill(partner.password);
    await page.getByRole("button", { name: "Ingresar", exact: true }).click();
    await page.waitForURL("**/donar");

    await page.getByRole("button", { name: "Agua potable", exact: true }).click();
    await page.getByRole("button", { name: /Continuar/ }).click();
    await page.getByLabel("¿Qué es?").fill(`Botellas selladas ${runId}`);
    await page.locator("#quantity-0").fill("10");
    await page.locator("#unit-0").selectOption("litro");
    await page.getByRole("button", { name: /Continuar/ }).click();

    const partnerCenter = page.getByRole("button", { name: /Centro de acopio Centro · Sandbox/ });
    const coordinationCenter = page.getByRole("button", { name: /Centro de acopio Norte · Sandbox/ });
    await partnerCenter.waitFor();
    const crossCenterEnabled = !(await coordinationCenter.isDisabled());
    if (crossCenterEnabled) {
      issue(
        "CENTER-TENANT-UI",
        "high",
        "El formulario permite al aliado elegir un centro perteneciente a otra organización",
        { organizationId: PARTNER_ORG_ID, exposedCenterId: COORDINATION_CENTER_ID },
      );
    }
    await partnerCenter.click();
    await page.getByRole("button", { name: /Continuar/ }).click();
    await page.getByLabel("Tipo de donante (opcional)").selectOption("empresa");
    await page.getByLabel("Nombre del donante (empresa o persona)").fill(`Donante sintético ${runId}`);
    await page.getByLabel("Correo de coordinación").fill(`${runId.toLowerCase()}-donor@example.invalid`);
    await page.getByRole("button", { name: /Continuar/ }).click();
    await page.getByRole("checkbox").check();
    await page.getByRole("button", { name: "Confirmar aporte" }).click();
    await page.getByRole("heading", { name: "Tu aporte ya tiene una ruta segura." }).waitFor();
    const intakeCode = (await page.locator(".ticket-code strong").textContent())?.trim();
    const qr = page.locator(".ticket-qr svg");
    await qr.waitFor();
    const qrPathLength = await qr.locator("path").evaluateAll((paths) => paths.reduce((size, node) => size + (node.getAttribute("d")?.length ?? 0), 0));
    record("ui:qr-real", /^APO-[A-F0-9]{24}$/.test(intakeCode ?? "") && qrPathLength > 100, {
      code: intakeCode,
      encodedTarget: `${APP_URL}/seguimiento?codigo=${intakeCode}`,
      svgPathLength: qrPathLength,
    });
    await page.locator(".donation-ticket").screenshot({ path: screenshotPath });
    return { browser, page, needCode, intakeCode, crossCenterEnabled };
  } catch (error) {
    await browser.close();
    throw error;
  }
}

async function main() {
  await mkdir(evidenceDir, { recursive: true });
  await discoverPublishedApiKey();
  const credentialContents = await readFile(path.resolve(process.env.SANDBOX_CREDENTIALS_PATH), "utf8");
  const credentials = parseCredentials(credentialContents);
  const anon = createSandboxClient();
  const dashboardBefore = valueOf(success(
    "tablero público inicial",
    await anon.from("public_event_dashboard").select("active_needs,units_delivered,visible_donations,reconciled_balance").eq("event_id", EVENT_ID).single(),
  ));

  const sessions = {};
  for (const role of ["admin", "partner", "warehouse", "requester", "approver"]) {
    sessions[role] = await authenticatedClient(role, credentials);
  }
  const { client: admin } = sessions.admin;
  const { client: partner } = sessions.partner;
  const { client: warehouse } = sessions.warehouse;
  const { client: requester } = sessions.requester;
  const { client: approver } = sessions.approver;

  const ui = await submitViaPublishedUi(credentials);
  const { browser, page, needCode, intakeCode } = ui;
  evidence.artifacts.needTrackingCode = needCode;
  evidence.artifacts.inKindIntakeCode = intakeCode;
  evidence.artifacts.qrScreenshot = screenshotPath;

  try {
    const need = valueOf(success(
      "necesidad privada para verificación",
      await admin.from("need_cases").select("id,status,exact_address_private,contact_private").eq("tracking_code", needCode).single(),
    ));
    const needItem = valueOf(success(
      "artículo de necesidad",
      await admin.from("need_items").select("id,quantity_required,quantity_covered,category,unit").eq("need_case_id", need.id).single(),
    ));
    record("datos:necesidad-creada", need.status === "reported" && Number(needItem.quantity_required) === 10, { needId: need.id, needItemId: needItem.id });

    const anonPrivateAttempt = await anon.from("need_cases").select("id").eq("id", need.id);
    record("rls:anon-sin-registro-protegido", Boolean(anonPrivateAttempt.error), { denied: true });

    const partnerPrivateAttempt = await partner
      .from("need_cases")
      .select("id,exact_address_private,contact_private")
      .eq("id", need.id)
      .maybeSingle();
    if (!partnerPrivateAttempt.error && partnerPrivateAttempt.data?.exact_address_private) {
      issue(
        "NEED-PRIVATE-SCOPE",
        "critical",
        "Un aliado con rol partner_reporter puede leer la ubicación exacta y el contacto de una necesidad",
        { role: "partner_reporter", needId: need.id, privateValuesRecorded: false },
      );
    }

    success("verificación de necesidad", await admin.rpc("review_need_case", {
      p_need_id: need.id,
      p_decision: "verify",
      p_note: `Verificación sintética ${runId}`,
      p_confidence: 90,
      p_expires_at: null,
    }));
    success("publicación segura de necesidad", await admin.rpc("review_need_case", {
      p_need_id: need.id,
      p_decision: "publish",
      p_note: `Publicación sintética ${runId}`,
      p_confidence: 90,
      p_expires_at: null,
    }));
    const publishedNeed = valueOf(success(
      "proyección pública de necesidad",
      await anon.from("public_need_projections").select("source_need_id,status,needed_quantity,covered_quantity,latitude,longitude,published").eq("source_need_id", need.id).single(),
    ));
    record("operacion:necesidad-publicada", publishedNeed.published && Number(publishedNeed.covered_quantity) === 0, { status: publishedNeed.status });

    const intake = valueOf(success(
      "ingreso en especie",
      await admin.from("donation_intakes").select("id,status,preferred_location_id").eq("tracking_code", intakeCode).single(),
    ));
    record("datos:intake-en-especie", intake.status === "pending_verification" && intake.preferred_location_id === PARTNER_CENTER_ID, { intakeId: intake.id });
    const partnerReview = await partner.rpc("review_donation_intake", {
      p_intake_id: intake.id,
      p_decision: "approve",
      p_note: "Intento que debe ser rechazado",
    });
    record("rls:aliado-no-autoaprueba", denied(partnerReview), { denied: true });

    const donationId = success("aprobación independiente en especie", await admin.rpc("review_donation_intake", {
      p_intake_id: intake.id,
      p_decision: "approve",
      p_note: `Aprobación sintética ${runId}`,
    }));
    const donation = valueOf(success(
      "donación operacional en especie",
      await admin.from("donations").select("id,status,donor_tracking_code").eq("id", donationId).single(),
    ));
    const donationItem = valueOf(success(
      "artículo operacional",
      await warehouse.from("donation_items").select("id,category,unit,quantity_promised").eq("donation_id", donation.id).single(),
    ));
    evidence.artifacts.inKindDonationCode = donation.donor_tracking_code;

    const receiveKey = `${runId}-receive`;
    const lotId = success("recepción física", await warehouse.rpc("receive_donation", {
      p_donation_item_id: donationItem.id,
      p_location_id: PARTNER_CENTER_ID,
      p_accepted: 10,
      p_rejected: 0,
      p_condition: "sellado",
      p_idempotency_key: receiveKey,
    }));
    const repeatedLotId = success("reintento de recepción", await warehouse.rpc("receive_donation", {
      p_donation_item_id: donationItem.id,
      p_location_id: PARTNER_CENTER_ID,
      p_accepted: 10,
      p_rejected: 0,
      p_condition: "sellado",
      p_idempotency_key: receiveKey,
    }));
    record("idempotencia:recepcion", lotId === repeatedLotId, { lotId });

    const allocationKey = `${runId}-allocate`;
    const allocationId = success("asignación de inventario", await warehouse.rpc("allocate_stock", {
      p_lot_id: lotId,
      p_need_item_id: needItem.id,
      p_quantity: 10,
      p_idempotency_key: allocationKey,
    }));
    const repeatedAllocationId = success("reintento de asignación", await warehouse.rpc("allocate_stock", {
      p_lot_id: lotId,
      p_need_item_id: needItem.id,
      p_quantity: 10,
      p_idempotency_key: allocationKey,
    }));
    record("idempotencia:asignacion", allocationId === repeatedAllocationId, { allocationId });

    const shipmentKey = `${runId}-shipment`;
    const shipmentId = success("creación de despacho", await warehouse.rpc("create_shipment", {
      p_allocation_id: allocationId,
      p_public_destination: `Zona sintética ${runId}`,
      p_carrier_name: "Operador sintético",
      p_idempotency_key: shipmentKey,
    }));
    const repeatedShipmentId = success("reintento de despacho", await warehouse.rpc("create_shipment", {
      p_allocation_id: allocationId,
      p_public_destination: `Zona sintética ${runId}`,
      p_carrier_name: "Operador sintético",
      p_idempotency_key: shipmentKey,
    }));
    const shipment = valueOf(success(
      "despacho operacional",
      await warehouse.from("shipments").select("id,shipment_code,status").eq("id", shipmentId).single(),
    ));
    record("idempotencia:despacho", shipmentId === repeatedShipmentId, { shipmentId, shipmentCode: shipment.shipment_code });
    evidence.artifacts.shipmentCode = shipment.shipment_code;

    const deliveryKey = `${runId}-delivery`;
    const deliveryId = success("registro de entrega", await warehouse.rpc("register_delivery", {
      p_shipment_id: shipmentId,
      p_quantity_delivered: 10,
      p_quantity_damaged: 0,
      p_idempotency_key: deliveryKey,
    }));
    const repeatedDeliveryId = success("reintento de entrega", await warehouse.rpc("register_delivery", {
      p_shipment_id: shipmentId,
      p_quantity_delivered: 10,
      p_quantity_damaged: 0,
      p_idempotency_key: deliveryKey,
    }));
    record("idempotencia:entrega", deliveryId === repeatedDeliveryId, { deliveryId });

    const warehouseValidation = await warehouse.rpc("validate_delivery", {
      p_delivery_id: deliveryId,
      p_note: "Intento sin rol verificador",
    });
    record("rls:bodega-no-valida-entrega", denied(warehouseValidation), { denied: true });
    const validatedDonationId = success("validación independiente de entrega", await admin.rpc("validate_delivery", {
      p_delivery_id: deliveryId,
      p_note: `Validación sintética ${runId}`,
    }));
    const repeatedValidatedDonationId = success("reintento de validación", await admin.rpc("validate_delivery", {
      p_delivery_id: deliveryId,
      p_note: `Reintento sintético ${runId}`,
    }));
    record("idempotencia:validacion", validatedDonationId === repeatedValidatedDonationId && validatedDonationId === donation.id, { donationId: donation.id });

    const needAfter = valueOf(success(
      "necesidad cubierta",
      await admin.from("need_cases").select("status").eq("id", need.id).single(),
    ));
    const needProjectionAfter = valueOf(success(
      "cobertura pública",
      await anon.from("public_need_projections").select("status,covered_quantity,needed_quantity").eq("source_need_id", need.id).single(),
    ));
    record("operacion:entrega-cubre-necesidad", needAfter.status === "covered" && Number(needProjectionAfter.covered_quantity) === 10, {
      privateStatus: needAfter.status,
      publicStatus: needProjectionAfter.status,
    });

    const intakeTracking = valueOf(success("seguimiento del QR", await anon.rpc("track_public_code", { p_tracking_code: intakeCode })));
    const donationTracking = valueOf(success("seguimiento operacional", await anon.rpc("track_public_code", { p_tracking_code: donation.donor_tracking_code })));
    record("seguimiento:donacion-operacional-validada", donationTracking?.safe_status === "validated", { code: donation.donor_tracking_code, status: donationTracking?.safe_status });
    if (intakeTracking?.safe_status !== "validated") {
      issue(
        "QR-TRACKING-CONTINUITY",
        "high",
        "El QR entregado al donante sigue mostrando el intake aprobado y no la entrega validada",
        { qrCode: intakeCode, qrStatus: intakeTracking?.safe_status, operationalCodeDisclosedByQr: false },
      );
    }

    const catalogs = success("catálogos versionados", await anon.rpc("donation_flow_catalogs"));
    const catalogVersions = Object.fromEntries(catalogs.map((catalog) => [catalog.key, Number(catalog.version)]));
    const categories = catalogs.find((catalog) => catalog.key === "donation_categories")?.values_json ?? [];
    const moneyCategory = categories.find((category) => category.kind === "money");
    const inKindCategory = categories.find((category) => category.kind === "in_kind" && category.parent_category === "Agua");
    record("catalogos:contrato-completo", Boolean(moneyCategory?.value && inKindCategory?.value && Object.keys(catalogVersions).length === 7), { versions: catalogVersions });

    const moneyKey = `${runId}-money-intake`;
    const moneyPayload = {
      p_event_id: EVENT_ID,
      p_organization_id: PARTNER_ORG_ID,
      p_kind: "money",
      p_idempotency_key: moneyKey,
      p_donor_name_private: `Donante monetario sintético ${runId}`,
      p_contact_private: { email: `${runId.toLowerCase()}-money@example.invalid`, phone: "" },
      p_attribution_kind: "anonymous",
      p_public_attribution: "",
      p_attribution_authorized: false,
      p_declared_status: "comprometida",
      p_items: [],
      p_declared_amount: 500000,
      p_preferred_location_id: null,
      p_reporting_context: {
        donor_type: "empresa",
        economic_sector: "servicios_financieros",
        specific_destination: false,
        destination_note: "",
        destination_department: "",
        destination_municipality: "",
        estimated_beneficiaries: "",
        delivery_channel: "",
        internal_responsible: "",
        internal_contact: {},
        observations: `Ejercicio ${runId}`,
      },
      p_catalog_versions: catalogVersions,
      p_declared_category_code: moneyCategory.value,
      p_need_case_id: null,
    };
    const moneyIntake = valueOf(success("registro económico", await partner.rpc("submit_donation_intake_v2", moneyPayload)));
    const repeatedMoneyIntake = valueOf(success("reintento económico", await partner.rpc("submit_donation_intake_v2", moneyPayload)));
    record("idempotencia:intake-economico", moneyIntake.intake_id === repeatedMoneyIntake.intake_id && repeatedMoneyIntake.was_duplicate === true, {
      intakeId: moneyIntake.intake_id,
      trackingCode: moneyIntake.tracking_code,
    });
    evidence.artifacts.moneyIntakeCode = moneyIntake.tracking_code;

    const moneyDonationId = success("aprobación económica independiente", await admin.rpc("review_donation_intake", {
      p_intake_id: moneyIntake.intake_id,
      p_decision: "approve",
      p_note: `Aprobación monetaria sintética ${runId}`,
    }));
    const moneyDonation = valueOf(success(
      "donación económica operacional",
      await admin.from("donations").select("id,donor_tracking_code,status").eq("id", moneyDonationId).single(),
    ));
    evidence.artifacts.moneyDonationCode = moneyDonation.donor_tracking_code;

    const reconcileKey = `${runId}-reconcile`;
    const reconciliation = valueOf(success("conciliación del aporte", await approver.rpc("reconcile_money_donation", {
      p_donation_id: moneyDonation.id,
      p_fund_id: FUND_ID,
      p_provider_reference_private: `SOPORTE-SINTETICO-${runId}`,
      p_idempotency_key: reconcileKey,
    })));
    const repeatedReconciliation = valueOf(success("reintento de conciliación", await approver.rpc("reconcile_money_donation", {
      p_donation_id: moneyDonation.id,
      p_fund_id: FUND_ID,
      p_provider_reference_private: `SOPORTE-SINTETICO-${runId}`,
      p_idempotency_key: reconcileKey,
    })));
    record("idempotencia:conciliacion", reconciliation.transaction_id === repeatedReconciliation.transaction_id && repeatedReconciliation.was_duplicate === true, {
      transactionId: reconciliation.transaction_id,
    });

    const expenseId = success("solicitud de gasto", await requester.rpc("request_expense", {
      p_fund_id: FUND_ID,
      p_amount: 125000,
      p_purpose: `Compra sintética de insumos ${runId}`,
    }));
    const selfApproval = await requester.rpc("approve_expense", {
      p_expense_id: expenseId,
      p_decision: "approved",
      p_note: "Intento de autoaprobación",
    });
    record("segregacion:solicitante-no-aprueba", denied(selfApproval), { denied: true });
    const approvalStatus = success("aprobación separada del gasto", await approver.rpc("approve_expense", {
      p_expense_id: expenseId,
      p_decision: "approved",
      p_note: `Aprobación sintética ${runId}`,
    }));
    record("tesoreria:gasto-aprobado", approvalStatus === "approved", { expenseId });
    const paymentKey = `${runId}-payment`;
    const paymentTransactionId = success("pago contable sandbox", await approver.rpc("pay_expense", {
      p_expense_id: expenseId,
      p_idempotency_key: paymentKey,
    }));
    const repeatedPaymentTransactionId = success("reintento de pago contable", await approver.rpc("pay_expense", {
      p_expense_id: expenseId,
      p_idempotency_key: paymentKey,
    }));
    const expense = valueOf(success("estado final del gasto", await approver.from("expense_requests").select("status,amount").eq("id", expenseId).single()));
    record("idempotencia:pago", paymentTransactionId === repeatedPaymentTransactionId && expense.status === "paid", { paymentTransactionId, expenseStatus: expense.status });

    const publicMoney = valueOf(success(
      "proyección pública económica",
      await anon.from("public_donation_projections").select("public_code,kind,reconciled_amount,currency,operational_state").eq("donation_id", moneyDonation.id).is("donation_item_id", null).single(),
    ));
    record("transparencia:aporte-economico-conciliado", publicMoney.public_code === moneyDonation.donor_tracking_code && Number(publicMoney.reconciled_amount) === 500000, {
      publicCode: publicMoney.public_code,
      state: publicMoney.operational_state,
    });

    const crossCenterPayload = {
      ...moneyPayload,
      p_kind: "in_kind",
      p_idempotency_key: `${runId}-cross-center`,
      p_donor_name_private: `Prueba centro cruzado ${runId}`,
      p_contact_private: { email: `${runId.toLowerCase()}-center@example.invalid`, phone: "" },
      p_declared_amount: null,
      p_items: [{
        category: "Agua",
        category_code: inKindCategory.value,
        description: `Prueba sintética de centro cruzado ${runId}`,
        quantity: 1,
        unit: "litro",
        condition: "sellado",
        storage_requirement: "ambiente",
        declared_estimated_value_cop: null,
        expires_on: null,
      }],
      p_preferred_location_id: COORDINATION_CENTER_ID,
      p_declared_category_code: null,
      p_need_case_id: null,
    };
    const crossCenterAttempt = await partner.rpc("submit_donation_intake_v2", crossCenterPayload);
    if (!crossCenterAttempt.error) {
      const crossCenterIntake = valueOf(crossCenterAttempt.data);
      issue(
        "CENTER-TENANT-SERVER",
        "critical",
        "El servidor acepta un centro de otra organización, pero la recepción posterior exige que centro y donación pertenezcan al mismo tenant",
        { intakeId: crossCenterIntake.intake_id, partnerOrganizationId: PARTNER_ORG_ID, centerId: COORDINATION_CENTER_ID },
      );
      success("cierre compensatorio de prueba de centro", await admin.rpc("review_donation_intake", {
        p_intake_id: crossCenterIntake.intake_id,
        p_decision: "reject",
        p_note: `Rechazo compensatorio por centro fuera del tenant ${runId}`,
      }));
    } else {
      record("seguridad:servidor-rechaza-centro-ajeno", denied(crossCenterAttempt) || crossCenterAttempt.error.code === "22023", { denied: true });
    }

    const logistics = success("mapa logístico público", await anon.rpc("public_logistics_map", { p_event_id: EVENT_ID }));
    const centers = success("centros públicos", await anon.rpc("public_collection_centers", { p_event_id: EVENT_ID }));
    record("mapa:centros-publicados", centers.length >= 2, { count: centers.length });
    if (!logistics.some((entry) => entry.public_code === shipment.shipment_code)) {
      issue(
        "MAP-DISPATCH-MISSING",
        "high",
        "El despacho validado no aparece en el mapa porque el reporte ciudadano no obtiene coordenadas aproximadas publicables",
        { shipmentCode: shipment.shipment_code, needProjectionHasCoordinates: Boolean(publishedNeed.latitude && publishedNeed.longitude) },
      );
    }

    const inKindProjection = valueOf(success(
      "proyección pública en especie",
      await anon.from("public_donation_projections").select("public_code,kind,verified_quantity,unit,operational_state").eq("donation_item_id", donationItem.id).single(),
    ));
    record("transparencia:aporte-en-especie-validado", Number(inKindProjection.verified_quantity) === 10 && inKindProjection.operational_state === "validated", {
      publicCode: inKindProjection.public_code,
    });

    const privateNeedMarker = `${runId.toLowerCase()}-need@example.invalid`;
    const privateDonorMarker = `${runId.toLowerCase()}-donor@example.invalid`;
    await page.goto(`${APP_URL}/transparencia`, { waitUntil: "domcontentloaded" });
    await page.getByRole("heading", { name: "Dashboard de aportes verificados" }).waitFor();
    const transparencyHtml = await page.content();
    record(
      "privacidad:tablero-sin-contactos",
      !transparencyHtml.includes(privateNeedMarker) && !transparencyHtml.includes(privateDonorMarker),
      { privateValuesRecorded: false },
    );
    record(
      "ui:transparencia-muestra-validaciones",
      transparencyHtml.includes(inKindProjection.public_code) && transparencyHtml.includes(moneyDonation.donor_tracking_code),
      { inKindCode: inKindProjection.public_code, moneyCode: moneyDonation.donor_tracking_code },
    );

    await page.goto(`${APP_URL}/seguimiento?codigo=${encodeURIComponent(needCode)}`, { waitUntil: "domcontentloaded" });
    await waitForReactHandler(page, ".tracking-search button.button-dark");
    await page.getByRole("button", { name: "Ver mi recorrido" }).click();
    await page.getByRole("heading", { name: "Cubierto" }).waitFor();
    record("ui:seguimiento-necesidad-cubierta", true, { code: needCode });

    await page.goto(`${APP_URL}/seguimiento?codigo=${encodeURIComponent(intakeCode)}`, { waitUntil: "domcontentloaded" });
    await waitForReactHandler(page, ".tracking-search button.button-dark");
    await page.getByRole("button", { name: "Ver mi recorrido" }).click();
    await page.locator(".tracking-result").waitFor();
    const qrJourneyText = await page.locator(".tracking-result").innerText();
    record("ui:qr-consultable", qrJourneyText.includes(intakeCode), { code: intakeCode, finalIntakeStatus: intakeTracking?.safe_status });

    const healthResponse = await fetch(`${APP_URL}/api/health`, { redirect: "error" });
    const health = await healthResponse.json();
    record("publicacion:salud-conectada", healthResponse.ok && health.status === "ok" && health.checks?.database === "connected", { status: healthResponse.status });
    const exportResponse = await fetch(`${APP_URL}/api/exports/transparency.xlsx`, { redirect: "error" });
    const exportBytes = new Uint8Array(await exportResponse.arrayBuffer());
    record("publicacion:excel-seguro", exportResponse.ok && exportBytes.byteLength > 1000, { status: exportResponse.status, bytes: exportBytes.byteLength });

    const dashboardAfter = valueOf(success(
      "tablero público final",
      await anon.from("public_event_dashboard").select("active_needs,units_delivered,visible_donations,reconciled_balance").eq("event_id", EVENT_ID).single(),
    ));
    record("metricas:vista-dinamica-incorpora-entrega", Number(dashboardAfter.units_delivered) >= Number(dashboardBefore.units_delivered) + 10, {
      before: Number(dashboardBefore.units_delivered),
      after: Number(dashboardAfter.units_delivered),
    });
    const recentSnapshots = success(
      "cortes de métricas",
      await anon.from("public_metric_snapshots").select("metric_key,source_cut_at").eq("event_id", EVENT_ID).gte("source_cut_at", startedAt),
    );
    if (recentSnapshots.length === 0) {
      issue(
        "METRIC-SNAPSHOT-STALE",
        "medium",
        "La operación terminada no genera un nuevo corte conciliado; las tarjetas superiores de transparencia quedan desactualizadas",
        { runStartedAt: startedAt },
      );
    }

    const auditRows = success(
      "auditoría del ejercicio",
      await admin.from("audit_events").select("event_id,organization_id,action,entity_table,entity_id,actor_id,correlation_id,occurred_at").gte("occurred_at", startedAt).order("occurred_at"),
    );
    const auditedTables = new Set(auditRows.map((entry) => entry.entity_table));
    const requiredAuditTables = [
      "need_cases",
      "need_verifications",
      "donation_intakes",
      "intake_verification_decisions",
      "donations",
      "inventory_lots",
      "stock_movements",
      "allocations",
      "shipments",
      "deliveries",
      "financial_transactions",
      "expense_requests",
      "expense_approvals",
      "expense_payments",
    ];
    const missingAuditTables = requiredAuditTables.filter((table) => !auditedTables.has(table));
    record("auditoria:historial-critico-presente", auditRows.length > 0 && missingAuditTables.length === 0, {
      events: auditRows.length,
      missingTables: missingAuditTables,
      actors: new Set(auditRows.map((entry) => entry.actor_id).filter(Boolean)).size,
    });
    const eventlessAuditRows = auditRows.filter((entry) => !entry.event_id);
    const organizationlessAuditRows = auditRows.filter((entry) => !entry.organization_id);
    if (eventlessAuditRows.length > 0 || organizationlessAuditRows.length > 0) {
      issue(
        "AUDIT-TENANT-CONTEXT",
        "high",
        "Parte del historial append-only de tablas hijas queda sin evento u organización, lo que debilita el aislamiento y la investigación por tenant",
        {
          eventlessEvents: eventlessAuditRows.length,
          eventlessTables: Array.from(new Set(eventlessAuditRows.map((entry) => entry.entity_table))).sort(),
          organizationlessEvents: organizationlessAuditRows.length,
          organizationlessTables: Array.from(new Set(organizationlessAuditRows.map((entry) => entry.entity_table))).sort(),
        },
      );
    }
    const correlations = new Set(auditRows.map((entry) => entry.correlation_id));
    if (auditRows.length > 1 && correlations.size === auditRows.length) {
      issue(
        "AUDIT-CORRELATION",
        "medium",
        "Cada cambio tiene auditoría append-only, pero los cambios de una misma transacción no comparten un identificador de correlación",
        { auditEvents: auditRows.length, distinctCorrelationIds: correlations.size },
      );
    }

    evidence.artifacts.entities = {
      needId: need.id,
      inKindIntakeId: intake.id,
      inKindDonationId: donation.id,
      lotId,
      allocationId,
      shipmentId,
      deliveryId,
      moneyIntakeId: moneyIntake.intake_id,
      moneyDonationId: moneyDonation.id,
      reconciliationTransactionId: reconciliation.transaction_id,
      expenseId,
      paymentTransactionId,
    };
    evidence.artifacts.dashboard = { before: dashboardBefore, after: dashboardAfter };
    evidence.artifacts.auditEventCount = auditRows.length;
  } finally {
    await browser.close();
  }
}

try {
  await main();
  evidence.status = evidence.issues.some((entry) => entry.severity === "critical") ? "completed_with_critical_findings" : "completed";
} catch (error) {
  evidence.status = "failed";
  evidence.failure = { message: error instanceof Error ? error.message : String(error) };
  process.exitCode = 1;
} finally {
  evidence.finishedAt = new Date().toISOString();
  await mkdir(evidenceDir, { recursive: true });
  await writeFile(evidencePath, `${JSON.stringify(evidence, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
  console.log(`SIMULATION_STATUS=${evidence.status}`);
  console.log(`SIMULATION_RUN_ID=${runId}`);
  console.log(`SIMULATION_CHECKS=${evidence.checks.filter((entry) => entry.passed).length}/${evidence.checks.length}`);
  console.log(`SIMULATION_ISSUES=${evidence.issues.length}`);
  console.log(`SIMULATION_EVIDENCE=${evidencePath}`);
  if (evidence.failure) console.error(`SIMULATION_FAILURE=${evidence.failure.message}`);
}
