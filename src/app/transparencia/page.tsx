import type { Metadata } from "next";
import Link from "next/link";
import { BadgeCheck, Building2, Clock3, Download, Scale, ShieldCheck } from "lucide-react";
import { TransparencyDashboard, type DashboardDonation, type DashboardNeed } from "@/components/transparency-dashboard";
import { createClient } from "@/lib/supabase/server";
import { assertSupabaseSuccess } from "@/lib/supabase/results";
import { EVENT_ID, labelStatus } from "@/lib/constants";
import { servesNonProductionData } from "@/lib/environment";
import { formatDate, numberFormat } from "@/lib/format";

export const metadata: Metadata = { title: "Transparencia" };
export const dynamic = "force-dynamic";

type Metric = {
  id: string;
  metric_key: string;
  value: number;
  unit: string;
  formula: string;
  source_cut_at: string;
  timezone: string;
  owner_role: string;
};

type PublicNeed = {
  id: string;
  category: string;
  summary: string;
  location_label: string;
  status: string;
  needed_quantity: number;
  covered_quantity: number;
  unit: string;
};

type PublicDonation = {
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
};

const metricNames: Record<string, string> = {
  needs_verified: "Necesidades verificadas",
  units_delivered: "Unidades cubiertas",
  median_verification_time: "Mediana de verificación",
  reconciled_balance: "Saldo conciliado",
};

export default async function TransparencyPage() {
  const supabase = await createClient();
  const [metricResult, needsResult, donationsResult] = await Promise.all([
    supabase
      .from("public_metric_snapshots")
      .select("id,metric_key,value,unit,formula,source_cut_at,timezone,owner_role")
      .eq("event_id", EVENT_ID)
      .eq("reconciled", true)
      .order("source_cut_at", { ascending: false }),
    supabase
      .from("public_need_projections")
      .select("id,category,summary,location_label,status,needed_quantity,covered_quantity,unit")
      .eq("event_id", EVENT_ID)
      .eq("published", true)
      .order("updated_at", { ascending: false }),
    supabase
      .from("public_donation_projections")
      .select("public_code,attribution,kind,category,verified_quantity,unit,reconciled_amount,currency,destination_label,operational_state")
      .eq("event_id", EVENT_ID)
      .eq("published", true)
      .order("updated_at", { ascending: false }),
  ]);
  assertSupabaseSuccess("transparencia", [metricResult, needsResult, donationsResult]);

  const allMetrics = (metricResult.data ?? []) as Metric[];
  const metrics = Array.from(
    allMetrics.reduce((latest, metric) => {
      if (!latest.has(metric.metric_key)) latest.set(metric.metric_key, metric);
      return latest;
    }, new Map<string, Metric>()).values(),
  );
  const dashboardNeeds: DashboardNeed[] = ((needsResult.data ?? []) as PublicNeed[]).map((need) => ({
    id: need.id,
    category: need.category,
    summary: need.summary,
    locationLabel: need.location_label,
    status: need.status,
    statusLabel: labelStatus(need.status),
    neededQuantity: Number(need.needed_quantity),
    coveredQuantity: Number(need.covered_quantity),
    unit: need.unit,
  }));
  const dashboardDonations: DashboardDonation[] = ((donationsResult.data ?? []) as PublicDonation[]).map((donation) => ({
    publicCode: donation.public_code,
    attribution: donation.attribution,
    kind: donation.kind,
    category: donation.category,
    verifiedQuantity: donation.verified_quantity === null ? null : Number(donation.verified_quantity),
    unit: donation.unit,
    reconciledAmount: donation.reconciled_amount === null ? null : Number(donation.reconciled_amount),
    currency: donation.currency,
    destinationLabel: donation.destination_label,
    operationalState: donation.operational_state,
  }));

  return (
    <>
      <section className="page-hero">
        <div className="shell page-hero-grid">
          <div>
            <p className="eyebrow">Rendición de cuentas reproducible</p>
            <h1>Cifras con fuente,<br />fórmula y corte.</h1>
            <p className="lead">No confundimos actividad con impacto. Cada métrica pública procede de un corte conciliado y conserva su método.</p>
            <div className="transparency-actions">
              <Link className="button button-primary" href="/api/exports/transparency.xlsx">
                <Download size={17} /> Descargar Excel seguro
              </Link>
              <a className="button button-outline" href="#dashboard">Ver dashboard</a>
            </div>
          </div>
          {servesNonProductionData && (
            <aside className="page-aside">
              <strong>Instancia de práctica</strong>
              Las cifras de esta pantalla no corresponden a una emergencia real.
            </aside>
          )}
        </div>
      </section>

      <section className="section section-white" aria-labelledby="metricas-title">
        <div className="shell">
          <h2 id="metricas-title" className="visually-hidden">Métricas conciliadas</h2>
          <div className="transparency-grid">
            {metrics.filter((metric) => metric.metric_key !== "reconciled_balance").slice(0, 3).map((metric, index) => (
              <article className="transparency-metric" key={metric.id}>
                {index === 0 ? <BadgeCheck size={23} /> : index === 1 ? <Scale size={23} /> : <Clock3 size={23} />}
                <strong>{numberFormat.format(metric.value)}</strong>
                <h3>{metricNames[metric.metric_key] ?? metric.metric_key}</h3>
                <p>{metric.unit} · corte {formatDate(metric.source_cut_at)}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="section analytics-section" id="dashboard">
        <div className="shell">
          <TransparencyDashboard needs={dashboardNeeds} donations={dashboardDonations} />
          <div className="analytics-export-note">
            <Download size={20} aria-hidden="true" />
            <div><strong>El mismo corte, listo para analizar.</strong><p>Incluye resumen, necesidades, aportes públicos, centros y metodología. Sin datos personales.</p></div>
            <Link className="button button-outline button-small" href="/api/exports/transparency.xlsx">Descargar .xlsx</Link>
          </div>
        </div>
      </section>

      <section className="section section-white">
        <div className="shell">
          <div className="section-heading">
            <p className="eyebrow">Metodología visible</p>
            <h2>Cómo se calcula.</h2>
            <p>La zona horaria, unidad y responsable acompañan cada número para que una auditoría independiente pueda reproducirlo.</p>
          </div>
          <div className="method-table-wrap">
            <table className="method-table">
              <thead><tr><th>Métrica</th><th>Valor</th><th>Fórmula</th><th>Corte / dueño</th></tr></thead>
              <tbody>{metrics.map((metric) => (
                <tr key={metric.id}>
                  <td><strong>{metricNames[metric.metric_key] ?? metric.metric_key}</strong></td>
                  <td>{numberFormat.format(metric.value)} {metric.unit}</td>
                  <td>{metric.formula}</td>
                  <td>{formatDate(metric.source_cut_at)}<br />{metric.timezone} · {metric.owner_role}</td>
                </tr>
              ))}</tbody>
            </table>
          </div>
          <p className="form-notice transparency-method-note">Las unidades pertenecen a categorías distintas y no representan personas únicas. Se comparan porcentajes; nunca se suman litros, kits y unidades como si fueran equivalentes.</p>
          <div className="brand-governance-note">
            <Building2 size={23} aria-hidden="true" />
            <div><strong>Aliados y marcas bajo autorización</strong><p>La organización reportante se deriva de su membresía verificada. Los logos institucionales solo se publican con autorización expresa.</p></div>
            <ShieldCheck size={23} aria-label="Protección institucional activa" />
          </div>
        </div>
      </section>
    </>
  );
}
