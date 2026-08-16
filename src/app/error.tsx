"use client";

import { useEffect } from "react";
import { RotateCcw } from "lucide-react";

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
          <p className="eyebrow">Información no disponible</p>
          <h1>No mostraremos cifras incompletas.</h1>
          <p className="lead">No pudimos cargar esta información. Tus acciones no se perdieron: vuelve a intentarlo en unos momentos.</p>
          <button className="button button-dark" type="button" onClick={reset}>
            <RotateCcw size={17} /> Reintentar
          </button>
        </div>
      </div>
    </section>
  );
}
