import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { AlertTriangle, ArrowRight, Boxes, ClipboardCheck, Download, LogOut, MapPinned, QrCode, Search, ShieldCheck, WalletCards } from "lucide-react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { assertSupabaseSuccess } from "@/lib/supabase/results";
import { currencyFormat, formatDate, numberFormat } from "@/lib/format";
import { EVENT_ID, labelStatus } from "@/lib/constants";
import { hasOperationalRole } from "@/lib/authorization";
import { servesNonProductionData } from "@/lib/environment";
import { toDonationFlowCatalogs, type DonationCatalogRow } from "@/lib/donation-catalogs";
import { StatusPill } from "@/components/status-pill";
import { IntakeActions, NeedActions } from "@/components/operational-actions";
import { IntakeAmendmentForm } from "@/components/intake-amendment-form";
import { IntakeEvidenceReview } from "@/components/intake-evidence-review";
import { logout } from "@/app/ingresar/actions";

export const metadata: Metadata = { title: "Centro operativo" };
export const dynamic = "force-dynamic";

type Membership = { role: string; organization_id: string; organizations: { name: string } | null };
type Need = { id: string; tracking_code: string; category: string; description: string; public_location_text: string; status: string; created_at: string; expires_at: string; priority_score: number | null; need_items: { quantity_required: number; unit: string }[] };
type IntakeItem = { category: string; description: string; quantity: number; unit: string };
/** Aporte devuelto al aliado con observaciones, con su última decisión. */
type ObservedIntake = {
  id: string;
  tracking_code: string;
  kind: string;
  version: number;
  declared_amount: number | null;
  submitted_at: string;
  donation_intake_items: { id: string; description: string; quantity: number; unit: string }[];
  intake_verification_decisions: { decision: string; note: string; decided_at: string }[];
};
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
// La existencia visible sale del Kardex, no del saldo con el que nació el lote.
type Lot = { lot_id: string; lot_code: string; category: string; status: string; quantity_available: number; quantity_physical: number; unit: string };
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
  const [profileResult, membershipsResult, superAdminResult] = await Promise.all([
    supabase.from("profiles").select("full_name").eq("id", user.id).maybeSingle(),
    supabase.from("memberships").select("role,organization_id,organizations(name)").eq("user_id", user.id).eq("event_id", EVENT_ID).eq("active", true),
    // La autoridad global no se deduce de la lista de roles del evento: es transversal y
    // la declara la base, que es quien la aplica.
    supabase.rpc("is_super_admin"),
  ]);
  assertSupabaseSuccess("membresia_centro_operativo", [profileResult, membershipsResult, superAdminResult]);
  const isSuperAdmin = superAdminResult.data === true;
  const memberships = (membershipsResult.data ?? []) as unknown as Membership[];
  const roles = new Set(memberships.map((item) => item.role));
  // La autoridad global es transversal al evento, así que se declara aparte de la lista
  // de membresías de este evento y desde ahí atraviesa las mismas comprobaciones.
  if (isSuperAdmin) roles.add("super_admin");
  const canVerify = hasOperationalRole(roles, ["verifier", "event_admin"]);
  const canSeeTreasury = hasOperationalRole(roles, ["treasury_requester", "treasury_approver", "event_admin", "auditor"]);
  // El aliado responde observaciones sobre sus propios aportes; no verifica.
  const isPartner = roles.has("partner_reporter");

  // Toda consulta se acota al evento que sirve la instancia. Sin ese filtro, una persona
  // con membresía en otro evento vería aquí su cola y sus cifras mezcladas con las de este.
  const [needsResult, intakesResult, lotsResult, txResult, expensesResult, auditsResult, catalogsResult, balanceResult] = await Promise.all([
    supabase.from("need_cases").select("id,tracking_code,category,description,public_location_text,status,created_at,expires_at,priority_score,need_items(quantity_required,unit)").eq("event_id", EVENT_ID).in("status", ["reported","in_verification","verified"]).order("created_at", { ascending: true }).limit(8),
    supabase.from("donation_intakes").select("id,tracking_code,kind,status,submitted_at,public_attribution_kind,declared_status,declared_amount,currency,reporting_ally_code,inventory_locations(name),donation_intake_items(category,description,quantity,unit),donation_intake_evidence(uploaded_at)").eq("event_id", EVENT_ID).in("status", ["reported","pending_verification","observed"]).order("submitted_at", { ascending: false }).limit(8),
    supabase.from("inventory_lot_positions").select("lot_id,lot_code,category,status,quantity_available,quantity_physical,unit").eq("event_id", EVENT_ID).order("lot_code").limit(6),
    supabase.from("financial_transactions").select("id,transaction_type,amount,status,public_reference,created_at").eq("event_id", EVENT_ID).eq("status", "reconciled").order("created_at", { ascending: false }).limit(8),
    supabase.from("expense_requests").select("id,amount,purpose,status,created_at").eq("event_id", EVENT_ID).order("created_at", { ascending: false }).limit(8),
    supabase.from("audit_events").select("id", { count: "exact", head: true }).eq("event_id", EVENT_ID),
    supabase.rpc("donation_flow_catalogs"),
    // El saldo se calcula en la base sobre el libro completo, no sobre la lista recortada.
    canSeeTreasury ? supabase.rpc("treasury_balance", { p_event_id: EVENT_ID }) : Promise.resolve({ data: [], error: null }),
  ]);
  assertSupabaseSuccess("centro_operativo", [needsResult, intakesResult, lotsResult, txResult, expensesResult, auditsResult, catalogsResult, balanceResult]);

  /*
   * Aportes observados de este aliado (G-028). Antes esta cola no existía: el
   * verificador dejaba una observación y el aliado no tenía dónde responderla.
   * RLS ya acota a las organizaciones donde la persona es miembro; el filtro por
   * evento y estado solo recorta lo que hay que resolver hoy.
   */
  const observedResult = isPartner
    ? await supabase
        .from("donation_intakes")
        .select(
          "id,tracking_code,kind,version,declared_amount,submitted_at,donation_intake_items(id,description,quantity,unit),intake_verification_decisions(decision,note,decided_at)",
        )
        .eq("event_id", EVENT_ID)
        .eq("status", "observed")
        .order("submitted_at", { ascending: true })
        .limit(10)
    : { data: [], error: null };
  assertSupabaseSuccess("aportes_observados", [observedResult]);
  const observedIntakes = (observedResult.data ?? []) as unknown as ObservedIntake[];

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
    <nav className="ops-subnav" aria-label="Módulos operativos"><Link href="/operaciones">Mando</Link>{hasOperationalRole(roles, ["event_admin"])&&<Link href="/operaciones/centros">Puntos de entrega</Link>}{hasOperationalRole(roles, ["warehouse_operator","logistics_operator","event_admin"])&&<Link href="/operaciones/bodega">Bodega y logística</Link>}{hasOperationalRole(roles, ["treasury_requester","treasury_approver","event_admin","auditor"])&&<Link href="/operaciones/tesoreria">Tesorería</Link>}{hasOperationalRole(roles, ["warehouse_operator","logistics_operator","event_admin","auditor"])&&<Link href="/operaciones/reportes">Reportes</Link>}{isSuperAdmin&&<Link href="/operaciones/parametrizacion">Parametrización</Link>}</nav>
    <section className="ops-launcher" aria-labelledby="ops-launcher-title"><header><div><p className="eyebrow">Acciones rápidas</p><h2 id="ops-launcher-title">¿Qué necesitas hacer ahora?</h2></div><span>Solo aparecen recorridos permitidos por tu rol.</span></header><div className="ops-launcher-grid">
      {canVerify && <Link href="#cola-verificacion"><span><ClipboardCheck size={21} /></span><div><strong>Revisar casos</strong><small>{needs.length + intakes.length} pendientes en la cola</small></div><ArrowRight size={16} /></Link>}
      {hasOperationalRole(roles, ["event_admin"]) && <Link href="/operaciones/centros"><span><MapPinned size={21} /></span><div><strong>Configurar puntos</strong><small>Ubicación, categorías y disponibilidad</small></div><ArrowRight size={16} /></Link>}
      {hasOperationalRole(roles, ["warehouse_operator","logistics_operator","event_admin"]) && <Link href="/operaciones/bodega"><span><QrCode size={21} /></span><div><strong>Recibir o mover bienes</strong><small>Buscar código, lote o despacho</small></div><ArrowRight size={16} /></Link>}
      {hasOperationalRole(roles, ["treasury_requester","treasury_approver","event_admin","auditor"]) && <Link href="/operaciones/tesoreria"><span><WalletCards size={21} /></span><div><strong>Revisar tesorería</strong><small>Solicitudes y movimientos conciliados</small></div><ArrowRight size={16} /></Link>}
      {isSuperAdmin && <Link href="/operaciones/parametrizacion"><span><ShieldCheck size={21} /></span><div><strong>Parametrizar la plataforma</strong><small>Usuarios, alcance, catálogos y auditoría</small></div><ArrowRight size={16} /></Link>}
      <Link href="/seguimiento"><span><Search size={21} /></span><div><strong>Consultar un código</strong><small>Ver el recorrido público y seguro</small></div><ArrowRight size={16} /></Link>
    </div></section>
    <section className="ops-kpis" aria-label="Indicadores operativos"><div className="ops-kpi"><span>Necesidades por revisar</span><strong>{needs.length}</strong><small>reportes ciudadanos sin publicar</small></div><div className="ops-kpi"><span>Aportes por revisar</span><strong>{intakes.length}</strong><small>reportados por aliados autenticados</small></div><div className="ops-kpi"><span>Lotes visibles</span><strong>{lots.length}</strong><small>según tu organización</small></div>{canSeeTreasury && <div className="ops-kpi"><span>Saldo conciliado</span><strong>{currencyFormat.format(Number(treasury?.balance ?? 0))}</strong><small>{treasury?.movement_count ?? 0} movimientos del libro completo</small></div>}</section>
    {/*
      G-028 · Los aportes devueltos con observaciones son lo primero que un
      aliado tiene que resolver: van antes que cualquier otra cola suya.
    */}
    {isPartner && observedIntakes.length > 0 && <section className="ops-panel" id="aportes-observados" aria-labelledby="observados-title"><header className="ops-panel-header"><div><h2 id="observados-title"><AlertTriangle size={18} style={{ display: "inline", marginRight: 7 }} /> Tus aportes con observaciones</h2><p>Verificación pidió una corrección. Al enviarla, el aporte vuelve a la cola y la versión anterior queda en el historial.</p></div><span>{observedIntakes.length} por responder</span></header><div className="ops-list">
      {observedIntakes.map((intake) => {
        // La última observación registrada es la que hay que responder.
        const observation = intake.intake_verification_decisions
          .filter((decision) => decision.decision === "observe")
          .sort((a, b) => b.decided_at.localeCompare(a.decided_at))[0];
        return <article className="ops-row ops-row-stack" key={intake.id}>
          <div><h3>{intake.tracking_code} · versión {intake.version}</h3><p>{intake.kind === "money" ? `${currencyFormat.format(Number(intake.declared_amount ?? 0))} declarados` : `${intake.donation_intake_items.length} línea(s)`} · registrado {formatDate(intake.submitted_at)}</p></div>
          <IntakeAmendmentForm
            intakeId={intake.id}
            version={intake.version}
            kind={intake.kind}
            declaredAmount={intake.declared_amount}
            items={intake.donation_intake_items}
            observation={observation?.note ?? null}
          />
        </article>;
      })}
    </div></section>}

    <div className="ops-grid"><section className="ops-panel" id="cola-verificacion"><header className="ops-panel-header"><div><h2><ClipboardCheck size={18} style={{ display: "inline", marginRight: 7 }} /> Solicitudes pendientes de decisión</h2><p>Lee qué se reportó, dónde aplica y cuál es el siguiente control. Aprobar no significa recibir ni entregar.</p></div><span>{needs.length + intakes.length} pendientes</span></header><div className="ops-list">
      {needs.map((need) => <article className="ops-row ops-request" key={need.id}><div><span className="ops-request-kind">Necesidad reportada por la ciudadanía</span><h3>{need.category} en {need.public_location_text}</h3><p className="ops-request-summary">{need.description.slice(0,180)}</p><dl className="ops-request-facts"><div><dt>Código</dt><dd>{need.tracking_code}</dd></div><div><dt>Solicitado</dt><dd>{need.need_items.length ? need.need_items.map((item) => `${numberFormat.format(Number(item.quantity_required))} ${item.unit}`).join(" · ") : "Cantidad no disponible"}</dd></div><div><dt>Reportado</dt><dd>{formatDate(need.created_at)}</dd></div></dl><p className="ops-request-next"><strong>Siguiente control:</strong> confirmar hechos, cantidad y ubicación antes de publicar.</p>{canVerify && <NeedActions id={need.id} status={need.status} />}</div><div className="ops-row-meta"><StatusPill status={need.status} /></div></article>)}
      {intakes.map((intake) => { const allyLabel = catalogs.reportingAllies.find((ally) => ally.value === intake.reporting_ally_code)?.label ?? "Sin aliado de referencia"; const uploadedPhotos = intake.donation_intake_evidence.filter((evidence) => evidence.uploaded_at).length; return <article className="ops-row ops-request" key={intake.id}><div><span className="ops-request-kind">{intake.kind === "in_kind" ? "Aporte en especie reportado" : "Aporte económico declarado"}</span><h3>{intakeDeclaredSummary(intake)}</h3><dl className="ops-request-facts"><div><dt>Código</dt><dd>{intake.tracking_code}</dd></div><div><dt>Situación declarada</dt><dd>{catalogs.declaredStatuses.find((status) => status.value === intake.declared_status)?.label ?? labelStatus(intake.declared_status)}</dd></div><div><dt>Centro previsto</dt><dd>{intakeCenterName(intake) ?? (intake.kind === "money" ? "No aplica" : "Sin centro")}</dd></div><div><dt>Aliado relacionado</dt><dd>{allyLabel}</dd></div><div><dt>Presentación pública</dt><dd>{attributionNames[intake.public_attribution_kind] ?? "No definida"}</dd></div><div><dt>Fotos privadas</dt><dd>{intake.donation_intake_evidence.length ? `${uploadedPhotos} cargada(s)` : "Sin fotos"}</dd></div><div><dt>Reportado</dt><dd>{formatDate(intake.submitted_at)}</dd></div></dl><p className="ops-request-next"><strong>Siguiente control:</strong> validar identidad, cantidades, centro y soportes antes de aprobar.</p>{canVerify && <IntakeEvidenceReview intakeId={intake.id} total={uploadedPhotos} />}{canVerify && <IntakeActions id={intake.id} />}</div><div className="ops-row-meta"><StatusPill status={intake.status} /></div></article>; })}
      {!needs.length && !intakes.length && <p className="ops-empty">La cola está al día. Los casos cerrados siguen disponibles en auditoría.</p>}
    </div></section>
    <section className="ops-panel"><header className="ops-panel-header"><h2><Boxes size={18} style={{ display: "inline", marginRight: 7 }} /> Inventario reciente</h2><span>{lots.length} lotes</span></header><div className="ops-list">{lots.map((lot) => <article className="ops-row" key={lot.lot_id}><div><h3>{lot.category} · {lot.lot_code}</h3><p>{numberFormat.format(lot.quantity_available)} de {numberFormat.format(lot.quantity_physical)} {lot.unit} disponibles</p></div><StatusPill status={lot.status} /></article>)}{!lots.length && <p className="ops-empty">Aún no hay lotes. Aprobar una promesa no equivale a recibirla.</p>}</div></section></div>
    <div className="ops-bottom"><section className="mini-panel"><ShieldCheck size={20} /><h2>Auditoría append-only</h2><strong>{auditsResult.count ?? 0} eventos</strong><p>Las correcciones agregan historia; no reemplazan los eventos críticos.</p></section><section className="mini-panel"><WalletCards size={20} /><h2>Tesorería segregada</h2><strong>{expenses.length} solicitudes</strong><p>{expenses[0] ? `${labelStatus(expenses[0].status)} · ${currencyFormat.format(expenses[0].amount)}` : "Ningún gasto solicitado"}</p></section><section className="mini-panel"><Boxes size={20} /><h2>Conciliación</h2><strong>{transactions.length} movimientos</strong><p>Solo estados reconciliados alimentan el saldo de esta vista.</p></section></div>
  </div>;
}
