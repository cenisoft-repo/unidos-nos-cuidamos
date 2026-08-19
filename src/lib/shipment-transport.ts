// Fase 12: los datos mínimos de transporte que la operación exige antes de que una carga
// salga. La regla autoritativa vive en `assert_transport_ready` dentro de PostgreSQL; esto
// es la misma regla escrita para avisar en pantalla antes del viaje de ida y vuelta.

export const TRANSPORT_MODES = [
  { value: "transportadora", label: "Transportadora" },
  { value: "particular", label: "Particular" },
  { value: "institucional", label: "Vehículo institucional" },
] as const;

export type TransportMode = (typeof TRANSPORT_MODES)[number]["value"];

export type ShipmentTransport = {
  mode: string;
  company: string;
  contact_name: string;
  contact_document: string;
  contact_phone: string;
  vehicle: string;
  plate: string;
  responsible: string;
};

function field(data: FormData, name: string) {
  return String(data.get(name) ?? "").trim();
}

export function transportFromForm(data: FormData): ShipmentTransport {
  return {
    mode: field(data, "transport_mode"),
    company: field(data, "transport_company"),
    contact_name: field(data, "transport_contact_name"),
    contact_document: field(data, "transport_contact_document"),
    contact_phone: field(data, "transport_contact_phone"),
    vehicle: field(data, "transport_vehicle"),
    plate: field(data, "transport_plate"),
    responsible: field(data, "transport_responsible"),
  };
}

/** Devuelve el aviso que corresponde, o cadena vacía cuando el transporte está completo. */
export function transportProblem(transport: ShipmentTransport): string {
  if (!TRANSPORT_MODES.some((mode) => mode.value === transport.mode)) {
    return "Indica si el transporte es transportadora, particular o institucional.";
  }
  if (!transport.contact_name || !transport.contact_document || !transport.contact_phone) {
    return "Registra nombre, identificación y teléfono de quien transporta.";
  }
  if (!transport.vehicle || !transport.plate) {
    return "Registra el vehículo y la placa que llevan la carga.";
  }
  if (!transport.responsible) {
    return "Registra quién responde por la carga durante el traslado.";
  }
  if (transport.mode === "transportadora" && !transport.company) {
    return "Registra la empresa transportadora.";
  }
  return "";
}
