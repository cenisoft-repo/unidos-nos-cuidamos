import Link from "next/link";
import { LockKeyhole } from "lucide-react";
import { servesNonProductionData } from "@/lib/environment";
import { Logo } from "./logo";

export function SiteFooter() {
  return (
    <footer className="site-footer">
      <div className="shell footer-grid">
        <div>
          <Logo />
          <p>Una infraestructura de coordinación para que cada aporte conserve contexto, custodia y evidencia.</p>
        </div>
        <div>
          <h2>Acciones</h2>
          <Link href="/reportar">Reportar una necesidad</Link>
          <Link href="/donar">Registrar un aporte</Link>
          <Link href="/seguimiento">Consultar un código</Link>
        </div>
        <div>
          <h2>Confianza</h2>
          <Link href="/transparencia">Metodología y cifras</Link>
          <span className="privacy-line"><LockKeyhole size={14} /> Datos sensibles protegidos</span>
        </div>
      </div>
      <div className="shell footer-bottom">
        <span>{servesNonProductionData ? "Instancia de práctica: la información no corresponde a operaciones reales." : "Unidos nos cuidamos"}</span>
        <span>Colombia · America/Bogota</span>
      </div>
    </footer>
  );
}
