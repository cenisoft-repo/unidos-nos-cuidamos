"use client";

import { useState } from "react";
import { ArrowRight, Check, Circle, Clock3, MapPinned, Search, ShieldCheck } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { formatDate } from "@/lib/format";
import { labelStatus } from "@/lib/constants";
import { servesNonProductionData } from "@/lib/environment";
import { StatusPill } from "./status-pill";

type TrackResult = { code: string; record_type: string; safe_status: string; last_update: string; message: string };
type JourneyStage = { label: string; description: string; statuses: string[] };

const DEMO_CODE = "NEC-A1B2C3D4E5F60718293A4B5C";

const journeys: Record<string, JourneyStage[]> = {
  need: [
    { label: "Reporte recibido", description: "El caso quedó protegido.", statuses: ["reported"] },
    { label: "Revisión segura", description: "Una organización contrasta los hechos.", statuses: ["in_verification", "observed"] },
    { label: "Necesidad verificada", description: "Puede coordinarse sin publicar datos sensibles.", statuses: ["verified", "published", "partially_covered"] },
    { label: "Caso resuelto", description: "La cobertura fue conciliada.", statuses: ["covered", "closed", "validated"] },
  ],
  intake: [
    { label: "Registro recibido", description: "El aporte fue registrado, no recibido.", statuses: ["reported"] },
    { label: "Verificación", description: "El equipo revisa soporte y condiciones.", statuses: ["pending_verification", "observed"] },
    { label: "Aporte aprobado", description: "Ya puede coordinarse la recepción.", statuses: ["approved", "scheduled"] },
    { label: "Custodia confirmada", description: "La recepción física quedó registrada.", statuses: ["received", "stored"] },
  ],
  donation: [
    { label: "Compromiso", description: "El aporte fue aceptado para coordinación.", statuses: ["promised", "scheduled"] },
    { label: "Recepción", description: "El centro confirmó cantidad y condición.", statuses: ["received", "stored", "allocated"] },
    { label: "En camino", description: "Existe una salida con custodia registrada.", statuses: ["dispatched", "in_transit"] },
    { label: "Entrega validada", description: "La entrega fue conciliada con evidencia.", statuses: ["delivered", "validated"] },
  ],
};

function journeyIndex(stages: JourneyStage[], status: string) {
  const index = stages.findIndex((stage) => stage.statuses.includes(status));
  return index < 0 ? 0 : index;
}

export function TrackingForm({ initialCode = "" }: { initialCode?: string }) {
  const [code, setCode] = useState(initialCode);
  const [result, setResult] = useState<TrackResult | null>(null);
  const [error, setError] = useState("");
  const [pending, setPending] = useState(false);

  async function search(value = code) {
    if (!value) return;
    setPending(true); setError(""); setResult(null);
    const supabase = createClient();
    const { data, error: queryError } = await supabase.rpc("track_public_code", { p_tracking_code: value.trim().toUpperCase() });
    setPending(false);
    if (queryError) { setError("No fue posible consultar en este momento."); return; }
    const row = Array.isArray(data) ? data[0] : null;
    if (!row) { setError("No encontramos un registro con ese código. Revisa cada carácter e intenta de nuevo."); return; }
    setResult(row as TrackResult);
  }

  const stages = result ? (journeys[result.record_type] ?? journeys.need) : journeys.need;
  const currentStage = result ? journeyIndex(stages, result.safe_status) : 0;

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
          <button className="tracking-demo" type="button" onClick={() => { setCode(DEMO_CODE); setError(""); setResult(null); }}>
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

          <p className="tracking-intro"><Clock3 size={16} /> Actualizado el {formatDate(result.last_update)}. Mostramos hitos del proceso, nunca la ubicación de personas.</p>

          <ol className="tracking-journey" aria-label="Recorrido del registro">
            {stages.map((stage, index) => {
              const completed = index < currentStage;
              const current = index === currentStage;
              return (
                <li className={completed ? "is-complete" : current ? "is-current" : ""} aria-current={current ? "step" : undefined} key={stage.label}>
                  <span className="tracking-step-icon" aria-hidden="true">{completed ? <Check size={15} /> : <Circle size={11} />}</span>
                  <div><strong>{stage.label}</strong><p>{stage.description}</p></div>
                </li>
              );
            })}
          </ol>

          <dl className="tracking-facts">
            <div><dt>Tipo de registro</dt><dd>{result.record_type === "need" ? "Necesidad" : result.record_type === "intake" ? "Reporte de aporte" : "Donación operacional"}</dd></div>
            <div><dt>Código consultado</dt><dd>{result.code}</dd></div>
          </dl>
          <p className="tracking-safe-note"><ShieldCheck size={16} /> {result.message}</p>
        </article>
      )}
    </div>
  );
}
