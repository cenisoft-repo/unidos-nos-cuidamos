import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { AlertTriangle, ArrowRight, Boxes, ClipboardCheck, Download, LogOut, QrCode, Search, ShieldCheck, WalletCards } from "lucide-react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { assertSupabaseSuccess } from "@/lib/supabase/results";
import { currencyFormat, formatDate, numberFormat } from "@/lib/format";
import { labelStatus } from "@/lib/constants";
import { StatusPill } from "@/components/status-pill";
import { IntakeActions, NeedActions } from "@/components/operational-actions";
import { logout } from "@/app/ingresar/actions";

export const metadata: Metadata = { title: "Centro operativo" };
export const dynamic = "force-dynamic";

type Membership = { role: string; organization_id: string; organizations: { name: string } | null };
type Need = { id: string; category: string; description: string; public_location_text: string; status: string; expires_at: string; priority_score: number | null };
type Intake = { id: string; tracking_code: string; kind: string; status: string; submitted_at: string; public_attribution_kind: string; donation_intake_items: { count: number }[] };
type Lot = { id: string; lot_code: string; category: string; status: string; quantity_initial: number; unit: string; created_at: string };
type Transaction = { id: string; transaction_type: string; amount: number; status: string; public_reference: string; created_at: string };
type Expense = { id: string; amount: number; purpose: string; status: string; created_at: string };

const roleNames: Record<string, string> = { event_admin: "Administración de evento", verifier: "Verificación", partner_reporter: "Aliado reportante", warehouse_operator: "Centro de acopio", logistics_operator: "Logística", treasury_requester: "Solicitudes de tesorería", treasury_approver: "Aprobación financiera", auditor: "Auditoría" };

export default async function OperationsPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/ingresar?next=/operaciones");

  const [profileResult, membershipsResult, needsResult, intakesResult, lotsResult, txResult, expensesResult, auditsResult] = await Promise.all([
    supabase.from("profiles").select("full_name").eq("id", user.id).maybeSingle(),
    supabase.from("memberships").select("role,organization_id,organizations(name)").eq("user_id", user.id).eq("active", true),
    supabase.from("need_cases").select("id,category,description,public_location_text,status,expires_at,priority_score").in("status", ["reported","in_verification","verified"]).order("created_at", { ascending: true }).limit(8),
    supabase.from("donation_intakes").select("id,tracking_code,kind,status,submitted_at,public_attribution_kind,donation_intake_items(count)").in("status", ["reported","pending_verification","observed"]).order("submitted_at", { ascending: true }).limit(8),
    supabase.from("inventory_lots").select("id,lot_code,category,status,quantity_initial,unit,created_at").order("created_at", { ascending: false }).limit(6),
    supabase.from("financial_transactions").select("id,transaction_type,amount,status,public_reference,created_at").eq("status", "reconciled").order("created_at", { ascending: false }).limit(8),
    supabase.from("expense_requests").select("id,amount,purpose,status,created_at").order("created_at", { ascending: false }).limit(8),
    supabase.from("audit_events").select("id", { count: "exact", head: true }),
  ]);
  assertSupabaseSuccess("centro_operativo", [profileResult, membershipsResult, needsResult, intakesResult, lotsResult, txResult, expensesResult, auditsResult]);

  const memberships = (membershipsResult.data ?? []) as unknown as Membership[];
  const roles = new Set(memberships.map((item) => item.role));
  const needs = (needsResult.data ?? []) as Need[];
  const intakes = (intakesResult.data ?? []) as Intake[];
  const lots = (lotsResult.data ?? []) as Lot[];
  const transactions = (txResult.data ?? []) as Transaction[];
  const expenses = (expensesResult.data ?? []) as Expense[];
  const balance = transactions.reduce((sum, tx) => sum + (tx.transaction_type === "credit" ? Number(tx.amount) : -Number(tx.amount)), 0);
  const canVerify = roles.has("verifier") || roles.has("event_admin");

  return <div className="ops-shell">
    <div className="ops-header"><div><p className="eyebrow">Centro de mando · Simulación</p><h1>Buenos días, {profileResult.data?.full_name?.split(" ")[0] ?? "equipo"}.</h1><p>{memberships.map((item) => roleNames[item.role] ?? item.role).filter((value,index,array) => array.indexOf(value) === index).join(" · ")}</p></div><div className="ops-actions"><Link className="button button-outline button-small ops-export" href="/api/exports/operations.xlsx"><Download size={15} /> Exportar Excel</Link><div className="ops-user"><div className="ops-user-avatar">{(profileResult.data?.full_name ?? user.email ?? "RS").slice(0,2).toUpperCase()}</div><div><strong>{profileResult.data?.full_name}</strong><small>{user.email}</small></div></div><form action={logout}><button className="button button-outline button-small" aria-label="Cerrar sesión"><LogOut size={15} /></button></form></div></div>
    <div className="ops-alert"><AlertTriangle size={17} /><strong>Entorno controlado:</strong> todos los datos, actores, fondos y decisiones de esta vista son sintéticos.</div>
    <nav className="ops-subnav" aria-label="Módulos operativos"><Link href="/operaciones">Mando</Link>{(roles.has("warehouse_operator")||roles.has("logistics_operator")||roles.has("event_admin"))&&<Link href="/operaciones/bodega">Bodega y logística</Link>}{(roles.has("treasury_requester")||roles.has("treasury_approver")||roles.has("event_admin")||roles.has("auditor"))&&<Link href="/operaciones/tesoreria">Tesorería</Link>}</nav>
    <section className="ops-launcher" aria-labelledby="ops-launcher-title"><header><div><p className="eyebrow">Acciones rápidas</p><h2 id="ops-launcher-title">¿Qué necesitas hacer ahora?</h2></div><span>Solo aparecen recorridos permitidos por tu rol.</span></header><div className="ops-launcher-grid">
      {canVerify && <Link href="#cola-verificacion"><span><ClipboardCheck size={21} /></span><div><strong>Revisar casos</strong><small>{needs.length + intakes.length} pendientes en la cola</small></div><ArrowRight size={16} /></Link>}
      {(roles.has("warehouse_operator")||roles.has("logistics_operator")||roles.has("event_admin")) && <Link href="/operaciones/bodega"><span><QrCode size={21} /></span><div><strong>Recibir o mover bienes</strong><small>Buscar código, lote o despacho</small></div><ArrowRight size={16} /></Link>}
      {(roles.has("treasury_requester")||roles.has("treasury_approver")||roles.has("event_admin")||roles.has("auditor")) && <Link href="/operaciones/tesoreria"><span><WalletCards size={21} /></span><div><strong>Revisar tesorería</strong><small>Solicitudes y movimientos conciliados</small></div><ArrowRight size={16} /></Link>}
      <Link href="/seguimiento"><span><Search size={21} /></span><div><strong>Consultar un código</strong><small>Ver el recorrido público y seguro</small></div><ArrowRight size={16} /></Link>
    </div></section>
    <section className="ops-kpis" aria-label="Indicadores operativos"><div className="ops-kpi"><span>Necesidades en cola</span><strong>{needs.length}</strong><small>sin publicar automáticamente</small></div><div className="ops-kpi"><span>Intakes por revisar</span><strong>{intakes.length}</strong><small>aliados autenticados</small></div><div className="ops-kpi"><span>Lotes visibles</span><strong>{lots.length}</strong><small>según tu organización</small></div><div className="ops-kpi"><span>Saldo conciliado</span><strong>{currencyFormat.format(balance)}</strong><small>proveedor sandbox</small></div></section>
    <div className="ops-grid"><section className="ops-panel" id="cola-verificacion"><header className="ops-panel-header"><h2><ClipboardCheck size={18} style={{ display: "inline", marginRight: 7 }} /> Cola de verificación</h2><span>{needs.length + intakes.length} pendientes</span></header><div className="ops-list">
      {needs.map((need) => <article className="ops-row" key={need.id}><div><h3>{need.category} · {need.public_location_text}</h3><p>{need.description.slice(0,150)}</p>{canVerify && <NeedActions id={need.id} status={need.status} />}</div><div className="ops-row-meta"><StatusPill status={need.status} /></div></article>)}
      {intakes.map((intake) => <article className="ops-row" key={intake.id}><div><h3>{intake.kind === "in_kind" ? "Especie" : "Económico"} · {intake.tracking_code}</h3><p>{intake.donation_intake_items?.[0]?.count ?? 0} líneas · atribución {intake.public_attribution_kind} · {formatDate(intake.submitted_at)}</p>{canVerify && <IntakeActions id={intake.id} />}</div><div className="ops-row-meta"><StatusPill status={intake.status} /></div></article>)}
      {!needs.length && !intakes.length && <p className="ops-empty">La cola está al día. Los casos cerrados siguen disponibles en auditoría.</p>}
    </div></section>
    <section className="ops-panel"><header className="ops-panel-header"><h2><Boxes size={18} style={{ display: "inline", marginRight: 7 }} /> Inventario reciente</h2><span>{lots.length} lotes</span></header><div className="ops-list">{lots.map((lot) => <article className="ops-row" key={lot.id}><div><h3>{lot.category} · {lot.lot_code}</h3><p>{numberFormat.format(lot.quantity_initial)} {lot.unit} · recibido {formatDate(lot.created_at)}</p></div><StatusPill status={lot.status} /></article>)}{!lots.length && <p className="ops-empty">Aún no hay lotes. Aprobar una promesa no equivale a recibirla.</p>}</div></section></div>
    <div className="ops-bottom"><section className="mini-panel"><ShieldCheck size={20} /><h2>Auditoría append-only</h2><strong>{auditsResult.count ?? 0} eventos</strong><p>Las correcciones agregan historia; no reemplazan los eventos críticos.</p></section><section className="mini-panel"><WalletCards size={20} /><h2>Tesorería segregada</h2><strong>{expenses.length} solicitudes</strong><p>{expenses[0] ? `${labelStatus(expenses[0].status)} · ${currencyFormat.format(expenses[0].amount)}` : "Ningún gasto solicitado"}</p></section><section className="mini-panel"><Boxes size={20} /><h2>Conciliación</h2><strong>{transactions.length} movimientos</strong><p>Solo estados reconciliados alimentan el saldo de esta vista.</p></section></div>
  </div>;
}
