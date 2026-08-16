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
  await page.getByRole("button", { name: "Usar un código de práctica" }).click();
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

test("Supabase Auth abre el centro operativo con rol y sin PII pública", async ({ page }) => {
  await page.goto("/ingresar");
  await page.getByLabel("Correo").fill("admin@rutasolidaria.local");
  await page.getByLabel("Contraseña").fill("RutaSolidaria2026!");
  await page.getByRole("button", { name: "Ingresar", exact: true }).click();
  await expect(page).toHaveURL(/\/operaciones$/);
  await expect(page.getByRole("heading", { name: /Buenos días, Ana/ })).toBeVisible();
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

test("bodega guía recepción, compatibilidad y evidencia bloqueada", async ({ page }) => {
  await page.goto("/ingresar?next=/operaciones/bodega");
  await page.getByLabel("Correo").fill("bodega@rutasolidaria.local");
  await page.getByLabel("Contraseña").fill("RutaSolidaria2026!");
  await page.getByRole("button", { name: "Ingresar", exact: true }).click();
  await expect(page).toHaveURL(/\/operaciones\/bodega$/);

  await expect(page.getByRole("navigation", { name: "Etapas de bodega y logística" })).toBeVisible();
  await expect(page.getByRole("link", { name: /01 Recibir/ })).toBeVisible();
  await page.getByLabel("Buscar aporte, categoría o artículo").fill("Agua");
  await expect(page.getByRole("heading", { name: /Recepciones pendientes/ })).toBeVisible();
  await expect(page.getByText("Solo se muestran necesidades con categoría y unidad compatibles.")).toBeVisible();
  await expect(page.getByText("Evidencia privada", { exact: true })).toBeVisible();
  await expect(page.getByText(/carga de fotos y documentos aún no está disponible/)).toBeVisible();
});

test("aporte guiado conserva pasos y genera ticket con QR", async ({ page }) => {
  await page.goto("/ingresar?next=/donar");
  await page.getByLabel("Correo").fill("aliado@rutasolidaria.local");
  await page.getByLabel("Contraseña").fill("RutaSolidaria2026!");
  await page.getByRole("button", { name: "Ingresar", exact: true }).click();
  await expect(page).toHaveURL(/\/donar$/);

  await page.getByRole("button", { name: "Agua", exact: true }).click();
  await page.getByRole("button", { name: "Continuar", exact: true }).click();
  await page.getByLabel("¿Qué es?").fill("Botellas selladas para prueba E2E");
  await page.locator("#quantity-0").fill("12");
  await page.locator("#unit-0").selectOption("litro");
  await page.getByRole("button", { name: "Continuar", exact: true }).click();
  await expect(page.getByRole("heading", { name: "Destino y entrega" })).toBeVisible();
  await page.getByRole("button", { name: "Continuar", exact: true }).click();
  await page.getByLabel("Nombre del donante (empresa o persona)").fill("Empresa donante sintética E2E");
  await page.getByLabel("Correo de coordinación").fill("e2e@example.local");
  await page.getByRole("button", { name: "Continuar", exact: true }).click();
  await expect(page.getByText("Se podrá publicar tras verificar")).toBeVisible();
  await expect(page.getByText("Permanece privado")).toBeVisible();
  await expect(page.getByText("Nombre legal, correo y teléfono")).toBeVisible();
  await page.getByRole("checkbox").check();
  await page.getByRole("button", { name: "Confirmar aporte" }).click();

  await expect(page.getByRole("heading", { name: "Tu aporte ya tiene una ruta segura." })).toBeVisible();
  await expect(page.getByText(/APO-[A-F0-9]{24}/)).toBeVisible();
  await expect(page.getByText("Escanea para consultar el estado")).toBeVisible();
});

test("aporte económico pasa de declaración privada a conciliación pública", async ({ page }) => {
  await page.goto("/ingresar?next=/donar");
  await page.getByLabel("Correo").fill("aliado@rutasolidaria.local");
  await page.getByLabel("Contraseña").fill("RutaSolidaria2026!");
  await page.getByRole("button", { name: "Ingresar", exact: true }).click();

  await page.getByRole("button", { name: "Aporte económico" }).click();
  await page.getByRole("button", { name: "Continuar", exact: true }).click();
  await page.getByLabel("Monto declarado (COP)").fill("275000");
  await page.getByRole("button", { name: "Continuar", exact: true }).click();
  await page.getByLabel("Estado declarado del aporte").selectOption("entregada_por_validar");
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
  await expect(page.getByText("Aporte conciliado y publicado.")).toBeVisible();

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
