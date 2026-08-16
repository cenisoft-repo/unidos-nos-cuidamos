import Link from "next/link";
import { Menu, ShieldCheck } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { servesNonProductionData } from "@/lib/environment";
import { Logo } from "./logo";

export async function SiteHeader() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getUser();

  return (
    <header className="site-header">
      <div className="shell header-inner">
        <Logo />
        <nav className="desktop-nav" aria-label="Navegación principal">
          <Link href="/#necesidades">Necesidades</Link>
          <Link href="/#mapa-section">Mapa</Link>
          <Link href="/#centros">Centros</Link>
          <Link href="/transparencia">Transparencia</Link>
          <Link href="/seguimiento">Seguimiento</Link>
        </nav>
        <div className="header-actions">
          {servesNonProductionData && <span className="sandbox-flag" title="Esta instancia no contiene información operativa real."><span aria-hidden="true" /> Datos de práctica</span>}
          {data.user ? (
            <Link className="button button-dark button-small" href="/operaciones">
              <ShieldCheck size={16} /> Centro operativo
            </Link>
          ) : (
            <Link className="button button-dark button-small" href="/ingresar">Ingresar</Link>
          )}
          <details className="mobile-menu">
            <summary aria-label="Abrir menú"><Menu size={21} /></summary>
            <nav aria-label="Navegación móvil">
              <Link href="/#necesidades">Necesidades</Link>
              <Link href="/#mapa-section">Mapa de necesidades</Link>
              <Link href="/#centros">Centros de acopio</Link>
              <Link href="/donar">Quiero ayudar</Link>
              <Link href="/transparencia">Transparencia</Link>
              <Link href="/seguimiento">Seguimiento</Link>
              <Link href={data.user ? "/operaciones" : "/ingresar"}>{data.user ? "Centro operativo" : "Ingresar"}</Link>
            </nav>
          </details>
        </div>
      </div>
    </header>
  );
}
