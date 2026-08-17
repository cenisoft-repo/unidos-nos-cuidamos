// El evento que sirve esta instancia es configuración, no código: un despliegue desde cero
// crea su propio evento y lo declara con estas variables. Sin ellas se usa el evento local
// sintético de `supabase/seed.sql`, que es lo correcto para desarrollo y para las pruebas.
const LOCAL_EVENT_ID = "10000000-0000-0000-0000-000000000001";
const LOCAL_EVENT_SLUG = "simulacion-andina-2026";
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

export function resolveEventId(raw: string | undefined) {
  const value = raw?.trim();
  if (!value) return LOCAL_EVENT_ID;
  if (!UUID_PATTERN.test(value)) {
    throw new Error("NEXT_PUBLIC_EVENT_ID debe ser un UUID. La instancia no puede arrancar apuntando a un evento inválido.");
  }
  return value.toLowerCase();
}

export function resolveEventSlug(raw: string | undefined) {
  const value = raw?.trim();
  if (!value) return LOCAL_EVENT_SLUG;
  if (!SLUG_PATTERN.test(value)) {
    throw new Error("NEXT_PUBLIC_EVENT_SLUG debe usar minúsculas, dígitos y guiones simples.");
  }
  return value;
}

export const EVENT_ID = resolveEventId(process.env.NEXT_PUBLIC_EVENT_ID);
export const EVENT_SLUG = resolveEventSlug(process.env.NEXT_PUBLIC_EVENT_SLUG);

export const NEED_CATEGORIES = ["Agua", "Alimentos", "Higiene", "Refugio", "Salud", "Protección"] as const;
export const NORMALIZED_UNITS = ["unidad", "litro", "kilogramo", "kit", "caja"] as const;

export const STATUS_LABELS: Record<string, string> = {
  reported: "Reportado",
  in_verification: "En verificación",
  verified: "Verificado",
  published: "Publicado",
  partially_covered: "Cobertura parcial",
  covered: "Cubierto",
  closed: "Cerrado",
  expired: "Vencido",
  pending_verification: "Pendiente de verificación",
  observed: "Con observaciones",
  approved: "Aprobado",
  rejected: "Rechazado",
  duplicate: "Duplicado",
  quarantined: "En cuarentena",
  promised: "Prometida",
  scheduled: "Programada",
  received: "Recibida",
  stored: "Almacenada",
  allocated: "Asignada",
  dispatched: "Despachada",
  in_transit: "En tránsito",
  delivered: "Entregada",
  validated: "Validada",
  reserved: "Reservada",
  paid: "Pagada",
  requested: "Solicitada",
};

export function labelStatus(value: string) {
  return STATUS_LABELS[value] ?? value.replaceAll("_", " ");
}
