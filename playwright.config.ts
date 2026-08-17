import { defineConfig, devices } from "@playwright/test";

const testPort = process.env.PLAYWRIGHT_PORT ?? "3000";
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
    reuseExistingServer: process.env.PLAYWRIGHT_REUSE_SERVER !== "false",
    timeout: 120_000,
  },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    { name: "mobile", use: { ...devices["Pixel 7"] } },
  ],
});
