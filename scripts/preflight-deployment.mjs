import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const blockers = [];

for (const [name, value] of Object.entries({
  NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  NEXT_PUBLIC_APP_URL: process.env.NEXT_PUBLIC_APP_URL,
})) {
  if (!value || value.includes("obtener_")) blockers.push(`${name} no está configurada para el entorno objetivo`);
}

for (const name of ["NEXT_PUBLIC_SUPABASE_URL", "NEXT_PUBLIC_APP_URL"]) {
  const value = process.env[name];
  if (value) {
    try {
      const host = new URL(value).hostname;
      if (new Set(["127.0.0.1", "localhost", "::1"]).has(host)) blockers.push(`${name} todavía apunta a loopback`);
    } catch {
      blockers.push(`${name} no es una URL válida`);
    }
  }
}

if (!existsSync(resolve(root, ".vercel", "project.json"))) blockers.push("Vercel no está enlazado");
if (!existsSync(resolve(root, "supabase", ".temp", "project-ref"))) blockers.push("Supabase remoto no está enlazado");

const gaps = readFileSync(resolve(root, "docs", "GAP_LEDGER.md"), "utf8");
for (const id of ["G-002", "G-003", "G-004", "G-005", "G-006", "G-007", "G-008", "G-015", "G-017"]) {
  if (new RegExp(`\\| ${id} \\| P[0-3] \\|`).test(gaps)) blockers.push(`${id} permanece abierto`);
}

console.log(JSON.stringify({
  status: blockers.length ? "blocked" : "ready-for-authorized-review",
  note: "Este comando solo inspecciona; no enlaza, despliega ni publica reglas.",
  blockers,
}, null, 2));

if (blockers.length) process.exit(2);
