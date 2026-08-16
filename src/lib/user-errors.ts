type ErrorLike = { message?: string | null; code?: string | null } | null | undefined;

/**
 * Las reglas de negocio se emiten desde PostgreSQL con `errcode 22023` y un
 * mensaje ya redactado para la persona usuaria. Ese texto sí se muestra; el de
 * cualquier otra falla se traduce, porque puede contener detalle interno.
 */
const BUSINESS_RULE_CODE = "22023";

const PATTERNS: Array<[RegExp, string]> = [
  [/permis|autoriz|membres|denied|policy|violates row-level/i, "Tu cuenta no tiene permiso para completar esta acción."],
  [/negativ|insuficien|disponible_menor|saldo/i, "No hay existencia suficiente para completar la operación."],
  [/duplicad|idempot|ya existe|unique|conflict/i, "Esta operación ya había sido registrada."],
  [/centro/i, "El centro seleccionado ya no está disponible. Elige otro."],
  [/vencid|expirad|caducad/i, "El registro ya no está vigente."],
  [/cuota|l[ií]mite|rate limit|too many/i, "Alcanzaste el límite de envíos. Intenta de nuevo en unos minutos."],
];

export const GENERIC_ACTION_ERROR = "No fue posible completar la acción. Intenta nuevamente.";

export function toOperationalMessage(error: ErrorLike, fallback: string = GENERIC_ACTION_ERROR) {
  const raw = error?.message ?? "";
  if (error?.code === BUSINESS_RULE_CODE && raw) return raw;
  if (raw) console.error("Acción no completada", { detail: raw });
  for (const [pattern, message] of PATTERNS) {
    if (pattern.test(raw)) return message;
  }
  return fallback;
}
