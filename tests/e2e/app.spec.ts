import { expect, test } from "@playwright/test";
import ExcelJS from "exceljs";

test.describe.configure({ mode: "serial" });

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
  await expect(page.locator(".maplibregl-canvas")).toBeVisible({ timeout: 10_000 });
  await expect(page.getByText("Actualización en vivo", { exact: true })).toBeVisible({ timeout: 10_000 });
  await expect(page.getByRole("heading", { name: "Acopio y despachos en tiempo real" })).toBeVisible();
  await expect(page.getByRole("button", { name: /Centro de acopio.*Centro de acopio Norte/ })).toBeVisible();
  await expect(page.getByRole("button", { name: /Despacho.*DSP-DEMO-MAPA-001.*Manizales.*Medellín.*En tránsito/ })).toBeVisible();
  await page.getByRole("button", { name: "Higiene", exact: true }).click();
  await expect(page.getByRole("button", { name: "Higiene", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByText("Kits de higiene familiar").first()).toBeVisible();

  await page.goto("/seguimiento");
  await page.getByRole("button", { name: "Usar un código de demostración" }).click();
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
  await page.getByRole("button", { name: "Ingresar de forma segura" }).click();
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

test("aporte guiado conserva pasos y genera ticket con QR", async ({ page }) => {
  await page.goto("/ingresar?next=/donar");
  await page.getByLabel("Correo").fill("aliado@rutasolidaria.local");
  await page.getByLabel("Contraseña").fill("RutaSolidaria2026!");
  await page.getByRole("button", { name: "Ingresar de forma segura" }).click();
  await expect(page).toHaveURL(/\/donar$/);

  await page.getByRole("button", { name: "Agua", exact: true }).click();
  await page.getByRole("button", { name: "Continuar", exact: true }).click();
  await page.getByLabel("¿Qué es?").fill("Botellas selladas para prueba E2E");
  await page.getByLabel("Cantidad", { exact: true }).fill("12");
  await page.getByLabel("Unidad", { exact: true }).selectOption("litro");
  await page.getByRole("button", { name: "Continuar", exact: true }).click();
  await expect(page.getByRole("heading", { name: "Destino y entrega" })).toBeVisible();
  await page.getByRole("button", { name: "Continuar", exact: true }).click();
  await page.getByLabel("Nombre de quien reporta").fill("Persona sintética E2E");
  await page.getByLabel("Correo de coordinación").fill("e2e@example.local");
  await page.getByRole("button", { name: "Continuar", exact: true }).click();
  await page.getByRole("checkbox").check();
  await page.getByRole("button", { name: "Confirmar aporte" }).click();

  await expect(page.getByRole("heading", { name: "Tu aporte ya tiene una ruta segura." })).toBeVisible();
  await expect(page.getByText(/APO-[A-F0-9]{24}/)).toBeVisible();
  await expect(page.getByText("Escanea para consultar el estado")).toBeVisible();
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
