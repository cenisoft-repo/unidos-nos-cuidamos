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

  /*
   * Errores de Auth. El registro de aliado los produjo en producción y la vista mostraba
   * el mensaje genérico: la persona veía «no fue posible» sin saber que su contraseña era
   * corta. Un mensaje que no dice qué corregir es un error sin arreglar.
   */
  it("explica por qué se rechazó la contraseña en vez de rendirse", () => {
    const message = toOperationalMessage({
      code: "weak_password",
      message: "Password should be at least 12 characters. Password should contain at least one character of each: abcdefghijklmnopqrstuvwxyz, ABCDEFGHIJKLMNOPQRSTUVWXYZ, 0123456789",
    });
    expect(message).toMatch(/12 caracteres/);
    expect(message).toMatch(/símbolo/);
    // No se reenvía el texto del servicio: llega en inglés y con el alfabeto entero dentro.
    expect(message).not.toMatch(/abcdefghijklmnopqrstuvwxyz/);
  });

  it("dice que el correo ya tiene cuenta sin insinuar nada más", () => {
    expect(toOperationalMessage({ code: "user_already_exists", message: "User already registered" })).toBe(
      "Ese correo ya tiene una cuenta. Ingresa con tu contraseña o recupérala.",
    );
  });

  it("distingue un fallo de envío de correo de un fallo cualquiera", () => {
    const message = toOperationalMessage({ code: "unexpected_failure", message: "Error sending confirmation email" });
    expect(message).toMatch(/correo de confirmación/);
    expect(message).not.toBe(GENERIC_ACTION_ERROR);
  });

  it("conserva el mensaje de regla de negocio por encima de los patrones de Auth", () => {
    // `22023` es contrato: su texto ya viene redactado para la persona y manda.
    expect(toOperationalMessage({ code: "22023", message: "Escribe un correo de contacto válido" })).toBe(
      "Escribe un correo de contacto válido",
    );
  });

  it("acepta un error ausente sin romper la vista", () => {
    expect(toOperationalMessage(null)).toBe(GENERIC_ACTION_ERROR);
  });
});
