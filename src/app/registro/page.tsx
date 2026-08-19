import type { Metadata } from "next";
import { BadgeCheck, MailCheck, ShieldCheck, UserPlus } from "lucide-react";
import { servesNonProductionData } from "@/lib/environment";
import { AllyRegistrationForm } from "@/components/ally-registration-form";

export const metadata: Metadata = { title: "Registro de aliado" };

export default function AllyRegistrationPage() {
  return (
    <>
      <section className="page-hero"><div className="shell page-hero-grid">
        <div>
          <p className="eyebrow">Una sola puerta de entrada</p>
          <h1>Registra tu organización<br />y aporta con trazabilidad.</h1>
          <p className="lead">Empresa, ONG, fundación, entidad o persona: el mismo registro, el mismo rol ALIADO y la misma cadena de seguimiento desde la necesidad hasta la entrega.</p>
        </div>
        {servesNonProductionData && <aside className="page-aside"><strong>Instancia de práctica</strong>No ingreses información real, tarjetas, claves ni cuentas bancarias.</aside>}
      </div></section>
      <section className="form-section"><div className="shell form-shell">
        <AllyRegistrationForm />
        <aside className="privacy-panel">
          <h2>Cómo se activa la cuenta</h2>
          <ul>
            <li><UserPlus size={18} /><span>Registras el aliado y reservamos su identificador de plataforma.</span></li>
            <li><MailCheck size={18} /><span>Creas tu cuenta con el correo y la contraseña que elijas.</span></li>
            <li><BadgeCheck size={18} /><span>Al activarla se crea tu organización con el rol ALIADO.</span></li>
            <li><ShieldCheck size={18} /><span>Hasta activarla, la cuenta no puede registrar aportes.</span></li>
          </ul>
        </aside>
      </div></section>
    </>
  );
}
