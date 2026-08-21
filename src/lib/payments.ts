/**
 * Contrato de la pasarela, del lado de la aplicación.
 *
 * Este módulo lo puede importar el navegador: no contiene ni toca secretos. Todo lo que
 * necesita el secreto del canal —firmar y verificar— vive en `payments-server.ts`.
 *
 * Lo que NO hay aquí, a propósito: ningún campo de tarjeta, cuenta, CVV ni token de medio
 * de pago. La plataforma abre una intención de cobro, manda a la persona al proveedor y
 * recibe de vuelta un resultado firmado. El dato de pago nunca la atraviesa.
 *
 * El secreto de cada canal vive en el entorno de despliegue, nunca en la base ni en el
 * navegador: la base solo guarda su huella y la compara al confirmar.
 */

export type ResultadoPago = "confirmed" | "failed";

export type AvisoDePago = {
  referencia: string;
  resultado: ResultadoPago;
  referenciaProveedor: string;
  monto: number;
  nota?: string | null;
};

export const CABECERA_FIRMA = "x-firma-pago";

/** Canal de práctica: no mueve dinero y su «pasarela» es una página del propio sandbox. */
export const CANAL_PRACTICA = "practica";

/** Valida la forma del aviso sin confiar en nada de lo que llega. */
export function leerAviso(cuerpo: unknown): AvisoDePago | null {
  if (!cuerpo || typeof cuerpo !== "object") return null;
  const dato = cuerpo as Record<string, unknown>;
  const referencia = typeof dato.referencia === "string" ? dato.referencia.trim() : "";
  const resultado = dato.resultado === "confirmed" || dato.resultado === "failed" ? dato.resultado : null;
  const referenciaProveedor = typeof dato.referencia_proveedor === "string" ? dato.referencia_proveedor.trim() : "";
  const monto = typeof dato.monto === "number" && Number.isFinite(dato.monto) ? dato.monto : null;
  const nota = typeof dato.nota === "string" ? dato.nota.slice(0, 240) : null;
  if (!referencia || !resultado) return null;
  if (resultado === "confirmed" && (!referenciaProveedor || monto === null)) return null;
  return { referencia, resultado, referenciaProveedor, monto: monto ?? 0, nota };
}

/**
 * A dónde se manda a la persona para pagar. Cada proveedor real devuelve esta URL desde su
 * API; el de práctica la resuelve dentro del propio sandbox para que el recorrido completo
 * —intención, pasarela, aviso firmado, conciliación— se pueda probar sin salir de casa.
 */
export function urlDeCheckout(proveedor: string, referencia: string) {
  if (proveedor === CANAL_PRACTICA) return `/pagos/practica/${encodeURIComponent(referencia)}`;
  return null;
}
