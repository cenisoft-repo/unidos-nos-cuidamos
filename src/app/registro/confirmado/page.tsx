import type { Metadata } from "next";
import { AllyActivationPanel } from "@/components/ally-activation-panel";

export const metadata: Metadata = { title: "Activar cuenta de aliado" };

export default function AllyActivationPage() {
  return (
    <section className="form-section"><div className="shell form-shell">
      <AllyActivationPanel />
      <aside className="privacy-panel">
        <h2>Qué acabas de crear</h2>
        <ul>
          <li><span>Tu organización queda creada con tu razón social.</span></li>
          <li><span>Tu usuario recibe el rol ALIADO en el evento activo.</span></li>
          <li><span>Cada aporte que registres queda ligado a ese aliado.</span></li>
          {/* G-055: el título decía «habilitar» y era justo lo que no ocurría aquí. */}
          <li><span>Verificación decide si la organización queda habilitada para operar.</span></li>
        </ul>
      </aside>
    </div></section>
  );
}
