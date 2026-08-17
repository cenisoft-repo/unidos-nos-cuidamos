import { describe, expect, it } from "vitest";
import { DONATION_CATALOG_KEYS, toDonationFlowCatalogs, type DonationCatalogRow } from "./donation-catalogs";

function rows(): DonationCatalogRow[] {
  const values: Record<string, unknown[]> = {
    donor_types: [{ value: "empresa", label: "Empresa" }],
    economic_sectors: [{ value: "comercio", label: "Comercio" }],
    donation_categories: [
      { value: "agua_potable", label: "Agua potable", kind: "in_kind", parent_category: "Agua" },
      { value: "apoyo_economico_recursos", label: "Apoyo económico / recursos", kind: "money", parent_category: null },
    ],
    declared_donation_statuses: [{ value: "comprometida", label: "Comprometida" }],
    coverage_departments: ["Valle del Cauca"],
    departments: ["Valle del Cauca", "Chocó"],
    units: ["unidad"],
    reporting_allies: [{ value: "propacifico", label: "PROPACIFICO" }],
  };
  return DONATION_CATALOG_KEYS.map((key) => ({ key, version: 1, values_json: values[key] }));
}

describe("toDonationFlowCatalogs", () => {
  it("convierte las versiones activas en opciones serializables para el formulario", () => {
    const catalogs = toDonationFlowCatalogs(rows());
    expect(catalogs.donorTypes).toEqual([{ value: "empresa", label: "Empresa" }]);
    expect(catalogs.donationCategories[0]).toMatchObject({ value: "agua_potable", parentCategory: "Agua" });
    expect(catalogs.versions.units).toBe(1);
    expect(catalogs.reportingAllies).toEqual([{ value: "propacifico", label: "PROPACIFICO" }]);
  });

  it("falla si falta un catálogo autoritativo", () => {
    expect(() => toDonationFlowCatalogs(rows().filter((row) => row.key !== "economic_sectors"))).toThrow(/economic_sectors/);
  });

  it("exige categorías distintas para especie y dinero", () => {
    const input = rows();
    const categories = input.find((row) => row.key === "donation_categories");
    if (categories) categories.values_json = [{ value: "agua_potable", label: "Agua potable", kind: "in_kind", parent_category: "Agua" }];
    expect(() => toDonationFlowCatalogs(input)).toThrow(/especie y dinero/);
  });
});
