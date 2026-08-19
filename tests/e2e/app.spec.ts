import { expect, test } from "@playwright/test";
import ExcelJS from "exceljs";

test.describe.configure({ mode: "serial" });

test("salud y cabeceras operativas son verificables", async ({ request }) => {
  const health = await request.get("/api/health", { headers: { "x-request-id": "e2e-health-check" } });
  expect(health.status()).toBe(200);
  expect(health.headers()["cache-control"]).toContain("no-store");
  expect(health.headers()["x-request-id"]).toBe("e2e-health-check");
  expect(health.headers()["server-timing"]).toMatch(/app;dur=/);
  await expect(health.json()).resolves.toMatchObject({ status: "ok", checks: { database: "connected" } });

  const portal = await request.get("/");
  expect(portal.headers()["x-content-type-options"]).toBe("nosniff");
  expect(portal.headers()["x-frame-options"]).toBe("DENY");
  expect(portal.headers()["cross-origin-opener-policy"]).toBe("same-origin");
  expect(portal.headers()["cross-origin-resource-policy"]).toBe("same-origin");
});

test("portal público muestra solo proyecciones verificadas", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: /Ayudar debe sentirse/ })).toBeVisible();
  await expect(page.getByRole("heading", { name: "¿Dónde hace falta ayuda?" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Centros de acopio cercanos" })).toBeVisible();
  await expect(page.getByText("Agua para albergue temporal").first()).toBeVisible();
  await expect(page.getByText("Reporte ciudadano ficticio en espera")).toHaveCount(0);
});

test("mapa filtra necesidades y seguimiento explica el recorrido", async ({ page }) => {
  await page.goto("/");
  // El respaldo cartográfico entra tras un temporizador de 4,5 s y carga su propio motor:
  // el margen cubre esa ruta cuando el estilo vectorial no está disponible.
  await expect(page.locator(".maplibregl-canvas, .leaflet-container")).toBeVisible({ timeout: 30_000 });
  const realMapEngine = await page.locator(".maplibregl-canvas, .leaflet-container").first().getAttribute("class");
  expect(realMapEngine).toMatch(/maplibregl-canvas|leaflet-container/);
  await expect(page.getByText("Actualización en vivo", { exact: true })).toBeVisible({ timeout: 10_000 });
  await expect(page.getByRole("heading", { name: "Acopio y despachos en tiempo real" })).toBeVisible();
  await expect(page.getByRole("button", { name: /Centro de acopio.*Centro de acopio Norte/ })).toBeVisible();
  await expect(page.getByRole("button", { name: /Despacho.*DSP-DEMO-MAPA-001.*Manizales.*Medellín.*En tránsito/ })).toBeVisible();
  await page.getByRole("button", { name: "Higiene", exact: true }).click();
  await expect(page.getByRole("button", { name: "Higiene", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByText("Kits de higiene familiar").first()).toBeVisible();

  await page.goto("/seguimiento");
  // El atajo al código de ejemplo solo existe mientras la instancia declare datos de
  // práctica. La prueba escribe el código para funcionar también en modo producción.
  const demoShortcut = page.getByRole("button", { name: "Usar un código de práctica" });
  if (await demoShortcut.count()) {
    await demoShortcut.click();
  } else {
    await page.getByLabel("Código de seguimiento").fill("NEC-A1B2C3D4E5F60718293A4B5C");
  }
  await page.getByRole("button", { name: "Ver mi recorrido" }).click();
  await expect(page.getByRole("heading", { name: "Publicado" })).toBeVisible();
  await expect(page.getByText("Necesidad verificada", { exact: true })).toBeVisible();
});

test("reporte ciudadano bloquea teléfono en campo público", async ({ page }) => {
  await page.goto("/reportar");
  await page.getByRole("radio", { name: "Agua" }).check();
  await page.getByLabel("Zona aproximada").fill("Zona de simulación");
  await page.getByLabel("Hechos observados").fill("Se requieren cincuenta unidades; llamar al 3001234567 para coordinar.");
  await page.getByLabel("Cantidad aproximada").fill("50");
  await page.getByLabel("Unidad").selectOption("unidad");
  await page.getByRole("checkbox").check();
  await page.getByRole("button", { name: "Enviar a verificación" }).click();
  await expect(page.locator(".form-error")).toContainText("No incluyas teléfonos");
});

test("reporte seguro genera código y no se publica", async ({ page }) => {
  await page.goto("/reportar");
  await page.getByRole("radio", { name: "Higiene" }).check();
  await page.getByLabel("Zona aproximada").fill("Pereira · ejercicio E2E");
  await page.getByLabel("Hechos observados").fill("El punto temporal ficticio requiere kits de higiene para veinte hogares del ejercicio.");
  await page.getByLabel("Cantidad aproximada").fill("20");
  await page.getByLabel("Unidad").selectOption("kit");
  await page.getByRole("checkbox").check();
  await page.getByRole("button", { name: "Enviar a verificación" }).click();
  await expect(page.getByRole("heading", { name: "Reporte recibido, aún no publicado." })).toBeVisible();
  await expect(page.getByText(/NEC-[A-F0-9]{24}/)).toBeVisible();
});

test("ingreso no publica cuentas ni credenciales de práctica", async ({ page }) => {
  await page.goto("/ingresar");
  await expect(page.getByText("Cuentas de práctica")).toHaveCount(0);
  await expect(page.getByText("admin@rutasolidaria.local")).toHaveCount(0);
  await expect(page.getByText("aliado@rutasolidaria.local")).toHaveCount(0);
  await expect(page.getByLabel("Correo")).toBeVisible();
  await expect(page.getByLabel("Contraseña")).toBeVisible();
  await expect(page.getByRole("link", { name: "Crea tu cuenta de aliado" })).toBeVisible();
});

test("Supabase Auth abre el centro operativo con rol y sin PII pública", async ({ page }) => {
  await page.goto("/ingresar");
  await page.getByLabel("Correo").fill("admin@rutasolidaria.local");
  await page.getByLabel("Contraseña").fill("RutaSolidaria2026!");
  await page.getByRole("button", { name: "Ingresar", exact: true }).click();
  await expect(page).toHaveURL(/\/operaciones$/);
  await expect(page.getByRole("heading", { name: /Buenos días, Ana/ })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Solicitudes pendientes de decisión" })).toBeVisible();
  await expect(page.getByText("Necesidad reportada por la ciudadanía").first()).toBeVisible();
  await expect(page.getByText(/Siguiente control:.*confirmar hechos/).first()).toBeVisible();
  await expect(page.getByRole("link", { name: "Bodega y logística" })).toBeVisible();
  const exportLink = page.getByRole("link", { name: "Exportar Excel" });
  await expect(exportLink).toHaveAttribute("href", "/api/exports/operations.xlsx");
  const downloadPromise = page.waitForEvent("download");
  await exportLink.click();
  const download = await downloadPromise;
  expect(download.suggestedFilename()).toBe("ruta-solidaria-operacion.xlsx");
  const downloadPath = await download.path();
  expect(downloadPath).toBeTruthy();
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.readFile(downloadPath!);
  expect(workbook.worksheets.map((sheet) => sheet.name)).toEqual(["Resumen", "Necesidades", "Aportes", "Artículos", "Inventario", "Finanzas"]);
  expect(String(workbook.getWorksheet("Resumen")?.getCell("A2").value)).not.toContain("admin@rutasolidaria.local");
  await expect(page.getByText("admin@rutasolidaria.local")).toHaveCount(1);
});

test("administración parametriza un punto de entrega sin exponer la dirección", async ({ page }) => {
  await page.goto("/ingresar?next=/operaciones/centros");
  await page.getByLabel("Correo").fill("admin@rutasolidaria.local");
  await page.getByLabel("Contraseña").fill("RutaSolidaria2026!");
  await page.getByRole("button", { name: "Ingresar", exact: true }).click();
  await expect(page).toHaveURL(/\/operaciones\/centros$/);

  await expect(page.getByRole("heading", { name: "Parametrizar puntos de entrega" })).toBeVisible();
  await page.getByLabel("Organización responsable").selectOption({ label: "Aliados Unidos Demo" });
  await page.getByLabel("Nombre operativo").fill("Punto parametrizado E2E");
  await page.getByLabel("Zona pública aproximada").fill("Cali · zona occidental de práctica");
  await page.getByLabel("Dirección exacta").fill("Dirección privada sintética E2E 123");
  await page.getByLabel("Instrucciones públicas (opcional)").fill("Coordina el horario después de recibir tu código APO.");
  await page.getByLabel("Agua", { exact: true }).check();
  await page.getByLabel("Higiene", { exact: true }).check();
  await page.getByLabel("Cuenta con cadena de frío").check();
  await page.getByRole("button", { name: "Crear punto de entrega" }).click();

  await expect(page.getByText("El punto de entrega quedó creado y auditado.")).toBeVisible();
  const point = page.locator(".delivery-point-row").filter({ hasText: "Punto parametrizado E2E" }).last();
  await expect(point).toContainText("Aliados Unidos Demo · Cali · zona occidental de práctica");
  await expect(point).toContainText("Agua, Higiene");
  await expect(point).toContainText("Coordina el horario después de recibir tu código APO.");
  await expect(point).not.toContainText("Dirección privada sintética E2E 123");
  await expect(point).toContainText("Solo acopio");

  // Un centro de despacho no declara categorías y no se publica como punto de recepción.
  await page.getByRole("button", { name: "Nuevo punto" }).click();
  await page.getByLabel("Organización responsable").selectOption({ label: "Aliados Unidos Demo" });
  await page.getByLabel("Nombre operativo").fill("Base de despacho E2E");
  await page.getByLabel("Zona pública aproximada").fill("Cali · salida sur de práctica");
  await page.getByLabel("Dirección exacta").fill("Dirección privada de despacho E2E 456");
  await page.getByLabel("Centro de acopio").uncheck();
  await page.getByLabel("Centro de despacho").check();
  await expect(page.getByRole("group", { name: "Categorías que recibe" })).toHaveCount(0);
  await page.getByRole("button", { name: "Crear punto de entrega" }).click();

  await expect(page.getByText("El punto de entrega quedó creado y auditado.")).toBeVisible();
  const dispatchPoint = page.locator(".delivery-point-row").filter({ hasText: "Base de despacho E2E" }).last();
  await expect(dispatchPoint).toContainText("Solo despacho");
  await expect(dispatchPoint).toContainText("No recibe aportes");
});

test("bodega guía recepción, compatibilidad y evidencia bloqueada", async ({ page }) => {
  await page.goto("/ingresar?next=/operaciones/bodega");
  await page.getByLabel("Correo").fill("bodega@rutasolidaria.local");
  await page.getByLabel("Contraseña").fill("RutaSolidaria2026!");
  await page.getByRole("button", { name: "Ingresar", exact: true }).click();
  await expect(page).toHaveURL(/\/operaciones\/bodega$/);

  await expect(page.getByRole("navigation", { name: "Etapas de bodega y logística" })).toBeVisible();
  await expect(page.getByRole("link", { name: /01 Recibir/ })).toBeVisible();
  await expect(page.getByRole("link", { name: /03 Trasladar/ })).toBeVisible();
  await page.getByLabel("Buscar aporte, categoría o artículo").fill("Agua");
  await expect(page.getByRole("heading", { name: /Recepciones pendientes/ })).toBeVisible();
  // La posición se lee del Kardex, no del saldo con el que nació el lote.
  await expect(page.getByText(/físico, disponible y reservado salen del Kardex/)).toBeVisible();
  await expect(page.getByRole("heading", { name: /Traslados entre bodegas/ })).toBeVisible();
  await expect(page.getByText("Sin escritura directa de stock", { exact: true })).toBeVisible();
  await expect(page.getByText(/todas salen de movimientos registrados en el Kardex/)).toBeVisible();
});

test("bodega exige el transporte antes de permitir una salida", async ({ page }) => {
  await page.goto("/ingresar?next=/operaciones/bodega");
  await page.getByLabel("Correo").fill("bodega@rutasolidaria.local");
  await page.getByLabel("Contraseña").fill("RutaSolidaria2026!");
  await page.getByRole("button", { name: "Ingresar", exact: true }).click();
  await expect(page).toHaveURL(/\/operaciones\/bodega$/);

  await expect(page.getByRole("heading", { name: /Preparar salida/ })).toBeVisible();
  await expect(page.getByText(/Sin datos de transporte completos el despacho no puede salir/)).toBeVisible();
  await expect(page.getByRole("heading", { name: /Movimiento/ })).toBeVisible();
  await expect(page.getByText(/Preparando → Despachado → En movimiento → Llegó → Recibido/)).toBeVisible();
});

test("el registro de aliado explica la confirmación de correo antes de operar", async ({ page }) => {
  await page.goto("/registro");
  await expect(page.getByRole("heading", { name: /Regístrate como aliado/ })).toBeVisible();
  await expect(page.getByLabel("Identificación o NIT")).toBeVisible();
  await expect(page.getByLabel("Zona pública desde la que entregas")).toBeVisible();
  await expect(page.getByText(/Al confirmar se crea tu organización con el rol ALIADO/)).toBeVisible();
  await expect(page.getByText(/Antes de confirmar, la cuenta no puede registrar aportes/)).toBeVisible();
  // Un solo registro para todos los perfiles: no hay un formulario por tipo de aliado.
  await expect(page.getByLabel("¿Quién aporta?")).toBeVisible();
});

test("reportes operativos derivan del Kardex y exigen rol", async ({ page }) => {
  await page.goto("/ingresar?next=/operaciones/reportes");
  await page.getByLabel("Correo").fill("bodega@rutasolidaria.local");
  await page.getByLabel("Contraseña").fill("RutaSolidaria2026!");
  await page.getByRole("button", { name: "Ingresar", exact: true }).click();
  await expect(page).toHaveURL(/\/operaciones\/reportes$/);

  await expect(page.getByRole("heading", { name: /Estado global del inventario/ })).toBeVisible();
  await expect(page.getByRole("heading", { name: /Reservas vigentes/ })).toBeVisible();
  await expect(page.getByRole("heading", { name: /Productos en movimiento/ })).toBeVisible();
  await expect(page.getByRole("heading", { name: /Donaciones asociadas a necesidades/ })).toBeVisible();
  await expect(page.getByRole("heading", { name: /Historial de movimientos/ })).toBeVisible();
});

test("aporte guiado conserva pasos y genera ticket con QR", async ({ page }) => {
  await page.goto("/ingresar?next=/donar");
  await page.getByLabel("Correo").fill("aliado@rutasolidaria.local");
  await page.getByLabel("Contraseña").fill("RutaSolidaria2026!");
  await page.getByRole("button", { name: "Ingresar", exact: true }).click();
  await expect(page).toHaveURL(/\/donar$/);

  await expect(page.getByText("Paso 1 de 4")).toBeVisible();
  await page.getByRole("button", { name: "Agua potable", exact: true }).click();
  await page.getByLabel("¿Qué es?").fill("Botellas selladas para prueba E2E");
  await page.locator("#quantity-0").fill("12");
  await page.locator("#unit-0").selectOption("litro");
  await page.getByRole("button", { name: "Continuar", exact: true }).click();
  await expect(page.getByRole("heading", { name: "¿Dónde lo entregas?" })).toBeVisible();
  await expect(page.getByRole("button", { name: /Centro aliado temporal.*Recibe Agua/ })).toBeEnabled();
  await page.getByRole("button", { name: "Continuar", exact: true }).click();
  await page.getByLabel("Nombre del donante (empresa o persona)").fill("Empresa donante sintética E2E");
  await page.getByLabel("Correo de coordinación").fill("e2e@example.local");
  await page.getByRole("button", { name: /Más datos internos/ }).click();
  await page.getByLabel("Tipo de donante").selectOption("empresa");
  await page.getByLabel("Sector económico").selectOption("alimentos_bebidas");
  await page.getByLabel("Aliado relacionado con el aporte").selectOption("propacifico");
  await page.getByLabel("Evidencia fotográfica (opcional y privada)").setInputFiles({
    name: "evidencia-sintetica-e2e.png",
    mimeType: "image/png",
    buffer: Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", "base64"),
  });
  await page.getByRole("button", { name: "Continuar", exact: true }).click();
  await expect(page.getByRole("heading", { name: "Revisa la solicitud antes de enviarla" })).toBeVisible();
  await expect(page.getByText(/No es una solicitud de ayuda, un recibo ni una confirmación de entrega/)).toBeVisible();
  await expect(page.getByText("Se podrá publicar tras verificar")).toBeVisible();
  await expect(page.getByText("Permanece privado")).toBeVisible();
  await expect(page.getByText("Nombre legal, correo y teléfono")).toBeVisible();
  await expect(page.getByText("PROPACIFICO", { exact: true })).toBeVisible();
  await expect(page.getByText(/1 foto seleccionada.*después de crear el código/)).toBeVisible();
  await page.getByRole("checkbox").check();
  await page.getByRole("button", { name: "Confirmar aporte" }).click();

  await expect(page.getByRole("heading", { name: "Tu aporte quedó reportado con un código." })).toBeVisible();
  await expect(page.getByText(/APO-[A-F0-9]{24}/)).toBeVisible();
  await expect(page.getByText("Escanea para consultar el estado")).toBeVisible();
  await expect(page.getByText(/La fotografía quedó vinculada.*privada/)).toBeVisible();
});

test("AYUDAR abre el aporte contra la necesidad y admite una parte de lo que falta", async ({ page }) => {
  await page.goto("/");
  const helpLink = page.getByRole("link", { name: /Quiero ayudar/ }).first();
  await expect(helpLink).toHaveAttribute("href", /\/donar\?necesidad=/);
  await expect(page.getByText(/Solicitado .* comprometido .* entregado/).first()).toBeVisible();

  await page.goto("/ingresar?next=/donar");
  await page.getByLabel("Correo").fill("aliado@rutasolidaria.local");
  await page.getByLabel("Contraseña").fill("RutaSolidaria2026!");
  await page.getByRole("button", { name: "Ingresar", exact: true }).click();
  await expect(page).toHaveURL(/\/donar$/);

  await page.goto("/donar?necesidad=62000000-0000-0000-0000-000000000001");
  await expect(page.getByText(/Estás ayudando a la necesidad NEC-/)).toBeVisible();
  await expect(page.getByText(/Puedes aportar una parte de lo que falta/)).toBeVisible();
  // La necesidad fija la unidad del aporte: el aliado solo decide cuánto.
  await expect(page.locator("#unit-0")).toBeDisabled();
  await page.locator("#quantity-0").fill("25");
  await page.getByRole("button", { name: "Continuar", exact: true }).click();
  await expect(page.getByRole("heading", { name: "¿Dónde lo entregas?" })).toBeVisible();
  await expect(page.getByRole("button", { name: /Ordenar por cercanía/ })).toBeVisible();
});

test("aporte económico pasa de declaración privada a conciliación pública", async ({ page }) => {
  await page.goto("/ingresar?next=/donar");
  await page.getByLabel("Correo").fill("aliado@rutasolidaria.local");
  await page.getByLabel("Contraseña").fill("RutaSolidaria2026!");
  await page.getByRole("button", { name: "Ingresar", exact: true }).click();

  await page.getByRole("button", { name: "Aporte económico" }).click();
  await expect(page.getByText("Paso 1 de 3")).toBeVisible();
  await page.getByLabel("Monto declarado (COP)").fill("275000");
  await page.getByLabel("Situación actual del aporte").selectOption("entregada");
  await page.getByRole("button", { name: "Continuar", exact: true }).click();
  await page.getByLabel("Nombre del donante (empresa o persona)").fill("Empresa monetaria sintética E2E");
  await page.getByLabel("Correo de coordinación").fill("money-e2e@example.local");
  await page.getByLabel("¿Cómo quieres aparecer públicamente?").selectOption("organization");
  await page.getByRole("button", { name: "Continuar", exact: true }).click();
  await expect(page.getByText("Cantidad recibida o monto conciliado")).toBeVisible();
  await page.getByRole("checkbox").check();
  await page.getByRole("button", { name: "Confirmar aporte" }).click();

  const intakeCode = await page.locator(".ticket-code strong").textContent();
  expect(intakeCode).toMatch(/APO-[A-F0-9]{24}/);

  await page.goto("/operaciones");
  if (!page.url().includes("/ingresar")) {
    await page.getByRole("button", { name: "Cerrar sesión" }).click();
  }
  await page.goto("/ingresar");
  await page.getByLabel("Correo").fill("admin@rutasolidaria.local");
  await page.getByLabel("Contraseña").fill("RutaSolidaria2026!");
  await page.getByRole("button", { name: "Ingresar", exact: true }).click();

  const intakeRow = page.locator(".ops-row").filter({ hasText: intakeCode! });
  await intakeRow.getByRole("button", { name: "Aprobar" }).click();
  await page.goto("/operaciones/tesoreria");
  const moneyRow = page.locator(".ops-row").filter({ hasText: intakeCode! });
  await expect(moneyRow).toBeVisible();
  const operationalCode = (await moneyRow.textContent())?.match(/DON-[A-F0-9]{24}/)?.[0];
  expect(operationalCode).toMatch(/DON-[A-F0-9]{24}/);
  await moneyRow.getByLabel("Referencia del soporte").fill(`SUPPORT-${operationalCode}`);
  await moneyRow.getByRole("button", { name: "Conciliar aporte" }).click();
  await expect(page.getByText(/Aporte conciliado.*El monto ya es público; la referencia del soporte no/)).toBeVisible();
  // El saldo sale del libro completo, no de la lista visible.
  await expect(page.getByText(/movimientos del libro completo/)).toBeVisible();

  await page.goto("/transparencia");
  await expect(page.getByRole("heading", { name: "Dashboard de aportes verificados" })).toBeVisible();
  await expect(page.getByText(operationalCode!, { exact: true })).toBeVisible();
});

test("portada no desborda en móvil", async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 800 });
  await page.goto("/");
  const widths = await page.evaluate(() => ({ viewport: window.innerWidth, document: document.documentElement.scrollWidth }));
  expect(widths.document).toBeLessThanOrEqual(widths.viewport);
  await expect(page.getByRole("heading", { name: /Ayudar debe sentirse/ })).toBeVisible();
});

test("dashboard público ofrece filtros, tabla accesible y Excel seguro", async ({ page, request }) => {
  await page.goto("/transparencia");
  await expect(page.getByRole("heading", { name: "Dashboard de cobertura" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Dashboard de aportes verificados" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Todas" })).toHaveAttribute("aria-pressed", "true");
  const dashboardTable = page.getByRole("table").first();
  await expect(dashboardTable).toContainText("Agua para albergue temporal");
  await page.getByRole("button", { name: "Higiene", exact: true }).click();
  await expect(page.getByRole("button", { name: "Higiene", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(dashboardTable).toContainText("Kits de higiene familiar");
  await expect(dashboardTable).not.toContainText("Agua para albergue temporal");
  await expect(page.getByText("Aliados y marcas bajo autorización")).toBeVisible();

  const response = await request.get("/api/exports/transparency.xlsx");
  expect(response.status()).toBe(200);
  expect(response.headers()["content-type"]).toContain("spreadsheetml.sheet");
  expect(response.headers()["content-disposition"]).toContain("ruta-solidaria-transparencia.xlsx");
  const body = await response.body();
  expect(body.subarray(0, 2).toString()).toBe("PK");
  const workbook = new ExcelJS.Workbook();
  const arrayBuffer = body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength) as ArrayBuffer;
  await workbook.xlsx.load(arrayBuffer);
  expect(workbook.worksheets.map((sheet) => sheet.name)).toEqual(["Resumen", "Necesidades", "Aportes públicos", "Centros", "Metodología"]);
  expect(workbook.getWorksheet("Necesidades")?.getCell("H5").value).toMatchObject({ formula: expect.stringContaining("IFERROR") });
});

test("Excel operativo bloquea visitantes sin sesión", async ({ request }) => {
  const response = await request.get("/api/exports/operations.xlsx");
  expect(response.status()).toBe(401);
});

/**
 * G-028 · Ciclo «observar → corregir → volver a verificación».
 *
 * Antes de la migración 202608170006 este recorrido no existía: el verificador
 * dejaba el aporte en «Con observaciones» y el aliado no tenía superficie para
 * responder, así que el ingreso quedaba atrapado sin salida.
 *
 * La prueba crea su propio aporte por la interfaz real: el seed no trae
 * ninguno, así que depender de datos previos la haría frágil.
 */
async function entrarComo(page: import("@playwright/test").Page, correo: string, destino = "/operaciones") {
  await page.goto("/operaciones");
  if (!page.url().includes("/ingresar")) {
    await page.getByRole("button", { name: "Cerrar sesión" }).click();
  }
  await page.goto(`/ingresar?next=${destino}`);
  await page.getByLabel("Correo").fill(correo);
  await page.getByLabel("Contraseña").fill("RutaSolidaria2026!");
  await page.getByRole("button", { name: "Ingresar", exact: true }).click();
  await expect(page).toHaveURL(new RegExp(`${destino.replace("/", "\/")}$`));
}

test("aliado responde una observación y el aporte vuelve a verificación", async ({ page }) => {
  // 1. El aliado registra un aporte con una cantidad que después se corrige.
  await entrarComo(page, "aliado@rutasolidaria.local", "/donar");
  await page.getByRole("button", { name: "Agua potable", exact: true }).click();
  await page.getByLabel("¿Qué es?").fill("Botellas selladas para el ciclo de corrección");
  await page.locator("#quantity-0").fill("100");
  await page.locator("#unit-0").selectOption("litro");
  await page.getByRole("button", { name: "Continuar", exact: true }).click();
  await page.getByRole("button", { name: "Continuar", exact: true }).click();
  await page.getByLabel("Nombre del donante (empresa o persona)").fill("Empresa donante del ciclo G-028");
  await page.getByLabel("Correo de coordinación").fill("g028@example.local");
  await page.getByRole("button", { name: "Continuar", exact: true }).click();
  await page.getByRole("checkbox").check();
  await page.getByRole("button", { name: "Confirmar aporte" }).click();
  const codigoAporte = (await page.locator(".ticket-code strong").textContent())?.trim();
  expect(codigoAporte).toMatch(/APO-[A-F0-9]{24}/);

  // 2. Verificación observa ESE aporte: la página también lista necesidades,
  // que tienen sus propios botones con el mismo nombre.
  await entrarComo(page, "admin@rutasolidaria.local");
  const filaAporte = page.locator(".ops-row").filter({ hasText: codigoAporte! });
  await expect(filaAporte).toBeVisible();
  await filaAporte.getByRole("button", { name: "Observar" }).click();
  await expect(filaAporte.getByText("Con observaciones")).toBeVisible({ timeout: 15000 });

  // 3. El aliado encuentra la observación en su propia cola y responde.
  await entrarComo(page, "aliado@rutasolidaria.local");
  const bloque = page.locator("#aportes-observados");
  await expect(bloque).toBeVisible();
  await expect(bloque.getByText("Observación de verificación:").first()).toBeVisible();

  await bloque.getByRole("button", { name: "Responder y corregir" }).first().click();
  const respuesta = bloque.getByRole("textbox").last();

  // La respuesta pasa por el mismo filtro de contenido sensible que el resto.
  await respuesta.fill("Escríbeme al 300 123 4567 y coordinamos");
  await bloque.getByRole("button", { name: "Enviar corrección" }).click();
  await expect(bloque.locator(".field-error")).toBeVisible({ timeout: 15000 });

  // 4. Con una respuesta válida el aporte sale de esta cola y vuelve a la de verificación.
  await respuesta.fill("Cantidad ajustada contra la remisión física 0012");
  await bloque.getByRole("button", { name: "Enviar corrección" }).click();
  await expect(page.locator("#aportes-observados")).toBeHidden({ timeout: 15000 });
});
