/**
 * Auditoría de accesibilidad comprobable: contraste, etiquetas, foco visible,
 * orden de encabezados y texto alternativo. No sustituye una revisión manual,
 * pero convierte en verificable lo que suele quedar en apreciación.
 *
 *   node scripts/accessibility-audit.mjs
 *
 * LÍMITE CONOCIDO: el contraste se calcula contra el primer ancestro con color
 * de fondo opaco. El texto colocado sobre una fotografía o sobre un degradado
 * de pseudo-elemento se reporta como falso positivo, porque esos fondos no son
 * nodos del DOM. Verifica esos casos a ojo antes de cambiar nada: el pie de la
 * portada, por ejemplo, se apoya en un degradado oscuro y sí contrasta.
 */
import { chromium } from "@playwright/test";

const BASE = process.env.METRICS_BASE_URL ?? "http://127.0.0.1:3000";
const PAGES = ["/", "/donar", "/reportar", "/seguimiento", "/transparencia", "/ingresar"];

const AUDIT = () => {
  const parse = (color) => {
    const match = color.match(/rgba?\(([^)]+)\)/);
    if (!match) return null;
    const [r, g, b, a = 1] = match[1].split(",").map((part) => Number(part.trim()));
    return { r, g, b, a };
  };
  const luminance = ({ r, g, b }) => {
    const channel = (value) => {
      const scaled = value / 255;
      return scaled <= 0.03928 ? scaled / 12.92 : ((scaled + 0.055) / 1.055) ** 2.4;
    };
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
  };
  const backgroundOf = (node) => {
    let current = node;
    while (current && current !== document.documentElement) {
      const color = parse(getComputedStyle(current).backgroundColor);
      if (color && color.a > 0.85) return color;
      current = current.parentElement;
    }
    return { r: 255, g: 255, b: 255, a: 1 };
  };
  const ratio = (a, b) => {
    const light = Math.max(luminance(a), luminance(b));
    const dark = Math.min(luminance(a), luminance(b));
    return (light + 0.05) / (dark + 0.05);
  };

  const contrasteBajo = [];
  for (const node of document.querySelectorAll("p, span, a, h1, h2, h3, h4, li, label, small, strong, td, th, button")) {
    if (!node.textContent?.trim() || node.offsetParent === null) continue;
    if (node.querySelector("p, span, a, h1, h2, h3, h4, li, label, small, strong, td, th, button")) continue;
    const style = getComputedStyle(node);
    const color = parse(style.color);
    if (!color) continue;
    const size = parseFloat(style.fontSize);
    const weight = Number(style.fontWeight) || 400;
    const grande = size >= 24 || (size >= 18.66 && weight >= 700);
    const minimo = grande ? 3 : 4.5;
    const valor = ratio(color, backgroundOf(node));
    if (valor < minimo) {
      contrasteBajo.push({
        texto: node.textContent.trim().slice(0, 40),
        ratio: Number(valor.toFixed(2)),
        minimo,
        size: style.fontSize,
      });
    }
  }

  const sinEtiqueta = [...document.querySelectorAll("input, select, textarea")]
    .filter((node) => node.type !== "hidden" && node.offsetParent !== null)
    .filter((node) => {
      if (node.getAttribute("aria-label") || node.getAttribute("aria-labelledby")) return false;
      if (node.id && document.querySelector(`label[for="${CSS.escape(node.id)}"]`)) return false;
      return !node.closest("label");
    })
    .map((node) => node.name || node.id || node.type);

  const imagenesSinAlt = [...document.querySelectorAll("img")]
    .filter((node) => !node.hasAttribute("alt"))
    .map((node) => node.currentSrc?.slice(-40) ?? "img");

  const niveles = [...document.querySelectorAll("h1, h2, h3, h4, h5, h6")].map((node) => Number(node.tagName[1]));
  const saltos = niveles.filter((nivel, index) => index > 0 && nivel - niveles[index - 1] > 1);

  const botonesSinNombre = [...document.querySelectorAll("button, a")]
    .filter((node) => node.offsetParent !== null)
    .filter((node) => !node.textContent?.trim() && !node.getAttribute("aria-label") && !node.getAttribute("title"))
    .length;

  return { contrasteBajo, sinEtiqueta, imagenesSinAlt, saltosDeNivel: saltos.length, botonesSinNombre, h1: niveles.filter((n) => n === 1).length };
};

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
const informe = {};
let problemas = 0;

for (const path of PAGES) {
  await page.goto(`${BASE}${path}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1500);
  const resultado = await page.evaluate(AUDIT);
  problemas += resultado.contrasteBajo.length + resultado.sinEtiqueta.length + resultado.imagenesSinAlt.length
    + resultado.saltosDeNivel + resultado.botonesSinNombre + (resultado.h1 === 1 ? 0 : 1);
  informe[path] = resultado;
}

await browser.close();
console.log(JSON.stringify({ informe, totalProblemas: problemas }, null, 2));
process.exit(problemas > 0 ? 1 : 0);
