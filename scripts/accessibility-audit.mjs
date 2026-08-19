/**
 * Auditoría de accesibilidad comprobable: contraste, etiquetas, foco visible,
 * orden de encabezados y texto alternativo. No sustituye una revisión manual,
 * pero convierte en verificable lo que suele quedar en apreciación.
 *
 *   node scripts/accessibility-audit.mjs
 *
 * Recorre las seis rutas públicas y las cinco consolas autenticadas, cada una
 * con el rol que la usa. Las autenticadas solo se auditan contra loopback; con
 * `AUDIT_SKIP_AUTH=1` se recorren solo las públicas y el informe declara la
 * omisión en vez de callarla.
 *
 * LÍMITE CONOCIDO: el contraste se calcula contra el primer ancestro con color
 * de fondo opaco. El texto sobre una fotografía o sobre un degradado de
 * pseudo-elemento no se puede calcular así, porque esos fondos no son nodos del
 * DOM. Esos casos salen en `contrasteIndeterminado` —no en `contrasteBajo`— y
 * no cuentan como fallo: hay que medirlos a mano.
 *
 * Medición manual del 2026-08-17 sobre el pie de la portada, componiendo la
 * fotografía con el degradado de `figure.human-hero-photo::after` y muestreando
 * 24 puntos por elemento: 5,54 · 5,99 · 6,10 en el peor punto de cada uno,
 * todos por encima de 4,5. Contrastan. El cálculo por DOM decía 1,14–1,43.
 */
import { chromium } from "@playwright/test";
import { RUTAS_PUBLICAS, abrirSesion, cerrarSesion, planAutenticado } from "./lib/rutas-auditadas.mjs";

const BASE = process.env.METRICS_BASE_URL ?? "http://127.0.0.1:3000";
const PAGES = RUTAS_PUBLICAS;

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

  /*
   * Un fondo pintado que NO es un color de nodo —una fotografía, un degradado
   * de pseudo-elemento, un vídeo— hace que el cálculo anterior sea inválido, no
   * que el texto falle. Antes esos casos se contaban como fallo y `audit:a11y`
   * salía en rojo para siempre; un control que nunca puede estar verde no sirve
   * de puerta y se termina ignorando. Ahora se separan: lo que no se puede
   * calcular se declara «indeterminado» y se verifica a mano, en vez de
   * fingirse aprobado o reprobado.
   */
  const fondoNoCalculable = (node) => {
    let current = node;
    while (current && current !== document.documentElement) {
      for (const estilo of [getComputedStyle(current), getComputedStyle(current, "::before"), getComputedStyle(current, "::after")]) {
        if (estilo.backgroundImage && estilo.backgroundImage !== "none") return `${current.tagName.toLowerCase()}: ${estilo.backgroundImage.slice(0, 48)}`;
      }
      if (current.querySelector("img, video, canvas, svg")) return `${current.tagName.toLowerCase()}: contiene medio de fondo`;
      const color = parse(getComputedStyle(current).backgroundColor);
      if (color && color.a > 0.85) return null; // fondo opaco antes de llegar al medio: sí es calculable
      current = current.parentElement;
    }
    return null;
  };

  const contrasteBajo = [];
  const contrasteIndeterminado = [];
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
    if (valor >= minimo) continue;
    const motivo = fondoNoCalculable(node);
    const hallazgo = {
      texto: node.textContent.trim().slice(0, 40),
      ratio: Number(valor.toFixed(2)),
      minimo,
      size: style.fontSize,
    };
    if (motivo) contrasteIndeterminado.push({ ...hallazgo, motivo });
    else contrasteBajo.push(hallazgo);
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

  return { contrasteBajo, contrasteIndeterminado, sinEtiqueta, imagenesSinAlt, saltosDeNivel: saltos.length, botonesSinNombre, h1: niveles.filter((n) => n === 1).length };
};

const contar = (resultado) =>
  resultado.contrasteBajo.length + resultado.sinEtiqueta.length + resultado.imagenesSinAlt.length +
  resultado.saltosDeNivel + resultado.botonesSinNombre + (resultado.h1 === 1 ? 0 : 1);

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
const informe = {};
let problemas = 0;

for (const path of PAGES) {
  await page.goto(`${BASE}${path}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1500);
  const resultado = await page.evaluate(AUDIT);
  problemas += contar(resultado);
  informe[path] = resultado;
}

const plan = planAutenticado(BASE);
for (const { clave, ruta, correo, rol } of plan.rutas) {
  await cerrarSesion(page, BASE);
  await abrirSesion(page, BASE, correo, ruta);
  await page.waitForTimeout(1500);
  const resultado = await page.evaluate(AUDIT);
  problemas += contar(resultado);
  // Se anota el rol, no la cuenta: el informe se comparte y no necesita el correo.
  informe[clave] = { rol, ...resultado };
}
if (plan.rutas.length) await cerrarSesion(page, BASE);

await browser.close();
const indeterminados = Object.values(informe).reduce((suma, r) => suma + r.contrasteIndeterminado.length, 0);
console.log(JSON.stringify({
  informe,
  cobertura: {
    publicas: PAGES.length,
    autenticadas: plan.rutas.length,
    autenticadasOmitidas: plan.omitido,
  },
  // No suman a `totalProblemas`: no se puede afirmar que fallen. Tampoco se
  // ocultan: si este número crece, alguien tiene que volver a medirlos a mano.
  contrasteIndeterminado: indeterminados,
  totalProblemas: problemas,
}, null, 2));
process.exit(problemas > 0 ? 1 : 0);
