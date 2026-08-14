"use client";

import { useMemo, useState } from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Legend,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { numberFormat } from "@/lib/format";

export type DashboardNeed = {
  id: string;
  category: string;
  summary: string;
  locationLabel: string;
  status: string;
  statusLabel: string;
  neededQuantity: number;
  coveredQuantity: number;
  unit: string;
};

const STATUS_COLORS = ["var(--forest-2)", "#236fa1", "var(--sun)", "#9d6046", "var(--muted)"];

export function TransparencyDashboard({ needs }: { needs: DashboardNeed[] }) {
  const [category, setCategory] = useState("Todas");
  const categories = useMemo(() => ["Todas", ...Array.from(new Set(needs.map((need) => need.category)))], [needs]);
  const filtered = useMemo(() => category === "Todas" ? needs : needs.filter((need) => need.category === category), [category, needs]);
  const coverageData = useMemo(() => filtered.map((need) => ({
    ...need,
    label: `${need.category} · ${need.locationLabel.split("·")[0].trim()}`,
    coverage: need.neededQuantity > 0 ? Math.min(100, Math.round((need.coveredQuantity / need.neededQuantity) * 100)) : 0,
    remaining: Math.max(0, need.neededQuantity - need.coveredQuantity),
  })), [filtered]);
  const statusData = useMemo(() => Array.from(filtered.reduce((map, need) => map.set(need.statusLabel, (map.get(need.statusLabel) ?? 0) + 1), new Map<string, number>())).map(([name, value]) => ({ name, value })), [filtered]);

  return (
    <section className="analytics-dashboard" aria-labelledby="analytics-dashboard-title">
      <header className="analytics-head">
        <div><p className="eyebrow">Análisis visual</p><h2 id="analytics-dashboard-title">Dashboard de cobertura</h2><p>Compara porcentajes por necesidad sin sumar litros, kits o unidades incompatibles.</p></div>
        <div className="analytics-filters" aria-label="Filtrar dashboard por categoría">{categories.map((item) => <button type="button" aria-pressed={category === item} onClick={() => setCategory(item)} key={item}>{item}</button>)}</div>
      </header>

      {coverageData.length ? <div className="analytics-grid">
        <article className="chart-panel">
          <div className="chart-panel-head"><h3>Cobertura por necesidad</h3><span>Porcentaje cubierto · 0–100 %</span></div>
          <div className="chart-canvas" role="img" aria-label={`Gráfico de barras con la cobertura de ${coverageData.length} necesidades`}>
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={coverageData} layout="vertical" margin={{ top: 8, right: 30, bottom: 20, left: 12 }} accessibilityLayer>
                <CartesianGrid stroke="var(--line)" horizontal={false} />
                <XAxis type="number" domain={[0, 100]} unit="%" tick={{ fill: "var(--muted)", fontSize: 11 }} axisLine={{ stroke: "var(--line)" }} tickLine={false} label={{ value: "Cobertura (%)", position: "insideBottom", offset: -12, fill: "var(--muted)", fontSize: 11 }} />
                <YAxis type="category" dataKey="label" width={128} tick={{ fill: "var(--ink)", fontSize: 11 }} axisLine={false} tickLine={false} />
                <Tooltip cursor={{ fill: "var(--mint)", opacity: 0.45 }} formatter={(value) => [`${Number(value)} %`, "Cobertura"]} labelFormatter={(_, payload) => payload?.[0]?.payload?.summary ?? "Necesidad"} />
                <Bar dataKey="coverage" name="Cobertura" fill="var(--forest-2)" radius={[0, 5, 5, 0]} isAnimationActive={false} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </article>

        <article className="chart-panel">
          <div className="chart-panel-head"><h3>Distribución por estado</h3><span>Número de necesidades públicas</span></div>
          <div className="chart-canvas pie-canvas" role="img" aria-label={`Gráfico circular con ${statusData.length} estados públicos`}>
            <ResponsiveContainer width="100%" height="100%">
              <PieChart accessibilityLayer>
                <Pie data={statusData} dataKey="value" nameKey="name" cx="50%" cy="47%" innerRadius={58} outerRadius={92} paddingAngle={2} isAnimationActive={false}>
                  {statusData.map((entry, index) => <Cell fill={STATUS_COLORS[index % STATUS_COLORS.length]} key={entry.name} />)}
                </Pie>
                <Tooltip formatter={(value) => [numberFormat.format(Number(value)), "Necesidades"]} />
                <Legend verticalAlign="bottom" iconType="circle" wrapperStyle={{ fontSize: 11, color: "var(--muted)" }} />
              </PieChart>
            </ResponsiveContainer>
          </div>
        </article>
      </div> : <p className="analytics-empty">No hay necesidades públicas para esta categoría.</p>}

      <div className="analytics-table-wrap">
        <table className="analytics-table"><thead><tr><th>Necesidad</th><th>Estado</th><th>Faltante</th><th>Cobertura</th></tr></thead><tbody>{coverageData.map((need) => <tr key={need.id}><td><strong>{need.category}</strong><span>{need.summary} · {need.locationLabel}</span></td><td>{need.statusLabel}</td><td>{numberFormat.format(need.remaining)} {need.unit}</td><td><strong>{need.coverage} %</strong></td></tr>)}</tbody></table>
      </div>
    </section>
  );
}
