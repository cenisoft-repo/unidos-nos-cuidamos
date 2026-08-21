import { describe, expect, it } from "vitest";
import { CANAL_PRACTICA, leerAviso, urlDeCheckout } from "./payments";
import { firmar, firmaValida } from "./payments-server";

const SECRETO = "secreto-de-practica-solo-para-el-sandbox-local";

describe("aviso de pago", () => {
  it("acepta un aviso confirmado completo", () => {
    const aviso = leerAviso({ referencia: "PAG-1", resultado: "confirmed", referencia_proveedor: "PROV-1", monto: 1000 });
    expect(aviso).toEqual({ referencia: "PAG-1", resultado: "confirmed", referenciaProveedor: "PROV-1", monto: 1000, nota: null });
  });

  it("rechaza una confirmación sin referencia del proveedor o sin monto", () => {
    expect(leerAviso({ referencia: "PAG-1", resultado: "confirmed", monto: 1000 })).toBeNull();
    expect(leerAviso({ referencia: "PAG-1", resultado: "confirmed", referencia_proveedor: "PROV-1" })).toBeNull();
  });

  it("rechaza resultados que no existen, para que el proveedor no invente estados", () => {
    expect(leerAviso({ referencia: "PAG-1", resultado: "reembolsado", referencia_proveedor: "PROV-1", monto: 10 })).toBeNull();
  });

  it("admite un rechazo sin importe: no hay nada que cuadrar", () => {
    expect(leerAviso({ referencia: "PAG-1", resultado: "failed" })?.resultado).toBe("failed");
  });

  it("no confía en tipos: un monto de texto no es un monto", () => {
    expect(leerAviso({ referencia: "PAG-1", resultado: "confirmed", referencia_proveedor: "PROV-1", monto: "1000" })).toBeNull();
  });
});

describe("firma del aviso", () => {
  it("acepta el cuerpo exacto que se firmó", () => {
    const cuerpo = JSON.stringify({ referencia: "PAG-1", monto: 1000 });
    expect(firmaValida(cuerpo, SECRETO, firmar(cuerpo, SECRETO))).toBe(true);
  });

  it("rechaza un cuerpo alterado aunque venga con una firma válida de otro cuerpo", () => {
    const original = JSON.stringify({ referencia: "PAG-1", monto: 1000 });
    const alterado = JSON.stringify({ referencia: "PAG-1", monto: 9999999 });
    expect(firmaValida(alterado, SECRETO, firmar(original, SECRETO))).toBe(false);
  });

  it("rechaza una firma hecha con otro secreto", () => {
    const cuerpo = JSON.stringify({ referencia: "PAG-1" });
    expect(firmaValida(cuerpo, SECRETO, firmar(cuerpo, "otro-secreto-igual-de-largo-0000"))).toBe(false);
  });

  it("rechaza la ausencia de firma", () => {
    expect(firmaValida("{}", SECRETO, null)).toBe(false);
  });
});

describe("destino de pago", () => {
  it("resuelve la pasarela del canal de práctica dentro del propio sandbox", () => {
    expect(urlDeCheckout(CANAL_PRACTICA, "PAG-ABC")).toBe("/pagos/practica/PAG-ABC");
  });

  it("no inventa una pasarela para un canal sin adaptador", () => {
    expect(urlDeCheckout("proveedor_real", "PAG-ABC")).toBeNull();
  });
});
