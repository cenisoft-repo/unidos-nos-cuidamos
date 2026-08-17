import { createClient } from "@/lib/supabase/server";
import { EVENT_ID } from "@/lib/constants";
import { addDataSheet, createExportWorkbook, workbookResponse } from "@/lib/excel-workbook";
import { observeRequest } from "@/lib/observability";
import { databaseUnavailableResponse, firstSupabaseError } from "@/lib/supabase/results";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

type NeedRow = {
  id: string;
  category: string;
  summary: string;
  location_label: string;
  status: string;
  needed_quantity: number;
  covered_quantity: number;
  unit: string;
  updated_at: string;
};

type DonationRow = {
  public_code: string;
  attribution: string;
  kind: string;
  category: string;
  verified_quantity: number | null;
  unit: string | null;
  reconciled_amount: number | null;
  currency: string | null;
  destination_label: string | null;
  operational_state: string;
  evidence_level: string;
  updated_at: string;
};

type CenterRow = {
  id: string;
  name: string;
  location_label: string;
  accepts: string[];
  restricted_items: string[];
  cold_chain_capable: boolean;
  latitude: number;
  longitude: number;
};

type MetricRow = {
  metric_key: string;
  value: number;
  unit: string;
  formula: string;
  source_cut_at: string;
  timezone: string;
  owner_role: string;
  dimensions: Record<string, unknown>;
};

export async function GET(request: Request) {
  const observation = observeRequest(request, "export_transparency_xlsx");
  const publicOrigin = new URL(request.url).origin;
  const supabase = await createClient();
  const results = await Promise.all([
    supabase.from("public_need_projections").select("id,category,summary,location_label,status,needed_quantity,covered_quantity,unit,updated_at").eq("event_id", EVENT_ID).eq("published", true).order("updated_at", { ascending: false }),
    supabase.from("public_donation_projections").select("public_code,attribution,kind,category,verified_quantity,unit,reconciled_amount,currency,destination_label,operational_state,evidence_level,updated_at").eq("event_id", EVENT_ID).eq("published", true).order("updated_at", { ascending: false }),
    supabase.rpc("public_collection_centers", { p_event_id: EVENT_ID }),
    supabase.from("public_metric_snapshots").select("metric_key,value,unit,formula,source_cut_at,timezone,owner_role,dimensions").eq("event_id", EVENT_ID).eq("reconciled", true).order("source_cut_at", { ascending: false }),
  ]);
  const queryError = firstSupabaseError(results);
  if (queryError) return observation.complete(databaseUnavailableResponse("exportacion_transparencia", queryError), "database_unavailable");
  const [{ data: needsData }, { data: donationsData }, { data: centersData }, { data: metricsData }] = results;

  const needs = (needsData ?? []) as NeedRow[];
  const donations = (donationsData ?? []) as DonationRow[];
  const centers = (centersData ?? []) as CenterRow[];
  const metrics = (metricsData ?? []) as MetricRow[];
  const needRows = needs.map((need, index) => ({
    ...need,
    needed_quantity: Number(need.needed_quantity),
    covered_quantity: Number(need.covered_quantity),
    coverage: {
      formula: `IFERROR(G${index + 5}/F${index + 5},0)`,
      result: Number(need.needed_quantity) > 0 ? Number(need.covered_quantity) / Number(need.needed_quantity) : 0,
    },
  }));
  const workbook = createExportWorkbook("Transparencia pública y reproducible");

  const needEnd = 4 + needs.length;
  const donationEnd = 4 + donations.length;
  const centerEnd = 4 + centers.length;
  const averageCoverage = needs.length ? needs.reduce((sum, row) => sum + (Number(row.needed_quantity) > 0 ? Number(row.covered_quantity) / Number(row.needed_quantity) : 0), 0) / needs.length : 0;
  const summary = [
    { metric: "Necesidades públicas", value: needs.length ? { formula: `COUNTA('Necesidades'!A5:A${needEnd})`, result: needs.length } : 0, unit: "casos", definition: "Proyecciones publicadas y vigentes" },
    { metric: "Cobertura promedio simple", value: needs.length ? { formula: `IFERROR(AVERAGE('Necesidades'!H5:H${needEnd}),0)`, result: averageCoverage } : 0, unit: "%", definition: "Promedio no ponderado del porcentaje de cada necesidad" },
    { metric: "Aportes públicos", value: donations.length ? { formula: `COUNTA('Aportes públicos'!A5:A${donationEnd})`, result: donations.length } : 0, unit: "aportes", definition: "Solo aportes verificados y publicados" },
    { metric: "Centros proyectados", value: centers.length ? { formula: `COUNTA('Centros'!A5:A${centerEnd})`, result: centers.length } : 0, unit: "centros", definition: "Ubicación aproximada; sin direcciones exactas" },
  ];
  addDataSheet(workbook, {
    name: "Resumen",
    title: "Ruta Solidaria · transparencia",
    description: `Exportación pública segura · corte ${new Date().toISOString()}`,
    columns: [
      { header: "Indicador", width: 28, value: (row: typeof summary[number]) => row.metric },
      { header: "Valor", width: 18, value: (row) => row.value, numFmt: "#,##0.0" },
      { header: "Unidad", width: 14, value: (row) => row.unit },
      { header: "Definición", width: 42, value: (row) => row.definition },
      { header: "Fuente", width: 38, value: () => `${publicOrigin}/transparencia` },
    ],
    rows: summary,
  });
  addDataSheet(workbook, {
    name: "Necesidades",
    title: "Necesidades públicas verificadas",
    description: "Cantidades comparables únicamente dentro de cada fila y unidad. La ubicación es aproximada.",
    columns: [
      { header: "ID público", width: 38, value: (row: typeof needRows[number]) => row.id },
      { header: "Categoría", width: 16, value: (row) => row.category },
      { header: "Descripción", width: 36, value: (row) => row.summary },
      { header: "Zona aproximada", width: 28, value: (row) => row.location_label },
      { header: "Estado", width: 20, value: (row) => row.status },
      { header: "Necesario", width: 14, value: (row) => row.needed_quantity, numFmt: "#,##0.000" },
      { header: "Cubierto", width: 14, value: (row) => row.covered_quantity, numFmt: "#,##0.000" },
      { header: "Cobertura", width: 14, value: (row) => row.coverage, numFmt: "0.0%" },
      { header: "Unidad", width: 14, value: (row) => row.unit },
      { header: "Actualización", width: 22, value: (row) => new Date(row.updated_at), numFmt: "yyyy-mm-dd hh:mm" },
    ],
    rows: needRows,
  });
  addDataSheet(workbook, {
    name: "Aportes públicos",
    title: "Aportes publicados y conciliados",
    description: "Excluye intakes pendientes, contactos, valores declarados no conciliados y cualquier evidencia privada.",
    columns: [
      { header: "Código", width: 30, value: (row: DonationRow) => row.public_code },
      { header: "Atribución", width: 24, value: (row) => row.attribution },
      { header: "Tipo", width: 16, value: (row) => row.kind },
      { header: "Categoría", width: 18, value: (row) => row.category },
      { header: "Cantidad verificada", width: 18, value: (row) => row.verified_quantity === null ? null : Number(row.verified_quantity), numFmt: "#,##0.000" },
      { header: "Unidad", width: 14, value: (row) => row.unit },
      { header: "Monto conciliado", width: 18, value: (row) => row.reconciled_amount === null ? null : Number(row.reconciled_amount), numFmt: "#,##0" },
      { header: "Moneda", width: 12, value: (row) => row.currency },
      { header: "Destino seguro", width: 26, value: (row) => row.destination_label },
      { header: "Estado operacional", width: 22, value: (row) => row.operational_state },
      { header: "Nivel de evidencia", width: 20, value: (row) => row.evidence_level },
      { header: "Actualización", width: 22, value: (row) => new Date(row.updated_at), numFmt: "yyyy-mm-dd hh:mm" },
    ],
    rows: donations,
  });
  addDataSheet(workbook, {
    name: "Centros",
    title: "Centros de acopio proyectados",
    description: "Coordenadas y zonas aproximadas. La exportación excluye direcciones exactas y datos de contacto.",
    columns: [
      { header: "ID público", width: 38, value: (row: CenterRow) => row.id },
      { header: "Centro", width: 28, value: (row) => row.name },
      { header: "Zona", width: 26, value: (row) => row.location_label },
      { header: "Acepta", width: 32, value: (row) => row.accepts.join(", ") },
      { header: "Restringe", width: 32, value: (row) => row.restricted_items.join(", ") },
      { header: "Cadena de frío", width: 16, value: (row) => row.cold_chain_capable ? "Sí" : "No" },
      { header: "Latitud aproximada", width: 20, value: (row) => Number(row.latitude), numFmt: "0.000000" },
      { header: "Longitud aproximada", width: 20, value: (row) => Number(row.longitude), numFmt: "0.000000" },
    ],
    rows: centers,
  });
  addDataSheet(workbook, {
    name: "Metodología",
    title: "Métricas reconciliadas y método",
    description: "Cada fila conserva fórmula, corte, zona horaria y rol responsable para auditoría.",
    columns: [
      { header: "Métrica", width: 28, value: (row: MetricRow) => row.metric_key },
      { header: "Valor", width: 16, value: (row) => Number(row.value), numFmt: "#,##0.000" },
      { header: "Unidad", width: 16, value: (row) => row.unit },
      { header: "Fórmula", width: 42, value: (row) => row.formula },
      { header: "Dimensiones", width: 30, value: (row) => JSON.stringify(row.dimensions ?? {}) },
      { header: "Corte", width: 22, value: (row) => new Date(row.source_cut_at), numFmt: "yyyy-mm-dd hh:mm" },
      { header: "Zona horaria", width: 22, value: (row) => row.timezone },
      { header: "Responsable", width: 22, value: (row) => row.owner_role },
    ],
    rows: metrics,
  });
  return observation.complete(await workbookResponse(workbook, "ruta-solidaria-transparencia.xlsx"), "export_ready");
}
