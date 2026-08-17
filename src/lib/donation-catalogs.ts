export const DONATION_CATALOG_KEYS = [
  "donor_types",
  "economic_sectors",
  "donation_categories",
  "declared_donation_statuses",
  "coverage_departments",
  "departments",
  "units",
  "reporting_allies",
] as const;

export type DonationCatalogKey = (typeof DONATION_CATALOG_KEYS)[number];

export type CatalogOption = {
  value: string;
  label: string;
};

export type DonationCategoryOption = CatalogOption & {
  kind: "in_kind" | "money";
  parentCategory: string | null;
};

export type DonationFlowCatalogs = {
  versions: Record<DonationCatalogKey, number>;
  donorTypes: CatalogOption[];
  economicSectors: CatalogOption[];
  donationCategories: DonationCategoryOption[];
  declaredStatuses: CatalogOption[];
  coverageDepartments: string[];
  departments: string[];
  units: string[];
  reportingAllies: CatalogOption[];
};

export type DonationCatalogRow = {
  key: string;
  version: number;
  values_json: unknown;
};

function requireRow(
  rows: Map<string, DonationCatalogRow>,
  key: DonationCatalogKey,
): DonationCatalogRow & { values_json: unknown[] } {
  const row = rows.get(key);
  if (!row || !Number.isInteger(Number(row.version)) || Number(row.version) < 1) {
    throw new Error(`Catálogo requerido no disponible: ${key}`);
  }
  if (!Array.isArray(row.values_json)) {
    throw new Error(`El catálogo ${key} no contiene una lista válida`);
  }
  return row as DonationCatalogRow & { values_json: unknown[] };
}

function parseOptions(value: unknown[], key: DonationCatalogKey): CatalogOption[] {
  const options = value.map((entry) => {
    if (!entry || typeof entry !== "object") throw new Error(`Opción inválida en ${key}`);
    const candidate = entry as Record<string, unknown>;
    if (typeof candidate.value !== "string" || typeof candidate.label !== "string") {
      throw new Error(`Opción inválida en ${key}`);
    }
    return { value: candidate.value, label: candidate.label };
  });
  if (!options.length) throw new Error(`El catálogo ${key} está vacío`);
  return options;
}

function parseCategories(value: unknown[]): DonationCategoryOption[] {
  const options = value.map((entry) => {
    if (!entry || typeof entry !== "object") throw new Error("Categoría de aporte inválida");
    const candidate = entry as Record<string, unknown>;
    const parentCategory = candidate.parent_category;
    const kind = candidate.kind;
    if (
      typeof candidate.value !== "string"
      || typeof candidate.label !== "string"
      || (kind !== "in_kind" && kind !== "money")
      || (parentCategory !== null && typeof parentCategory !== "string")
    ) {
      throw new Error("Categoría de aporte inválida");
    }
    return {
      value: candidate.value,
      label: candidate.label,
      kind: kind as "in_kind" | "money",
      parentCategory,
    };
  });
  if (!options.some((option) => option.kind === "in_kind") || !options.some((option) => option.kind === "money")) {
    throw new Error("El catálogo de categorías no cubre especie y dinero");
  }
  return options;
}

function parseStrings(value: unknown[], key: DonationCatalogKey): string[] {
  if (!value.length || value.some((entry) => typeof entry !== "string" || !entry.trim())) {
    throw new Error(`Valor inválido en ${key}`);
  }
  return value as string[];
}

export function toDonationFlowCatalogs(input: DonationCatalogRow[]): DonationFlowCatalogs {
  const rows = new Map(input.map((row) => [row.key, row]));
  const donorTypes = requireRow(rows, "donor_types");
  const economicSectors = requireRow(rows, "economic_sectors");
  const donationCategories = requireRow(rows, "donation_categories");
  const declaredStatuses = requireRow(rows, "declared_donation_statuses");
  const coverageDepartments = requireRow(rows, "coverage_departments");
  const departments = requireRow(rows, "departments");
  const units = requireRow(rows, "units");
  const reportingAllies = requireRow(rows, "reporting_allies");

  const versions = Object.fromEntries(
    DONATION_CATALOG_KEYS.map((key) => [key, Number(requireRow(rows, key).version)]),
  ) as Record<DonationCatalogKey, number>;

  return {
    versions,
    donorTypes: parseOptions(donorTypes.values_json, "donor_types"),
    economicSectors: parseOptions(economicSectors.values_json, "economic_sectors"),
    donationCategories: parseCategories(donationCategories.values_json),
    declaredStatuses: parseOptions(declaredStatuses.values_json, "declared_donation_statuses"),
    coverageDepartments: parseStrings(coverageDepartments.values_json, "coverage_departments"),
    departments: parseStrings(departments.values_json, "departments"),
    units: parseStrings(units.values_json, "units"),
    reportingAllies: parseOptions(reportingAllies.values_json, "reporting_allies"),
  };
}
