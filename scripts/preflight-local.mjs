import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const failures = [];

function requireLoopbackUrl(name) {
  const raw = process.env[name];
  if (!raw) {
    failures.push(`${name}: ausente`);
    return;
  }
  try {
    const parsed = new URL(raw);
    if (!new Set(["127.0.0.1", "localhost", "::1"]).has(parsed.hostname)) {
      failures.push(`${name}: el sandbox local no debe apuntar a un host remoto`);
    }
  } catch {
    failures.push(`${name}: URL inválida`);
  }
}

requireLoopbackUrl("NEXT_PUBLIC_SUPABASE_URL");
requireLoopbackUrl("NEXT_PUBLIC_APP_URL");

const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? "";
if (!publishableKey) failures.push("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: ausente");

const example = readFileSync(resolve(root, ".env.example"), "utf8");
if (example.includes("SERVICE_ROLE")) failures.push(".env.example: no debe sugerir una clave service_role");

const gitignore = readFileSync(resolve(root, ".gitignore"), "utf8");
for (const ignored of [".env*", ".vercel/", ".local-backups/"]) {
  if (!gitignore.includes(ignored)) failures.push(`.gitignore: falta ${ignored}`);
}

if (existsSync(resolve(root, ".vercel", "project.json"))) {
  failures.push("el sandbox local quedó enlazado a Vercel sin autorización");
}
if (existsSync(resolve(root, "supabase", ".temp", "project-ref"))) {
  failures.push("el sandbox local quedó enlazado a Supabase remoto sin autorización");
}

if (failures.length) {
  console.error(JSON.stringify({ status: "failed", checks: failures }, null, 2));
  process.exit(1);
}

console.log(JSON.stringify({
  status: "ok",
  checks: [
    "URLs limitadas a loopback",
    "clave publicable presente sin service_role en la plantilla",
    "secretos, enlaces remotos y respaldos ignorados por Git",
    "sin enlaces activos a proyectos remotos",
  ],
}, null, 2));
