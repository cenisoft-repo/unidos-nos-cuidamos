"use client";

import { useState } from "react";
import { ArrowRight, Check, Clock3, MapPinned, Search, ShieldCheck } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { formatDate } from "@/lib/format";
import { labelStatus } from "@/lib/constants";
import { servesNonProductionData } from "@/lib/environment";
import { StatusPill } from "./status-pill";

type TrackResult = { code: string; record_type: string; safe_status: string; last_update: string; message: string };
type JourneyStep = { step: number; stage_key: string; stage_label: string; detail: string; occurred_at: string; related_code: string };

const DEMO_CODE = "NEC-A1B2C3D4E5F60718293A4B5C";

// Qué falta después de cada hito confirmado. Se describe el siguiente control, no una
// promesa de tiempo: el recorrido depende de decisiones humanas, no de un temporizador.
const NEXT_STEP: Record<string, string> = {
  need_reported: "Una organización autorizada debe contrastar los hechos antes de publicar el caso.",
  need_verified: "Falta publicar el caso para que pueda recibir aportes.",
  need_published: "El caso ya puede recibir aportes. La cobertura avanza cuando se validan entregas.",
  intake_reported: "El equipo debe revisar los datos y soportes antes de coordinar la recepción.",
  intake_approved: "Falta que el centro confirme físicamente la recepción.",
  donation_opened: "Falta que el centro confirme físicamente la recepción.",
  stock_received: "La existencia está en custodia y espera ser reservada para un caso verificado.",
  stock_allocated: "Falta crear la salida hacia la zona de destino.",
  shipment_dispatched: "Falta registrar el resultado de la entrega.",
  delivery_registered: "Falta la validación de una persona distinta de quien entregó.",
  delivery_validated: "El recorrido está completo y la cobertura pública ya lo refleja.",
  money_reconciled: "El aporte quedó conciliado contra un soporte y publicado como monto verificado.",
};

const RECORD_LABELS: Record<string, string> = {
  need: "Necesidad",
  intake: "Reporte de aporte",
  donation: "Donación operacional",
};

export function TrackingForm({ initialCode = "" }: { initialCode?: string }) {
  const [code, setCode] = useState(initialCode);
  const [result, setResult] = useState<TrackResult | null>(null);
  const [journey, setJourney] = useState<JourneyStep[]>([]);
  const [error, setError] = useState("");
  const [pending, setPending] = useState(false);

  async function search(value = code) {
    if (!value) return;
    setPending(true); setError(""); setResult(null); setJourney([]);
    const supabase = createClient();
    const normalized = value.trim().toUpperCase();
    // Se consultan a la vez el estado vigente y la cadena de hitos: la primera responde
    // «en qué punto está» y la segunda «por dónde pasó y cuándo».
    const [summary, steps] = await Promise.all([
      supabase.rpc("track_public_code", { p_tracking_code: normalized }),
      supabase.rpc("track_public_journey", { p_tracking_code: normalized }),
    ]);
    setPending(false);
    if (summary.error || steps.error) { setError("No fue posible consultar en este momento."); return; }
    const row = Array.isArray(summary.data) ? summary.data[0] : null;
    if (!row) { setError("No encontramos un registro con ese código. Revisa cada carácter e intenta de nuevo."); return; }
    setResult(row as TrackResult);
    setJourney((steps.data ?? []) as JourneyStep[]);
  }

  const lastStep = journey.at(-1);
  const nextStep = lastStep ? NEXT_STEP[lastStep.stage_key] : undefined;
  // Un aporte se sigue con dos códigos: el del reporte y el operacional. Mostrar ambos
  // evita que el donante crea que su APO dejó de avanzar cuando en realidad avanzó el DON.
  const relatedCodes = [...new Set(journey.map((step) => step.related_code).filter(Boolean))];

  return (
    <div className="tracking-panel">
      <form className="tracking-search" onSubmit={(event) => { event.preventDefault(); void search(); }}>
        <div className="field">
          <label htmlFor="tracking-code">Código de seguimiento</label>
          <div className="tracking-input-wrap"><MapPinned size={18} aria-hidden="true" /><input id="tracking-code" value={code} onChange={(event) => setCode(event.target.value.toUpperCase())} placeholder="NEC-… / APO-… / DON-…" minLength={28} maxLength={28} required /></div>
          <small>Empieza por NEC, APO o DON y tiene 28 caracteres.</small>
        </div>
        <button className="button button-dark button-block" disabled={pending}><Search size={17} /> {pending ? "Consultando…" : "Ver mi recorrido"}</button>
        {servesNonProductionData && (
          <button className="tracking-demo" type="button" onClick={() => { setCode(DEMO_CODE); setError(""); setResult(null); setJourney([]); }}>
            Usar un código de práctica <ArrowRight size={14} />
          </button>
        )}
      </form>

      {error && <p className="form-error" role="alert" style={{ marginTop: 20 }}>{error}</p>}

      {result && (
        <article className="tracking-result">
          <header className="tracking-result-head">
            <div className="tracking-result-icon"><ShieldCheck size={21} /></div>
            <div><span>Estado actual</span><h2>{labelStatus(result.safe_status)}</h2></div>
            <StatusPill status={result.safe_status} />
          </header>

          <p className="tracking-intro"><Clock3 size={16} /> Actualizado el {formatDate(result.last_update)}. Mostramos hitos comprobados del proceso, nunca la ubicación de personas.</p>

          {journey.length > 0 ? (
            <ol className="tracking-journey" aria-label="Hitos comprobados del recorrido">
              {journey.map((step) => (
                <li className="is-complete" key={`${step.stage_key}-${step.occurred_at}`}>
                  <span className="tracking-step-icon" aria-hidden="true"><Check size={15} /></span>
                  <div>
                    <strong>{step.stage_label}</strong>
                    <p>{step.detail}</p>
                    <small className="tracking-step-meta">{formatDate(step.occurred_at)}{step.related_code ? ` · ${step.related_code}` : ""}</small>
                  </div>
                </li>
              ))}
              {nextStep && (
                <li className="is-current" aria-current="step">
                  <span className="tracking-step-icon" aria-hidden="true" />
                  <div><strong>Siguiente control</strong><p>{nextStep}</p></div>
                </li>
              )}
            </ol>
          ) : (
            <p className="tracking-empty-journey">Todavía no hay hitos comprobados para este código. Aparecerán a medida que el equipo autorizado registre cada control.</p>
          )}

          <dl className="tracking-facts">
            <div><dt>Tipo de registro</dt><dd>{RECORD_LABELS[result.record_type] ?? result.record_type}</dd></div>
            <div><dt>Código consultado</dt><dd>{result.code}</dd></div>
            {relatedCodes.length > 1 && <div><dt>Códigos del recorrido</dt><dd>{relatedCodes.join(" · ")}</dd></div>}
          </dl>
          <p className="tracking-safe-note"><ShieldCheck size={16} /> {result.message}</p>
        </article>
      )}
    </div>
  );
}
