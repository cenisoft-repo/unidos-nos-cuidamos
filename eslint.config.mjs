import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

export default defineConfig([
  ...nextVitals,
  ...nextTs,
  /*
   * `.local-backups` guarda volcados y copias del entorno; `test-results` lo escribe
   * Playwright al fallar. Ninguno es código del proyecto, pero pueden traer archivos que
   * ESLint analiza —un respaldo de `supabase/.temp` incluye un bundle del runtime— y
   * entonces la puerta de calidad falla por algo que nadie escribió.
   */
  globalIgnores([
    ".next/**",
    ".vercel/**",
    "coverage/**",
    "playwright-report/**",
    "test-results/**",
    "supabase/.temp/**",
    ".local-backups/**",
  ]),
]);
