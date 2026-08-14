export const DEMO_EVENT_ID = "10000000-0000-0000-0000-000000000001";
export const DEMO_EVENT_SLUG = "simulacion-andina-2026";
export const DEMO_OPERATOR_ORG_ID = "20000000-0000-0000-0000-000000000001";
export const DEMO_PARTNER_ORG_ID = "20000000-0000-0000-0000-000000000002";

export const NEED_CATEGORIES = ["Agua", "Alimentos", "Higiene", "Refugio", "Salud", "Protección"] as const;
export const NORMALIZED_UNITS = ["unidad", "litro", "kilogramo", "kit", "caja"] as const;
export const DONOR_TYPES = [
  ["persona", "Persona"],
  ["empresa", "Empresa"],
  ["gremio", "Gremio o asociación"],
  ["fundacion", "Fundación u organización social"],
  ["otro", "Otro"],
] as const;
export const ECONOMIC_SECTORS = ["Agropecuario", "Comercio", "Construcción", "Educación", "Energía", "Financiero", "Industria", "Salud", "Tecnología", "Transporte y logística", "Turismo", "Otro"] as const;
export const COLOMBIA_DEPARTMENTS = ["Amazonas", "Antioquia", "Arauca", "Atlántico", "Bolívar", "Boyacá", "Caldas", "Caquetá", "Casanare", "Cauca", "Cesar", "Chocó", "Córdoba", "Cundinamarca", "Guainía", "Guaviare", "Huila", "La Guajira", "Magdalena", "Meta", "Nariño", "Norte de Santander", "Putumayo", "Quindío", "Risaralda", "San Andrés y Providencia", "Santander", "Sucre", "Tolima", "Valle del Cauca", "Vaupés", "Vichada", "Bogotá D.C."] as const;

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
