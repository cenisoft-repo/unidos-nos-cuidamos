import { describe, expect, it } from "vitest";
import { cn, currencyFormat, formatDate, numberFormat } from "./format";
import { labelStatus } from "./constants";

describe("presentación segura y localizada", () => {
  it("presenta estados operacionales en español", () => {
    expect(labelStatus("pending_verification")).toBe("Pendiente de verificación");
    expect(labelStatus("unknown_state")).toBe("unknown state");
  });

  it("mantiene formato colombiano para cantidades y dinero", () => {
    expect(numberFormat.format(1234.5)).toMatch(/1[.\s]234,5/);
    expect(currencyFormat.format(1000000)).toContain("1.000.000");
  });

  it("forma clases sin valores vacíos", () => {
    expect(cn("base", false, undefined, "active")).toBe("base active");
  });

  it("no falla con una fecha ausente", () => {
    expect(formatDate(null)).toBe("Sin fecha");
  });

  it("normaliza espacios para que servidor y navegador hidraten el mismo texto", () => {
    const formatted = formatDate("2026-08-16T20:43:00.000Z");
    expect(formatted).not.toContain("\u00a0");
    expect(formatted).toContain("16");
  });
});
