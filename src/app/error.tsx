"use client";

import { useEffect } from "react";
import { AlertTriangle, RotateCcw } from "lucide-react";

export default function ErrorPage({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error("Vista no disponible", { digest: error.digest });
  }, [error]);

  return (
    <section className="page-hero">
      <div className="shell page-hero-grid">
        <div>
          <p className="eyebrow">Conexión temporalmente interrumpida</p>
          <h1>No mostraremos cifras incompletas.</h1>
          <p className="lead">La información no pudo verificarse contra la base de datos. Tus acciones no se perdieron; vuelve a intentar cuando la conexión esté disponible.</p>
          <button className="button button-dark" type="button" onClick={reset}>
            <RotateCcw size={17} /> Reintentar
          </button>
        </div>
        <aside className="page-aside">
          <AlertTriangle size={22} />
          <strong>Falla segura</strong>
          La plataforma evita reemplazar información ausente por ceros o listas vacías que puedan inducir a error.
        </aside>
      </div>
    </section>
  );
}
