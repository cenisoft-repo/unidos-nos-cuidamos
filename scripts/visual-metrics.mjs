/**
 * Captura métricas de maquetación en varios anchos para comparar antes y después
 * de un cambio visual. No sustituye una revisión humana: detecta desbordes,
 * desplazamientos de bloques y pérdidas de contraste estructural.
 *
 *   node scripts/visual-metrics.mjs > antes.json
 *   node scripts/visual-metrics.mjs > despues.json
 *   node scripts/visual-metrics.mjs --diff antes.json despues.json
 */
import { chromium } from "@playwright/test";
import { readFileSync } from "node:fs";
import { RUTAS_PUBLICAS, abrirSesion, cerrarSesion, planAutenticado } from "./lib/rutas-auditadas.mjs";

const BASE = process.env.METRICS_BASE_URL ?? "http://127.0.0.1:3000";
const PAGES = RUTAS_PUBLICAS;
const WIDTHS = [1440, 1280, 1024, 768, 390];
// Las cuatro últimas son la maquetación real de las consolas —comprobadas en
// `operaciones/page.tsx`, `warehouse-console.tsx` y `treasury-console.tsx`—:
// sin sondas propias, las rutas autenticadas solo aportarían desborde y alto.
const PROBES = [
  ".site-header", ".site-footer", "h1", ".button", ".form-card", ".need-card",
  ".ops-shell", ".ops-panel", ".ops-row", ".ops-kpi",
];

const MEDIR = (probes) => {
  const round = (value) => Math.round(value);
  const box = (selector) => {
    const node = document.querySelector(selector);
    if (!node) return null;
    const rect = node.getBoundingClientRect();
    const style = getComputedStyle(node);
    return {
      w: round(rect.width),
      h: round(rect.height),
      radius: style.borderRadius,
      size: style.fontSize,
    };
  };
  return {
    desborde: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    alto: round(document.documentElement.scrollHeight),
    sondas: Object.fromEntries(probes.map((selector) => [selector, box(selector)])),
  };
};

async function capture() {
  const browser = await chromium.launch();
  const result = {};
  const plan = planAutenticado(BASE);
  for (const width of WIDTHS) {
    const page = await browser.newPage({ viewport: { width, height: 900 } });
    for (const path of PAGES) {
      await page.goto(`${BASE}${path}`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(1200);
      result[`${width}${path}`] = await page.evaluate(MEDIR, PROBES);
    }

    for (const { clave, ruta, correo } of plan.rutas) {
      await cerrarSesion(page, BASE);
      await abrirSesion(page, BASE, correo, ruta);
      await page.waitForTimeout(1200);
      result[`${width}${clave}`] = await page.evaluate(MEDIR, PROBES);
    }
    if (plan.rutas.length) await cerrarSesion(page, BASE);

    await page.close();
  }
  await browser.close();
  result.__cobertura = { publicas: PAGES.length, autenticadas: plan.rutas.length, autenticadasOmitidas: plan.omitido };
  return result;
}

function diff(beforePath, afterPath) {
  const before = JSON.parse(readFileSync(beforePath, "utf8"));
  const after = JSON.parse(readFileSync(afterPath, "utf8"));
  const changes = [];
  for (const key of Object.keys(before)) {
    if (key.startsWith("__")) continue; // metadatos de cobertura, no una medición
    const a = before[key];
    const b = after[key];
    if (!b) continue;
    if (a.desborde !== b.desborde) changes.push(`${key}: desborde ${a.desborde} → ${b.desborde}`);
    const deltaAlto = Math.abs(a.alto - b.alto);
    if (deltaAlto > 24) changes.push(`${key}: alto ${a.alto} → ${b.alto}`);
    for (const [selector, boxBefore] of Object.entries(a.sondas)) {
      const boxAfter = b.sondas[selector];
      if (!boxBefore || !boxAfter) continue;
      if (Math.abs(boxBefore.w - boxAfter.w) > 4 || Math.abs(boxBefore.h - boxAfter.h) > 8) {
        changes.push(`${key} ${selector}: ${boxBefore.w}x${boxBefore.h} → ${boxAfter.w}x${boxAfter.h}`);
      }
    }
  }
  const desbordes = Object.entries(after).filter(([key, value]) => !key.startsWith("__") && value.desborde > 0);
  // Si la captura nueva cubre menos rutas que la anterior, el diff mira menos
  // superficie y «sin regresiones» significaría menos de lo que aparenta.
  const perdidas = Object.keys(before).filter((key) => !key.startsWith("__") && !(key in after));
  console.log(JSON.stringify({
    cambiosRelevantes: changes,
    desbordesHorizontales: desbordes.map(([key, value]) => `${key}: ${value.desborde}px`),
    rutasSinMedirEnLaCapturaNueva: perdidas,
    cobertura: after.__cobertura ?? null,
    veredicto: changes.length === 0 && desbordes.length === 0 && perdidas.length === 0
      ? "sin regresiones detectadas"
      : "revisar",
  }, null, 2));
}

if (process.argv[2] === "--diff") {
  diff(process.argv[3], process.argv[4]);
} else {
  console.log(JSON.stringify(await capture(), null, 2));
}
