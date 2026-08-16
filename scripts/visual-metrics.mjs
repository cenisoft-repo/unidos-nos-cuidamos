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

const BASE = process.env.METRICS_BASE_URL ?? "http://127.0.0.1:3000";
const PAGES = ["/", "/donar", "/reportar", "/seguimiento", "/transparencia", "/ingresar"];
const WIDTHS = [1440, 1280, 1024, 768, 390];
const PROBES = [".site-header", ".site-footer", "h1", ".button", ".form-card", ".need-card"];

async function capture() {
  const browser = await chromium.launch();
  const result = {};
  for (const width of WIDTHS) {
    const page = await browser.newPage({ viewport: { width, height: 900 } });
    for (const path of PAGES) {
      await page.goto(`${BASE}${path}`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(1200);
      result[`${width}${path}`] = await page.evaluate((probes) => {
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
      }, PROBES);
    }
    await page.close();
  }
  await browser.close();
  return result;
}

function diff(beforePath, afterPath) {
  const before = JSON.parse(readFileSync(beforePath, "utf8"));
  const after = JSON.parse(readFileSync(afterPath, "utf8"));
  const changes = [];
  for (const key of Object.keys(before)) {
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
  const desbordes = Object.entries(after).filter(([, value]) => value.desborde > 0);
  console.log(JSON.stringify({
    cambiosRelevantes: changes,
    desbordesHorizontales: desbordes.map(([key, value]) => `${key}: ${value.desborde}px`),
    veredicto: changes.length === 0 && desbordes.length === 0 ? "sin regresiones detectadas" : "revisar",
  }, null, 2));
}

if (process.argv[2] === "--diff") {
  diff(process.argv[3], process.argv[4]);
} else {
  console.log(JSON.stringify(await capture(), null, 2));
}
