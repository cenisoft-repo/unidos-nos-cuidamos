import { describe, expect, it } from "vitest";
import { transportFromForm, transportProblem, TRANSPORT_MODES } from "./shipment-transport";

function form(values: Record<string, string>) {
  const data = new FormData();
  for (const [name, value] of Object.entries(values)) data.set(name, value);
  return data;
}

const complete = {
  transport_mode: "transportadora",
  transport_company: "Transportes Sintéticos SAS",
  transport_contact_name: " Conductor Sintético ",
  transport_contact_document: "CC-00000001",
  transport_contact_phone: "6040000000",
  transport_vehicle: "Camión sencillo",
  transport_plate: "ABC123",
  transport_responsible: "Marta Bodega",
};

describe("transporte del despacho", () => {
  it("recorta los espacios de cada campo declarado", () => {
    expect(transportFromForm(form(complete)).contact_name).toBe("Conductor Sintético");
  });

  it("acepta un transporte completo", () => {
    expect(transportProblem(transportFromForm(form(complete)))).toBe("");
  });

  it("exige declarar el tipo de transporte", () => {
    expect(transportProblem(transportFromForm(form({ ...complete, transport_mode: "" }))))
      .toMatch(/transportadora, particular o institucional/);
  });

  it("exige identificar a quien transporta", () => {
    expect(transportProblem(transportFromForm(form({ ...complete, transport_contact_document: "" }))))
      .toMatch(/nombre, identificación y teléfono/);
  });

  it("exige vehículo y placa", () => {
    expect(transportProblem(transportFromForm(form({ ...complete, transport_plate: "  " }))))
      .toMatch(/vehículo y la placa/);
  });

  it("exige un responsable de la carga", () => {
    expect(transportProblem(transportFromForm(form({ ...complete, transport_responsible: "" }))))
      .toMatch(/responde por la carga/);
  });

  it("solo exige la empresa cuando el transporte es una transportadora", () => {
    const asCompany = { ...complete, transport_company: "" };
    expect(transportProblem(transportFromForm(form(asCompany)))).toMatch(/empresa transportadora/);
    expect(transportProblem(transportFromForm(form({ ...asCompany, transport_mode: "particular" })))).toBe("");
  });

  it("declara exactamente los tres tipos que acepta la base de datos", () => {
    expect(TRANSPORT_MODES.map((mode) => mode.value)).toEqual(["transportadora", "particular", "institucional"]);
  });
});
