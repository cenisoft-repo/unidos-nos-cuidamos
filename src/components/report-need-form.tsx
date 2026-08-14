"use client";

import { useState } from "react";
import { CheckCircle2, LoaderCircle } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { DEMO_EVENT_ID, NEED_CATEGORIES, NORMALIZED_UNITS } from "@/lib/constants";
import { CategoryIcon } from "./category-icon";

type Result = { tracking_code: string; status: string };

export function ReportNeedForm() {
  const [category, setCategory] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const [result, setResult] = useState<Result | null>(null);

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setError("");
    const formElement = event.currentTarget;
    const form = new FormData(formElement);
    const supabase = createClient();
    const { data, error: submitError } = await supabase.rpc("submit_need_report", {
      p_event_id: DEMO_EVENT_ID,
      p_category: String(form.get("category")),
      p_description: String(form.get("description")),
      p_public_location: String(form.get("public_location")),
      p_quantity: Number(form.get("quantity")),
      p_unit: String(form.get("unit")),
      p_exact_address_private: String(form.get("exact_address") ?? ""),
      p_contact_private: { email: String(form.get("email") ?? "") },
    });
    setPending(false);
    if (submitError) {
      setError(submitError.message);
      return;
    }
    const row = Array.isArray(data) ? data[0] : data;
    setResult(row as Result);
    setCategory("");
    formElement.reset();
  }

  if (result) {
    return (
      <div className="form-card">
        <div className="form-body">
          <CheckCircle2 size={38} color="var(--forest-2)" />
          <h2 style={{ marginTop: 18 }}>Reporte recibido, aún no publicado.</h2>
          <p className="lead" style={{ fontSize: 16 }}>Una persona autorizada debe verificar hechos, vigencia, ubicación y posibles duplicados.</p>
          <div className="form-success">
            Código seguro: <strong>{result.tracking_code}</strong><br />Guárdalo para consultar, corregir o retirar el reporte.
          </div>
          <a className="button button-dark" href={`/seguimiento?codigo=${result.tracking_code}`}>Consultar seguimiento</a>
        </div>
      </div>
    );
  }

  return (
    <form className="form-card" onSubmit={handleSubmit}>
      <div className="form-card-header"><h2>Cuéntanos qué está pasando</h2><p>Reporta hechos observables. Nuestro equipo determina prioridad y ruta de atención.</p></div>
      <div className="form-body">
        {error && <p className="form-error" role="alert">{error}</p>}
        <p className="form-notice"><strong>¿Hay riesgo vital inmediato?</strong> Contacta a la autoridad de emergencias. Este formulario no despacha rescate ni personal clínico.</p>
        <fieldset className="report-category-fieldset"><legend>¿Qué tipo de ayuda hace falta?</legend><div className="report-category-grid">{NEED_CATEGORIES.map((value) => <label key={value}><input type="radio" name="category" value={value} checked={category === value} onChange={() => setCategory(value)} required /><CategoryIcon category={value} size={22} /><span>{value}</span></label>)}</div></fieldset>
        <div className="field"><label htmlFor="public_location">Zona aproximada</label><input id="public_location" name="public_location" placeholder="Municipio y sector amplio" minLength={4} maxLength={120} required /><small>Usa una referencia amplia; esto puede mostrarse públicamente.</small></div>
        <div className="field"><label htmlFor="description">Hechos observados</label><textarea id="description" name="description" placeholder="Describe quién necesita qué, desde cuándo y qué fuente lo confirma. No incluyas teléfonos, cuentas ni enlaces." minLength={20} maxLength={2000} required /></div>
        <div className="field-grid">
          <div className="field"><label htmlFor="quantity">Cantidad aproximada</label><input id="quantity" name="quantity" type="number" min="0.001" step="0.001" placeholder="Ej. 50" required /></div>
          <div className="field"><label htmlFor="unit">Unidad</label><select id="unit" name="unit" required defaultValue=""><option value="" disabled>Selecciona</option>{NORMALIZED_UNITS.map((value) => <option key={value}>{value}</option>)}</select></div>
        </div>
        <div className="field"><label htmlFor="exact_address">Ubicación exacta (privada y opcional)</label><input id="exact_address" name="exact_address" maxLength={240} placeholder="Solo para verificación autorizada" /><small>Nunca aparece en el mapa público.</small></div>
        <div className="field"><label htmlFor="email">Correo de contacto (privado y opcional)</label><input id="email" name="email" type="email" maxLength={160} autoComplete="email" placeholder="nombre@ejemplo.org" /></div>
        <label className="form-check"><input type="checkbox" required /><span>Confirmo que el reporte es de buena fe y que no incluí datos bancarios, teléfonos en campos públicos ni información que exponga a personas vulnerables.</span></label>
        <button className="button button-dark button-block" disabled={pending} type="submit">{pending ? <><LoaderCircle size={17} /> Enviando…</> : "Enviar a verificación"}</button>
      </div>
    </form>
  );
}
