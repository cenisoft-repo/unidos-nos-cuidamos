import { createHmac, timingSafeEqual } from "node:crypto";

/**
 * La mitad de la pasarela que toca el secreto del canal. Solo servidor: importa
 * `node:crypto` y lee variables de entorno sin prefijo público, así que si alguna vez
 * acabara en un componente de cliente, la construcción falla en vez de filtrar nada.
 */

export function secretoDelCanal(proveedor: string) {
  const clave = `PAGOS_SECRETO_${proveedor.toUpperCase()}`;
  const secreto = process.env[clave];
  return secreto && secreto.length >= 24 ? secreto : null;
}

export function firmar(cuerpo: string, secreto: string) {
  return `sha256=${createHmac("sha256", secreto).update(cuerpo, "utf8").digest("hex")}`;
}

/**
 * Comparación en tiempo constante: una comparación normal filtra, por lo que tarda, cuántos
 * caracteres del principio acertó quien lo intenta.
 */
export function firmaValida(cuerpo: string, secreto: string, firmaRecibida: string | null) {
  if (!firmaRecibida) return false;
  const esperada = Buffer.from(firmar(cuerpo, secreto), "utf8");
  const recibida = Buffer.from(firmaRecibida, "utf8");
  if (esperada.length !== recibida.length) return false;
  return timingSafeEqual(esperada, recibida);
}

