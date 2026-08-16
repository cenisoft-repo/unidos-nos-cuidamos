import { afterEach, describe, expect, it, vi } from "vitest";

async function loadEnvironment(value?: string) {
  vi.resetModules();
  if (value === undefined) vi.stubEnv("NEXT_PUBLIC_APP_ENV", "");
  else vi.stubEnv("NEXT_PUBLIC_APP_ENV", value);
  return import("./environment");
}

describe("entorno declarado", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("oculta el aviso solo cuando se declara production", async () => {
    const { servesNonProductionData } = await loadEnvironment("production");
    expect(servesNonProductionData).toBe(false);
  });

  it("advierte datos no productivos en sandbox", async () => {
    const { servesNonProductionData } = await loadEnvironment("sandbox");
    expect(servesNonProductionData).toBe(true);
  });

  it("falla de forma segura ante un valor desconocido", async () => {
    const { servesNonProductionData } = await loadEnvironment("staging");
    expect(servesNonProductionData).toBe(true);
  });
});
