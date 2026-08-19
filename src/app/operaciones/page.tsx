import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { AlertTriangle, ArrowRight, Boxes, ClipboardCheck, Download, LogOut, MapPinned, QrCode, Search, ShieldCheck, WalletCards } from "lucide-react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { assertSupabaseSuccess } from "@/lib/supabase/results";
import { currencyFormat, formatDate, numberFormat } from "@/lib/format";
import { EVENT_ID, labelStatus } from "@/lib/constants";
import { servesNonProductionData } from "@/lib/environment";
import { toDonationFlowCatalogs, type DonationCatalogRow } from "@/lib/donation-catalogs";
import { StatusPill } from "@/components/status-pill";
import { IntakeActions, NeedActions } from "@/components/operational-actions";
import { logout } from "@/app/ingresar/actions";

export const metadata: Metadata = { title: "Centro operativo" };
export const dynamic = "force-dynamic";

type Membership = { role: string; organization_id: string; organizations: { name: string } | null };
type Need = { id: string; tracking_code: string; category: string; description: string; public_location_text: string; status: string; created_at: string; expires_at: string; priority_score: number | null; need_items: { quantity_required: number; unit: string }[] };
type IntakeItem = { category: string; description: string; quantity: number; unit: string };
type Intake = {
  id: string;
  tracking_code: string;
  kind: string;
  status: string;
  submitted_at: string;
  public_attribution_kind: string;
  declared_status: string;
  declared_amount: number | null;
  currency: string;
  reporting_ally_code: string | null;
  inventory_locations: { name: string } | { name: string }[] | null;
  donation_intake_items: IntakeItem[];
  donation_intake_evidence: { uploaded_at: string | null }[];
};
type Lot = { id: string; lot_code: string; category: string; status: string; quantity_initial: number; unit: string; created_at: string };
type Transaction = { id: string; transaction_type: string; amount: number; status: string; public_reference: string; created_at: string };
type Expense = { id: string; amount: number; purpose: string; status: string; created_at: string };

const roleNames: Record<string, string> = { event_admin: "Administración de evento", verifier: "Verificación", partner_reporter: "Aliado reportante", warehouse_operator: "Centro de acopio", logistics_operator: "Logística", treasury_requester: "Solicitudes de tesorería", treasury_approver: "Aprobación financiera", auditor: "Auditoría" };
const attributionNames: Record<string, string> = { anonymous: "Anónima", organization: "Organización autorizada", alias: "Alias autorizado", authorized_name: "Nombre autorizado" };

function intakeDeclaredSummary(intake: Intake) {
  if (intake.kind === "money") return `${currencyFormat.format(Number(intake.declared_amount ?? 0))} declarados fuera de la plataforma`;
  if (!intake.donation_intake_items.length) return "Sin artículos declarados";
  const first = intake.donation_intake_items[0];
  const firstSummary = `${numberFormat.format(Number(first.quantity))} ${first.unit} de ${first.description}`;
  return intake.donation_intake_items.length === 1 ? firstSummary : `${firstSummary} y ${intake.donation_intake_items.length - 1} artículo(s) más`;
}

function intakeCenterName(intake: Intake) {
  if (Array.isArray(intake.inventory_locations)) return intake.inventory_locations[0]?.name;
  return intake.inventory_locations?.name;
}

export default async function OperationsPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/ingresar?next=/operaciones");

  // Los roles se resuelven antes que los datos: definen qué se puede consultar y qué
  // indicadores tienen sentido para esta persona.
  const [profileResult, membershipsResult] = await Promise.all([
    supabase.from("profiles").select("full_name").eq("id", user.id).maybeSingle(),
    supabase.from("memberships").select("role,organization_id,organizations(name)").eq("user_id", user.id).eq("event_id", EVENT_ID).eq("active", true),
  ]);
  assertSupabaseSuccess("membresia_centro_operativo", [profileResult, membershipsResult]);
  const memberships = (membershipsResult.data ?? []) as unknown as Membership[];
  const roles = new Set(memberships.map((item) => item.role));
  const canVerify = roles.has("verifier") || roles.has("event_admin");
  const canSeeTreasury = ["treasury_requester", "treasury_approver", "event_admin", "auditor"].some((role) => roles.has(role));

  // Toda consulta se acota al evento que sirve la instancia. Sin ese filtro, una persona
  // con membresía en otro evento vería aquí su cola y sus cifras mezcladas con las de este.
  const [needsResult, intakesResult, lotsResult, txResult, expensesResult, auditsResult, catalogsResult, balanceResult] = await Promise.all([
    supabase.from("need_cases").select("id,tracking_code,category,description,public_location_text,status,created_at,expires_at,priority_score,need_items(quantity_required,unit)").eq("event_id", EVENT_ID).in("status", ["reported","in_verification","verified"]).order("created_at", { ascending: true }).limit(8),
    supabase.from("donation_intakes").select("id,tracking_code,kind,status,submitted_at,public_attribution_kind,declared_status,declared_amount,currency,reporting_ally_code,inventory_locations(name),donation_intake_items(category,description,quantity,unit),donation_intake_evidence(uploaded_at)").eq("event_id", EVENT_ID).in("status", ["reported","pending_verification","observed"]).order("submitted_at", { ascending: false }).limit(8),
    supabase.from("inventory_lots").select("id,lot_code,category,status,quantity_initial,unit,created_at").eq("event_id", EVENT_ID).order("created_at", { ascending: false }).limit(6),
    supabase.from("financial_transactions").select("id,transaction_type,amount,status,public_reference,created_at").eq("event_id", EVENT_ID).eq("status", "reconciled").order("created_at", { ascending: false }).limit(8),
    supabase.from("expense_requests").select("id,amount,purpose,status,created_at").eq("event_id", EVENT_ID).order("created_at", { ascending: false }).limit(8),
    supabase.from("audit_events").select("id", { count: "exact", head: true }).eq("event_id", EVENT_ID),
    supabase.rpc("donation_flow_catalogs"),
    // El saldo se calcula en la base sobre el libro completo, no sobre la lista recortada.
    canSeeTreasury ? supabase.rpc("treasury_balance", { p_event_id: EVENT_ID }) : Promise.resolve({ data: [], error: null }),
  ]);
  assertSupabaseSuccess("centro_operativo", [needsResult, intakesResult, lotsResult, txResult, expensesResult, auditsResult, catalogsResult, balanceResult]);

  const needs = (needsResult.data ?? []) as Need[];
  const intakes = (intakesResult.data ?? []) as unknown as Intake[];
  const catalogs = toDonationFlowCatalogs((catalogsResult.data ?? []) as DonationCatalogRow[]);
  const lots = (lotsResult.data ?? []) as Lot[];
  const transactions = (txResult.data ?? []) as Transaction[];
  const expenses = (expensesResult.data ?? []) as Expense[];
  const treasury = (balanceResult.data ?? [])[0] as { balance: number; movement_count: number } | undefined;

  return <div className="ops-shell">
    <div className="ops-header"><div><p className="eyebrow">Centro de mando</p><h1>Buenos días, {profileResult.data?.full_name?.split(" ")[0] ?? "equipo"}.</h1><p>{memberships.map((item) => roleNames[item.role] ?? item.role).filter((value,index,array) => array.indexOf(value) === index).join(" · ")}</p></div><div className="ops-actions"><Link className="button button-outline button-small ops-export" href="/api/exports/operations.xlsx"><Download size={15} /> Exportar Excel</Link><div className="ops-user"><div className="ops-user-avatar">{(profileResult.data?.full_name ?? user.email ?? "RS").slice(0,2).toUpperCase()}</div><div><strong>{profileResult.data?.full_name}</strong><small>{user.email}</small></div></div><form action={logout}><button className="button button-outline button-small" aria-label="Cerrar sesión"><LogOut size={15} /></button></form></div></div>
    {servesNonProductionData && <div className="ops-alert"><AlertTriangle size={17} /><strong>Instancia de práctica:</strong> los datos, fondos y decisiones de esta vista no son reales.</div>}
    <nav className="ops-subnav" aria-label="Módulos operativos"><Link href="/operaciones">Mando</Link>{roles.has("event_admin")&&<Link href="/operaciones/centros">Puntos de entrega</Link>}{(roles.has("warehouse_operator")||roles.has("logistics_operator")||roles.has("event_admin"))&&<Link href="/operaciones/bodega">Bodega y logística</Link>}{(roles.has("treasury_requester")||roles.has("treasury_approver")||roles.has("event_admin")||roles.has("auditor"))&&<Link href="/operaciones/tesoreria">Tesorería</Link>}{(roles.has("warehouse_operator")||roles.has("logistics_operator")||roles.has("event_admin")||roles.has("auditor"))&&<Link href="/operaciones/reportes">Reportes</Link>}</nav>
    <section className="ops-launcher" aria-labelledby="ops-launcher-title"><header><div><p className="eyebrow">Acciones rápidas</p><h2 id="ops-launcher-title">¿Qué necesitas hacer ahora?</h2></div><span>Solo aparecen recorridos permitidos por tu rol.</span></header><div className="ops-launcher-grid">
      {canVerify && <Link href="#cola-verificacion"><span><ClipboardCheck size={21} /></span><div><strong>Revisar casos</strong><small>{needs.length + intakes.length} pendientes en la cola</small></div><ArrowRight size={16} /></Link>}
      {roles.has("event_admin") && <Link href="/operaciones/centros"><span><MapPinned size={21} /></span><div><strong>Configurar puntos</strong><small>Ubicación, categorías y disponibilidad</small></div><ArrowRight size={16} /></Link>}
      {(roles.has("warehouse_operator")||roles.has("logistics_operator")||roles.has("event_admin")) && <Link href="/operaciones/bodega"><span><QrCode size={21} /></span><div><strong>Recibir o mover bienes</strong><small>Buscar código, lote o despacho</small></div><ArrowRight size={16} /></Link>}
      {(roles.has("treasury_requester")||roles.has("treasury_approver")||roles.has("event_admin")||roles.has("auditor")) && <Link href="/operaciones/tesoreria"><span><WalletCards size={21} /></span><div><strong>Revisar tesorería</strong><small>Solicitudes y movimientos conciliados</small></div><ArrowRight size={16} /></Link>}
      <Link href="/seguimiento"><span><Search size={21} /></span><div><strong>Consultar un código</strong><small>Ver el recorrido público y seguro</small></div><ArrowRight size={16} /></Link>
    </div></section>
    <section className="ops-kpis" aria-label="Indicadores operativos"><div className="ops-kpi"><span>Necesidades por revisar</span><strong>{needs.length}</strong><small>reportes ciudadanos sin publicar</small></div><div className="ops-kpi"><span>Aportes por revisar</span><strong>{intakes.length}</strong><small>reportados por aliados autenticados</small></div><div className="ops-kpi"><span>Lotes visibles</span><strong>{lots.length}</strong><small>según tu organización</small></div>{canSeeTreasury && <div className="ops-kpi"><span>Saldo conciliado</span><strong>{currencyFormat.format(Number(treasury?.balance ?? 0))}</strong><small>{treasury?.movement_count ?? 0} movimientos del libro completo</small></div>}</section>
    <div className="ops-grid"><section className="ops-panel" id="cola-verificacion"><header className="ops-panel-header"><div><h2><ClipboardCheck size={18} style={{ display: "inline", marginRight: 7 }} /> Solicitudes pendientes de decisión</h2><p>Lee qué se reportó, dónde aplica y cuál es el siguiente control. Aprobar no significa recibir ni entregar.</p></div><span>{needs.length + intakes.length} pendientes</span></header><div className="ops-list">
      {needs.map((need) => <article className="ops-row ops-request" key={need.id}><div><span className="ops-request-kind">Necesidad reportada por la ciudadanía</span><h3>{need.category} en {need.public_location_text}</h3><p className="ops-request-summary">{need.description.slice(0,180)}</p><dl className="ops-request-facts"><div><dt>Código</dt><dd>{need.tracking_code}</dd></div><div><dt>Solicitado</dt><dd>{need.need_items.length ? need.need_items.map((item) => `${numberFormat.format(Number(item.quantity_required))} ${item.unit}`).join(" · ") : "Cantidad no disponible"}</dd></div><div><dt>Reportado</dt><dd>{formatDate(need.created_at)}</dd></div></dl><p className="ops-request-next"><strong>Siguiente control:</strong> confirmar hechos, cantidad y ubicación antes de publicar.</p>{canVerify && <NeedActions id={need.id} status={need.status} />}</div><div className="ops-row-meta"><StatusPill status={need.status} /></div></article>)}
      {intakes.map((intake) => { const allyLabel = catalogs.reportingAllies.find((ally) => ally.value === intake.reporting_ally_code)?.label ?? "Sin aliado de referencia"; const uploadedPhotos = intake.donation_intake_evidence.filter((evidence) => evidence.uploaded_at).length; return <article className="ops-row ops-request" key={intake.id}><div><span className="ops-request-kind">{intake.kind === "in_kind" ? "Aporte en especie reportado" : "Aporte económico declarado"}</span><h3>{intakeDeclaredSummary(intake)}</h3><dl className="ops-request-facts"><div><dt>Código</dt><dd>{intake.tracking_code}</dd></div><div><dt>Situación declarada</dt><dd>{catalogs.declaredStatuses.find((status) => status.value === intake.declared_status)?.label ?? labelStatus(intake.declared_status)}</dd></div><div><dt>Centro previsto</dt><dd>{intakeCenterName(intake) ?? (intake.kind === "money" ? "No aplica" : "Sin centro")}</dd></div><div><dt>Aliado relacionado</dt><dd>{allyLabel}</dd></div><div><dt>Presentación pública</dt><dd>{attributionNames[intake.public_attribution_kind] ?? "No definida"}</dd></div><div><dt>Fotos privadas</dt><dd>{intake.donation_intake_evidence.length ? `${uploadedPhotos} cargada(s), pendientes de revisión` : "Sin fotos"}</dd></div><div><dt>Reportado</dt><dd>{formatDate(intake.submitted_at)}</dd></div></dl><p className="ops-request-next"><strong>Siguiente control:</strong> validar identidad, cantidades, centro y soportes antes de aprobar.</p>{canVerify && <IntakeActions id={intake.id} />}</div><div className="ops-row-meta"><StatusPill status={intake.status} /></div></article>; })}
      {!needs.length && !intakes.length && <p className="ops-empty">La cola está al día. Los casos cerrados siguen disponibles en auditoría.</p>}
    </div></section>
    <section className="ops-panel"><header className="ops-panel-header"><h2><Boxes size={18} style={{ display: "inline", marginRight: 7 }} /> Inventario reciente</h2><span>{lots.length} lotes</span></header><div className="ops-list">{lots.map((lot) => <article className="ops-row" key={lot.id}><div><h3>{lot.category} · {lot.lot_code}</h3><p>{numberFormat.format(lot.quantity_initial)} {lot.unit} · recibido {formatDate(lot.created_at)}</p></div><StatusPill status={lot.status} /></article>)}{!lots.length && <p className="ops-empty">Aún no hay lotes. Aprobar una promesa no equivale a recibirla.</p>}</div></section></div>
    <div className="ops-bottom"><section className="mini-panel"><ShieldCheck size={20} /><h2>Auditoría append-only</h2><strong>{auditsResult.count ?? 0} eventos</strong><p>Las correcciones agregan historia; no reemplazan los eventos críticos.</p></section><section className="mini-panel"><WalletCards size={20} /><h2>Tesorería segregada</h2><strong>{expenses.length} solicitudes</strong><p>{expenses[0] ? `${labelStatus(expenses[0].status)} · ${currencyFormat.format(expenses[0].amount)}` : "Ningún gasto solicitado"}</p></section><section className="mini-panel"><Boxes size={20} /><h2>Conciliación</h2><strong>{transactions.length} movimientos</strong><p>Solo estados reconciliados alimentan el saldo de esta vista.</p></section></div>
  </div>;
}
