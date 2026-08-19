/**
 * Rutas que recorren las auditorías visuales y de accesibilidad, y la sesión
 * necesaria para abrir las autenticadas.
 *
 * Existe porque `audit:a11y` y `audit:visual` solo miraban seis rutas públicas:
 * las cinco consolas operativas —donde ocurre el trabajo real— no tenían
 * ninguna evidencia de contraste ni de maquetación, y por eso `DESIGN_QUALITY`
 * no podía sembrarlas por encima de nivel 2 por buena que fuera la
 * implementación. Es el hallazgo DQ-01.
 *
 * Cada consola se audita con el rol que la usa, no con un administrador que lo
 * ve todo: lo que importa es lo que ve quien trabaja ahí. `/operaciones` se
 * recorre dos veces, porque el aliado y la coordinación ven pantallas
 * distintas —la cola de aportes observados es del aliado— y auditar solo una
 * dejaría la otra sin cubrir.
 */

export const RUTAS_PUBLICAS = ["/", "/donar", "/reportar", "/seguimiento", "/transparencia", "/ingresar"];

/**
 * `clave` es el identificador en el informe; `ruta` es la URL real. Se separan
 * porque dos entradas comparten `/operaciones` con roles distintos.
 */
export const RUTAS_AUTENTICADAS = [
  { clave: "/operaciones#coordinacion", ruta: "/operaciones", correo: "admin@rutasolidaria.local", rol: "event_admin + verifier" },
  { clave: "/operaciones#aliado", ruta: "/operaciones", correo: "aliado@rutasolidaria.local", rol: "partner_reporter" },
  { clave: "/operaciones/bodega", ruta: "/operaciones/bodega", correo: "bodega@rutasolidaria.local", rol: "warehouse_operator" },
  { clave: "/operaciones/tesoreria", ruta: "/operaciones/tesoreria", correo: "aprueba@rutasolidaria.local", rol: "treasury_approver" },
  { clave: "/operaciones/centros", ruta: "/operaciones/centros", correo: "admin@rutasolidaria.local", rol: "event_admin" },
];

const CLAVE_SANDBOX = "RutaSolidaria2026!";

/**
 * La contraseña sembrada solo se usa contra loopback. Contra cualquier otro
 * host la auditoría se detiene en vez de intentar autenticarse: probar
 * credenciales conocidas contra un servidor que no es el sandbox local no es
 * una auditoría, y el proyecto ya prohíbe que el sandbox toque remoto sin
 * autorización (`preflight:local`).
 */
export function exigirSandboxLocal(base) {
  const host = new URL(base).hostname;
  if (host !== "127.0.0.1" && host !== "localhost" && host !== "[::1]") {
    throw new Error(
      `Las rutas autenticadas solo se auditan contra loopback; ${host} no lo es. ` +
        "Usa AUDIT_SKIP_AUTH=1 para recorrer solo las públicas.",
    );
  }
}

export async function abrirSesion(page, base, correo, destino) {
  await page.goto(`${base}/ingresar?next=${encodeURIComponent(destino)}`, { waitUntil: "domcontentloaded" });
  await page.getByLabel("Correo").fill(correo);
  await page.getByLabel("Contraseña").fill(process.env.AUDIT_SANDBOX_PASSWORD ?? CLAVE_SANDBOX);
  await page.getByRole("button", { name: "Ingresar", exact: true }).click();
  await page.waitForURL((url) => url.pathname === destino, { timeout: 20_000 });
}

export async function cerrarSesion(page, base) {
  await page.goto(`${base}/operaciones`, { waitUntil: "domcontentloaded" });
  const boton = page.getByRole("button", { name: "Cerrar sesión" });
  if (await boton.count()) await boton.first().click();
}

/**
 * Devuelve las rutas autenticadas que se van a recorrer, o una lista vacía con
 * el motivo. Nunca lanza por configuración: si no se pueden auditar, el informe
 * lo dice en vez de fingir cobertura.
 */
export function planAutenticado(base) {
  if (process.env.AUDIT_SKIP_AUTH === "1") {
    return { rutas: [], omitido: "AUDIT_SKIP_AUTH=1" };
  }
  try {
    exigirSandboxLocal(base);
  } catch (error) {
    return { rutas: [], omitido: error.message };
  }
  return { rutas: RUTAS_AUTENTICADAS, omitido: null };
}
