import { createClient } from "@/lib/supabase/server";
import { DEMO_EVENT_ID } from "@/lib/constants";
import { addDataSheet, createExportWorkbook, workbookResponse } from "@/lib/excel-workbook";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

type IntakeItem = {
  id: string;
  category: string;
  description: string;
  quantity: number;
  unit: string;
  condition: string | null;
  storage_requirement: string | null;
  declared_estimated_value_cop: number | null;
};

type IntakeRow = {
  id: string;
  tracking_code: string;
  organization_id: string;
  kind: string;
  status: string;
  public_attribution_kind: string;
  donor_type: string | null;
  economic_sector: string | null;
  specific_destination: boolean;
  destination_department: string | null;
  destination_municipality: string | null;
  estimated_beneficiaries: number | null;
  delivery_channel: string | null;
  declared_amount: number | null;
  currency: string;
  submitted_at: string;
  organizations: { name: string } | null;
  donation_intake_items: IntakeItem[];
};

type NeedRow = { tracking_code: string; category: string; description: string; public_location_text: string; status: string; priority_score: number | null; expires_at: string; created_at: string };
type LotRow = { lot_code: string; category: string; status: string; quantity_initial: number; unit: string; condition: string; created_at: string };
type FinanceRow = { public_reference: string; transaction_type: string; amount: number; currency: string; status: string; provider: string; reconciled_at: string | null; created_at: string };

export async function GET() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return Response.json({ error: "Debes iniciar sesión" }, { status: 401 });

  const { data: memberships } = await supabase.from("memberships").select("id").eq("user_id", user.id).eq("event_id", DEMO_EVENT_ID).eq("active", true).limit(1);
  if (!memberships?.length) return Response.json({ error: "No tienes una membresía activa para este evento" }, { status: 403 });

  const [{ data: needsData }, { data: intakesData }, { data: lotsData }, { data: financeData }] = await Promise.all([
    supabase.from("need_cases").select("tracking_code,category,description,public_location_text,status,priority_score,expires_at,created_at").eq("event_id", DEMO_EVENT_ID).order("created_at", { ascending: false }),
    supabase.from("donation_intakes").select("id,tracking_code,organization_id,kind,status,public_attribution_kind,donor_type,economic_sector,specific_destination,destination_department,destination_municipality,estimated_beneficiaries,delivery_channel,declared_amount,currency,submitted_at,organizations(name),donation_intake_items(id,category,description,quantity,unit,condition,storage_requirement,declared_estimated_value_cop)").eq("event_id", DEMO_EVENT_ID).order("submitted_at", { ascending: false }),
    supabase.from("inventory_lots").select("lot_code,category,status,quantity_initial,unit,condition,created_at").eq("event_id", DEMO_EVENT_ID).order("created_at", { ascending: false }),
    supabase.from("financial_transactions").select("public_reference,transaction_type,amount,currency,status,provider,reconciled_at,created_at").eq("event_id", DEMO_EVENT_ID).order("created_at", { ascending: false }),
  ]);

  const needs = (needsData ?? []) as NeedRow[];
  const intakes = (intakesData ?? []) as unknown as IntakeRow[];
  const lots = (lotsData ?? []) as LotRow[];
  const finances = (financeData ?? []) as FinanceRow[];
  const itemRows = intakes.flatMap((intake) => (intake.donation_intake_items ?? []).map((item) => ({
    ...item,
    tracking_code: intake.tracking_code,
    organization: intake.organizations?.name ?? intake.organization_id,
    submitted_at: intake.submitted_at,
  })));

  const workbook = createExportWorkbook("Operación autorizada y datos declarados");
  const summary = [
    { metric: "Necesidades visibles", value: needs.length, unit: "casos", definition: "Casos permitidos por RLS para la membresía activa" },
    { metric: "Aportes visibles", value: intakes.length, unit: "intakes", definition: "Reportes; no equivalen a recepción o impacto" },
    { metric: "Artículos declarados", value: itemRows.length, unit: "líneas", definition: "Líneas de especie antes de conciliación" },
    { metric: "Lotes visibles", value: lots.length, unit: "lotes", definition: "Inventario permitido por organización y evento" },
    { metric: "Movimientos financieros", value: finances.length, unit: "movimientos", definition: "Solo datos autorizados por RLS" },
  ];
  addDataSheet(workbook, {
    name: "Resumen",
    title: "Ruta Solidaria · exportación operativa",
    description: `Generada para una membresía autenticada · ${new Date().toISOString()} · sandbox de demostración`,
    columns: [
      { header: "Indicador", width: 28, value: (row: typeof summary[number]) => row.metric },
      { header: "Valor", width: 16, value: (row) => row.value, numFmt: "#,##0" },
      { header: "Unidad", width: 16, value: (row) => row.unit },
      { header: "Definición", width: 44, value: (row) => row.definition },
    ],
    rows: summary,
  });
  addDataSheet(workbook, {
    name: "Necesidades",
    title: "Necesidades operacionales autorizadas",
    description: "La exportación conserva el estado real; no convierte reportes en necesidades verificadas.",
    columns: [
      { header: "Código", width: 30, value: (row: NeedRow) => row.tracking_code },
      { header: "Categoría", width: 18, value: (row) => row.category },
      { header: "Descripción", width: 42, value: (row) => row.description },
      { header: "Zona pública", width: 28, value: (row) => row.public_location_text },
      { header: "Estado", width: 20, value: (row) => row.status },
      { header: "Puntaje interno", width: 18, value: (row) => row.priority_score === null ? null : Number(row.priority_score), numFmt: "0.0" },
      { header: "Vence", width: 22, value: (row) => new Date(row.expires_at), numFmt: "yyyy-mm-dd hh:mm" },
      { header: "Creación", width: 22, value: (row) => new Date(row.created_at), numFmt: "yyyy-mm-dd hh:mm" },
    ],
    rows: needs,
  });
  addDataSheet(workbook, {
    name: "Aportes",
    title: "Aportes reportados por aliados autenticados",
    description: "Perfil, destino y beneficiarios son datos declarados. Se excluyen nombre, correo, teléfono, observaciones y contacto interno.",
    columns: [
      { header: "Código", width: 30, value: (row: IntakeRow) => row.tracking_code },
      { header: "Organización derivada", width: 28, value: (row) => row.organizations?.name ?? row.organization_id },
      { header: "Tipo", width: 16, value: (row) => row.kind },
      { header: "Estado", width: 20, value: (row) => row.status },
      { header: "Atribución", width: 18, value: (row) => row.public_attribution_kind },
      { header: "Tipo de donante", width: 20, value: (row) => row.donor_type },
      { header: "Sector económico", width: 22, value: (row) => row.economic_sector },
      { header: "Destinación específica", width: 20, value: (row) => row.specific_destination ? "Sí" : "No" },
      { header: "Departamento", width: 22, value: (row) => row.destination_department },
      { header: "Municipio o zona", width: 24, value: (row) => row.destination_municipality },
      { header: "Beneficiarios estimados (no verificados)", width: 24, value: (row) => row.estimated_beneficiaries === null ? null : Number(row.estimated_beneficiaries), numFmt: "#,##0" },
      { header: "Canal previsto", width: 26, value: (row) => row.delivery_channel },
      { header: "Monto declarado (no conciliado)", width: 24, value: (row) => row.declared_amount === null ? null : Number(row.declared_amount), numFmt: "#,##0" },
      { header: "Moneda", width: 12, value: (row) => row.currency },
      { header: "Registro", width: 22, value: (row) => new Date(row.submitted_at), numFmt: "yyyy-mm-dd hh:mm" },
    ],
    rows: intakes,
  });
  addDataSheet(workbook, {
    name: "Artículos",
    title: "Detalle declarado de artículos",
    description: "Los valores estimados no constituyen ingreso financiero, inventario recibido ni cifra pública.",
    columns: [
      { header: "Código de aporte", width: 30, value: (row: typeof itemRows[number]) => row.tracking_code },
      { header: "Organización", width: 26, value: (row) => row.organization },
      { header: "Categoría", width: 18, value: (row) => row.category },
      { header: "Descripción", width: 38, value: (row) => row.description },
      { header: "Cantidad", width: 14, value: (row) => Number(row.quantity), numFmt: "#,##0.000" },
      { header: "Unidad", width: 14, value: (row) => row.unit },
      { header: "Condición", width: 16, value: (row) => row.condition },
      { header: "Almacenamiento", width: 18, value: (row) => row.storage_requirement },
      { header: "Valor estimado COP (no conciliado)", width: 24, value: (row) => row.declared_estimated_value_cop === null ? null : Number(row.declared_estimated_value_cop), numFmt: "#,##0" },
      { header: "Registro", width: 22, value: (row) => new Date(row.submitted_at), numFmt: "yyyy-mm-dd hh:mm" },
    ],
    rows: itemRows,
  });
  addDataSheet(workbook, {
    name: "Inventario",
    title: "Inventario visible por RLS",
    description: "Solo los lotes recibidos operacionalmente aparecen en esta hoja.",
    columns: [
      { header: "Lote", width: 28, value: (row: LotRow) => row.lot_code },
      { header: "Categoría", width: 18, value: (row) => row.category },
      { header: "Estado", width: 18, value: (row) => row.status },
      { header: "Cantidad inicial", width: 18, value: (row) => Number(row.quantity_initial), numFmt: "#,##0.000" },
      { header: "Unidad", width: 14, value: (row) => row.unit },
      { header: "Condición", width: 18, value: (row) => row.condition },
      { header: "Creación", width: 22, value: (row) => new Date(row.created_at), numFmt: "yyyy-mm-dd hh:mm" },
    ],
    rows: lots,
  });
  addDataSheet(workbook, {
    name: "Finanzas",
    title: "Movimientos financieros autorizados",
    description: "No incluye cuentas, referencias privadas ni credenciales del proveedor.",
    columns: [
      { header: "Referencia pública", width: 28, value: (row: FinanceRow) => row.public_reference },
      { header: "Tipo", width: 16, value: (row) => row.transaction_type },
      { header: "Monto", width: 18, value: (row) => Number(row.amount), numFmt: "#,##0" },
      { header: "Moneda", width: 12, value: (row) => row.currency },
      { header: "Estado", width: 18, value: (row) => row.status },
      { header: "Proveedor", width: 18, value: (row) => row.provider },
      { header: "Conciliación", width: 22, value: (row) => row.reconciled_at ? new Date(row.reconciled_at) : null, numFmt: "yyyy-mm-dd hh:mm" },
      { header: "Creación", width: 22, value: (row) => new Date(row.created_at), numFmt: "yyyy-mm-dd hh:mm" },
    ],
    rows: finances,
  });
  return workbookResponse(workbook, "ruta-solidaria-operacion.xlsx");
}
