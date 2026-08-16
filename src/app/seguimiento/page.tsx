import type { Metadata } from "next";
import { EyeOff, Route, ShieldCheck } from "lucide-react";
import { TrackingForm } from "@/components/tracking-form";

export const metadata: Metadata = { title: "Seguimiento seguro" };

export default async function TrackingPage({ searchParams }: { searchParams: Promise<{ codigo?: string }> }) {
  const { codigo } = await searchParams;
  return <><section className="page-hero tracking-hero"><div className="shell" style={{ textAlign: "center" }}><p className="eyebrow">Consulta privada y mínima</p><h1 style={{ marginInline: "auto" }}>Entiende el recorrido<br />de tu ayuda.</h1><p className="lead" style={{ marginInline: "auto" }}>Un código, un estado claro y una historia protegida. Sin revelar contactos, evidencias privadas ni rutas operacionales.</p><div className="tracking-principles" aria-label="Cómo funciona el seguimiento"><div><Route size={19} /><strong>Recorrido claro</strong><span>Hitos fáciles de entender</span></div><div><ShieldCheck size={19} /><strong>Estado verificable</strong><span>Actualizado en cada etapa</span></div><div><EyeOff size={19} /><strong>Privacidad primero</strong><span>Sin seguir a personas</span></div></div></div></section><section className="form-section tracking-section"><div className="shell"><TrackingForm initialCode={codigo ?? ""} /></div></section></>;
}
