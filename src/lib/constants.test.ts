import { describe, expect, it } from "vitest";
import { resolveEventId, resolveEventSlug } from "./constants";

describe("resolveEventId", () => {
  it("cae al evento local cuando la variable no está declarada", () => {
    expect(resolveEventId(undefined)).toBe("10000000-0000-0000-0000-000000000001");
    expect(resolveEventId("   ")).toBe("10000000-0000-0000-0000-000000000001");
  });

  it("acepta el evento declarado y lo normaliza", () => {
    expect(resolveEventId(" 3F2A9C41-0B7D-4E52-9A18-6C5D3E7B1042 "))
      .toBe("3f2a9c41-0b7d-4e52-9a18-6c5d3e7b1042");
  });

  it("no arranca con un identificador que no es UUID", () => {
    expect(() => resolveEventId("evento-de-produccion")).toThrow(/UUID/);
    expect(() => resolveEventId("10000000-0000-0000-0000-00000000000")).toThrow(/UUID/);
  });
});

describe("resolveEventSlug", () => {
  it("cae al slug local cuando la variable no está declarada", () => {
    expect(resolveEventSlug(undefined)).toBe("simulacion-andina-2026");
  });

  it("acepta un slug con minúsculas, dígitos y guiones simples", () => {
    expect(resolveEventSlug("respuesta-choco-2026")).toBe("respuesta-choco-2026");
  });

  it("rechaza mayúsculas, espacios y guiones dobles", () => {
    expect(() => resolveEventSlug("Respuesta Chocó")).toThrow(/minúsculas/);
    expect(() => resolveEventSlug("respuesta--choco")).toThrow(/minúsculas/);
  });
});
