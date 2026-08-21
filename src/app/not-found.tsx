import type { Metadata } from "next";
import Link from "next/link";
import { Compass, LifeBuoy, Search } from "lucide-react";

export const metadata: Metadata = { title: "Página no encontrada" };

/*
 * G-067: hasta aquí, una ruta inexistente devolvía la página 404 que Next trae de fábrica:
 * «404: This page could not be found.», en inglés, dentro de un sitio que se declara
 * `lang="es"` y que en una emergencia lo usa gente que no tiene por qué leer inglés.
 *
 * Y una 404 en una plataforma de ayuda no es un callejón decorativo: quien llega aquí venía
 * buscando algo. Por eso ofrece las tres salidas reales del recorrido en vez de un enlace
 * genérico al inicio.
 */
export default function NotFound() {
  return (
    <section className="form-section">
      <div className="shell form-shell">
        <div className="form-card">
          <div className="form-body">
            <Compass size={38} color="var(--forest-2)" />
            <h1 style={{ marginTop: 18 }}>Esta página no existe.</h1>
            <p className="lead" style={{ fontSize: 16 }}>
              El enlace puede estar incompleto o haber cambiado. Lo que buscas probablemente esté
              en una de estas tres puertas.
            </p>
            <Link className="button button-dark" href="/">Volver al inicio</Link>
            <p className="form-notice" style={{ marginTop: 14 }}>
              ¿Buscabas el estado de un aporte o de un reporte?{" "}
              <Link href="/seguimiento">Consúltalo con tu código</Link>.
            </p>
          </div>
        </div>
        <aside className="privacy-panel">
          <h2>A dónde ir</h2>
          <ul>
            <li><Search size={18} /><span><Link href="/seguimiento">Seguir un código</Link> que ya tienes.</span></li>
            <li><LifeBuoy size={18} /><span><Link href="/reportar">Reportar una necesidad</Link> que hayas visto.</span></li>
            <li><Compass size={18} /><span><Link href="/transparencia">Ver las cifras públicas</Link> y su método.</span></li>
          </ul>
        </aside>
      </div>
    </section>
  );
}
