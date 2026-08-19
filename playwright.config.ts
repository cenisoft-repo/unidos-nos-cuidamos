import { defineConfig, devices } from "@playwright/test";

/*
 * La suite corre en su propio puerto y con su propio directorio de compilación,
 * y NO reutiliza un servidor que ya esté encendido.
 *
 * Antes el puerto era el 3000 —el mismo de `npm run dev`— y `reuseExistingServer`
 * estaba activo, así que `npm run verify` probaba silenciosamente el servidor de
 * desarrollo que el programador tuviera abierto, en el estado en que estuviera.
 * El 2026-08-17 eso hizo fallar la prueba del mapa contra un servidor con horas
 * de uso y el HMR caído: dos chunks respondían 403 y el mapa nunca montaba. Con
 * un servidor limpio la misma prueba pasa en 10 s. Una puerta que depende de lo
 * que haya encendido no es una puerta; es el mismo defecto que G-032.
 *
 * Con puerto propio, no reutilizar no genera choque: nadie más escucha en 3100.
 *
 * Se probó además aislar el directorio de compilación con `NEXT_DIST_DIR`, y se
 * descartó: Next reescribe `next-env.d.ts` y `tsconfig.json` apuntando al último
 * `distDir` usado, así que ensuciaba dos archivos versionados y dejaba
 * `typecheck` mirando una carpeta temporal. Dentro de `verify` no hace falta:
 * `build` termina antes de que arranque la suite.
 */
const testPort = process.env.PLAYWRIGHT_PORT ?? "3100";
const webServerCommand = process.env.PLAYWRIGHT_WEB_SERVER_COMMAND
  ?? `npm run dev -- --hostname 127.0.0.1 --port ${testPort}`;

export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: false,
  // Ambos proyectos usan la misma base sandbox y las mismas cuentas. Un solo
  // worker evita que el cierre de sesión global de un proyecto invalide al otro.
  workers: 1,
  reporter: "html",
  use: {
    baseURL: `http://127.0.0.1:${testPort}`,
    trace: "retain-on-failure",
  },
  webServer: {
    command: webServerCommand,
    url: `http://127.0.0.1:${testPort}`,
    // Hay que pedir la reutilización a propósito (`PLAYWRIGHT_REUSE_SERVER=true`),
    // útil al depurar una prueba suelta. Por omisión, servidor nuevo.
    reuseExistingServer: process.env.PLAYWRIGHT_REUSE_SERVER === "true",
    timeout: 120_000,
  },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    { name: "mobile", use: { ...devices["Pixel 7"] } },
  ],
});
