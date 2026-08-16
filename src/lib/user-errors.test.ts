import { describe, expect, it, vi } from "vitest";
import { GENERIC_ACTION_ERROR, toOperationalMessage } from "./user-errors";

vi.spyOn(console, "error").mockImplementation(() => {});

describe("mensajes operativos", () => {
  it("muestra la regla de negocio tal como fue redactada", () => {
    const message = toOperationalMessage({
      code: "22023",
      message: "No incluyas teléfonos, cuentas ni enlaces en campos públicos",
    });
    expect(message).toBe("No incluyas teléfonos, cuentas ni enlaces en campos públicos");
  });

  it("nunca devuelve el texto crudo de la base de datos", () => {
    const message = toOperationalMessage({
      code: "42501",
      message: 'new row violates row-level security policy for table "donation_intakes"',
    });
    expect(message).not.toContain("row-level");
    expect(message).not.toContain("donation_intakes");
    expect(message).toBe("Tu cuenta no tiene permiso para completar esta acción.");
  });

  it("no expone identificadores internos en un fallo desconocido", () => {
    const message = toOperationalMessage({ code: "PGRST116", message: "JSON object requested, multiple rows returned" });
    expect(message).toBe(GENERIC_ACTION_ERROR);
    expect(message).not.toMatch(/PGRST|JSON/);
  });

  it("traduce una existencia insuficiente sin código de regla", () => {
    expect(toOperationalMessage({ code: "XX000", message: "cantidad_disponible negativa" })).toBe(
      "No hay existencia suficiente para completar la operación.",
    );
  });

  it("acepta un error ausente sin romper la vista", () => {
    expect(toOperationalMessage(null)).toBe(GENERIC_ACTION_ERROR);
  });
});
