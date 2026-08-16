import type { Metadata } from "next";
import { Clock3, EyeOff, MapPinned, ShieldAlert } from "lucide-react";
import { servesNonProductionData } from "@/lib/environment";
import { ReportNeedForm } from "@/components/report-need-form";

export const metadata: Metadata = { title: "Reportar una necesidad" };

export default function ReportPage() {
  return (
    <>
      <section className="page-hero"><div className="shell page-hero-grid"><div><p className="eyebrow">Reporte ciudadano seguro</p><h1>Primero los hechos.<br />Luego la prioridad.</h1><p className="lead">Tu reporte entra privado y pendiente de verificación. No se clasifica automáticamente como rescate, urgente ni verificado.</p></div>{servesNonProductionData && <aside className="page-aside"><strong>Instancia de práctica</strong>No ingreses personas, direcciones ni contactos reales.</aside>}</div></section>
      <section className="form-section"><div className="shell form-shell"><ReportNeedForm /><aside className="privacy-panel"><h2>Qué protegemos</h2><ul><li><EyeOff size={18} /><span>Contacto y dirección exacta nunca se publican.</span></li><li><MapPinned size={18} /><span>El mapa usa una zona amplia según el riesgo.</span></li><li><Clock3 size={18} /><span>Los reportes vencen si no se renuevan.</span></li><li><ShieldAlert size={18} /><span>Rescate, salud y materiales peligrosos se escalan a personal competente.</span></li></ul></aside></div></section>
    </>
  );
}
