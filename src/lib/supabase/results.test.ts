import { describe, expect, it } from "vitest";
import { assertSupabaseSuccess, databaseUnavailableResponse, firstSupabaseError } from "./results";

describe("resultados Supabase", () => {
  it("acepta un conjunto de consultas exitosas", () => {
    const results = [{ error: null }, { error: null }];
    expect(firstSupabaseError(results)).toBeNull();
    expect(() => assertSupabaseSuccess("dashboard", results)).not.toThrow();
  });

  it("detiene una vista para no presentar datos parciales como completos", () => {
    const results = [{ error: null }, { error: { code: "PGRST001", message: "fallo sintético" } }];
    expect(() => assertSupabaseSuccess("dashboard", results)).toThrow("[supabase:dashboard] PGRST001");
  });

  it("devuelve 503 sin filtrar el detalle interno", async () => {
    const response = databaseUnavailableResponse("excel", { code: "XX000", message: "detalle interno" });
    expect(response.status).toBe(503);
    expect(response.headers.get("retry-after")).toBe("30");
    expect(await response.text()).not.toContain("detalle interno");
  });
});
