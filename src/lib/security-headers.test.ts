import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { contentSecurityPolicy } from "./security-headers";

function directive(policy: string, name: string) {
  return policy.split("; ").find((part) => part.startsWith(`${name} `)) ?? "";
}

const SUPABASE_URL = "http://127.0.0.1:55321";

describe("política de seguridad de contenido", () => {
  beforeAll(() => vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", SUPABASE_URL));
  afterAll(() => vi.unstubAllEnvs());

  const policy = () => contentSecurityPolicy("abc123");

  it("firma los scripts con el nonce y no admite código en línea", () => {
    const script = directive(policy(), "script-src");
    expect(script).toContain("'nonce-abc123'");
    expect(script).toContain("'strict-dynamic'");
    expect(script).not.toContain("'unsafe-inline'");
    expect(script).not.toContain("'unsafe-eval'");
  });

  it("bloquea incrustación, objetos y bases arbitrarias", () => {
    expect(policy()).toContain("frame-ancestors 'none'");
    expect(policy()).toContain("object-src 'none'");
    expect(policy()).toContain("base-uri 'self'");
    expect(policy()).toContain("form-action 'self'");
  });

  it("permite la conexión con la base y la cartografía configuradas", () => {
    const connect = directive(policy(), "connect-src");
    expect(connect).toContain(SUPABASE_URL);
    expect(connect).toContain("https://tiles.openfreemap.org");
    expect(connect).toContain("https://tile.openstreetmap.org");
  });

  it("habilita los trabajadores del mapa sin abrir el resto", () => {
    expect(policy()).toContain("worker-src 'self' blob:");
    expect(directive(policy(), "default-src")).toBe("default-src 'self'");
  });

  it("solo admite evaluación de código en desarrollo", () => {
    expect(contentSecurityPolicy("n", { development: true })).toContain("'unsafe-eval'");
    expect(contentSecurityPolicy("n", { development: true })).not.toContain("upgrade-insecure-requests");
    expect(policy()).toContain("upgrade-insecure-requests");
  });

  it("permite mostrar la evidencia firmada del almacenamiento de Supabase", () => {
    // Sin este origen la política bloquea la imagen en silencio y quien verifica un aporte
    // ve un hueco donde debería estar el soporte. Es un fallo que no da error visible.
    const politica = contentSecurityPolicy("nonce-de-prueba");
    const imgSrc = politica.split(";").map((parte) => parte.trim()).find((parte) => parte.startsWith("img-src"));
    expect(imgSrc).toBeDefined();
    expect(imgSrc).toContain(new URL(process.env.NEXT_PUBLIC_SUPABASE_URL as string).origin);
  });
});
