"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { CheckCircle2, LoaderCircle, MapPin, Pencil, Plus, ShieldCheck } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { EVENT_ID } from "@/lib/constants";
import { toOperationalMessage } from "@/lib/user-errors";

export type DeliveryPointAdmin = {
  id: string;
  organization_id: string;
  organization_name: string;
  name: string;
  public_location_text: string;
  exact_address_private: string | null;
  public_instructions: string | null;
  public_latitude: number | null;
  public_longitude: number | null;
  cold_chain_capable: boolean;
  active: boolean;
  accepts_donations: boolean;
  dispatches_shipments: boolean;
  accepted_categories: string[] | null;
  updated_at: string;
};

type OrganizationOption = { id: string; name: string };

type PointForm = {
  id: string | null;
  organizationId: string;
  name: string;
  publicLocation: string;
  exactAddress: string;
  publicInstructions: string;
  latitude: string;
  longitude: string;
  coldChain: boolean;
  active: boolean;
  acceptsDonations: boolean;
  dispatchesShipments: boolean;
  acceptedCategories: string[];
};

function blankForm(organizationId: string): PointForm {
  return {
    id: null,
    organizationId,
    name: "",
    publicLocation: "",
    exactAddress: "",
    publicInstructions: "",
    latitude: "3.4516",
    longitude: "-76.5320",
    coldChain: false,
    active: true,
    acceptsDonations: true,
    dispatchesShipments: false,
    acceptedCategories: [],
  };
}

function purposeLabel(point: { accepts_donations: boolean; dispatches_shipments: boolean }) {
  if (point.accepts_donations && point.dispatches_shipments) return "Acopio y despacho";
  if (point.accepts_donations) return "Solo acopio";
  return "Solo despacho";
}

export function DeliveryPointsManager({
  organizations,
  points,
  categories,
}: {
  organizations: OrganizationOption[];
  points: DeliveryPointAdmin[];
  categories: string[];
}) {
  const router = useRouter();
  const [form, setForm] = useState<PointForm>(() => blankForm(organizations[0]?.id ?? ""));
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const idempotencyKey = useRef<string | null>(null);

  function change(patch: Partial<PointForm>) {
    idempotencyKey.current = null;
    setForm((current) => ({ ...current, ...patch }));
    setError("");
    setMessage("");
  }

  function startCreate() {
    idempotencyKey.current = null;
    setForm(blankForm(organizations[0]?.id ?? ""));
    setError("");
    setMessage("");
    document.getElementById("delivery-point-form")?.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  function startEdit(point: DeliveryPointAdmin) {
    idempotencyKey.current = null;
    setForm({
      id: point.id,
      organizationId: point.organization_id,
      name: point.name,
      publicLocation: point.public_location_text,
      exactAddress: point.exact_address_private ?? "",
      publicInstructions: point.public_instructions ?? "",
      latitude: point.public_latitude?.toString() ?? "",
      longitude: point.public_longitude?.toString() ?? "",
      coldChain: point.cold_chain_capable,
      active: point.active,
      acceptsDonations: point.accepts_donations,
      dispatchesShipments: point.dispatches_shipments,
      acceptedCategories: point.accepted_categories ?? [],
    });
    setError("");
    setMessage("");
    document.getElementById("delivery-point-form")?.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  function toggleCategory(category: string) {
    change({
      acceptedCategories: form.acceptedCategories.includes(category)
        ? form.acceptedCategories.filter((value) => value !== category)
        : [...form.acceptedCategories, category].sort(),
    });
  }

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!form.acceptsDonations && !form.dispatchesShipments) {
      setError("Indica para qué sirve el punto: recibir aportes, despachar salidas o ambas cosas.");
      return;
    }
    if (form.acceptsDonations && !form.acceptedCategories.length) {
      setError("Un punto que recibe aportes necesita al menos una categoría aceptada.");
      return;
    }

    setPending(true);
    setError("");
    setMessage("");
    idempotencyKey.current ??= globalThis.crypto.randomUUID();
    const supabase = createClient();
    const { error: submitError } = await supabase.rpc("manage_delivery_point", {
      p_location_id: form.id,
      p_event_id: EVENT_ID,
      p_organization_id: form.organizationId,
      p_name: form.name.trim(),
      p_public_location_text: form.publicLocation.trim(),
      p_exact_address_private: form.exactAddress.trim(),
      p_public_instructions: form.publicInstructions.trim() || null,
      p_public_latitude: Number(form.latitude),
      p_public_longitude: Number(form.longitude),
      p_cold_chain_capable: form.coldChain,
      p_active: form.active,
      p_accepts_donations: form.acceptsDonations,
      p_dispatches_shipments: form.dispatchesShipments,
      // Un punto que solo despacha no declara categorías de recepción.
      p_accepted_categories: form.acceptsDonations ? [...form.acceptedCategories].sort() : [],
      p_idempotency_key: idempotencyKey.current,
    });
    setPending(false);

    if (submitError) {
      setError(toOperationalMessage(submitError, "No fue posible guardar el punto de entrega."));
      return;
    }

    idempotencyKey.current = null;
    setMessage(form.id ? "La parametrización quedó actualizada y auditada." : "El punto de entrega quedó creado y auditado.");
    if (!form.id) setForm(blankForm(form.organizationId));
    router.refresh();
  }

  return <div className="delivery-points-layout">
    <section className="ops-panel delivery-points-list" aria-labelledby="delivery-points-list-title">
      <header className="ops-panel-header"><div><h2 id="delivery-points-list-title"><MapPin size={18} /> Puntos configurados</h2><p>La desactivación conserva la trazabilidad y retira el punto de nuevas solicitudes.</p></div><button className="button button-dark button-small" type="button" onClick={startCreate}><Plus size={15} /> Nuevo punto</button></header>
      <div className="ops-list">
        {points.map((point) => <article className="delivery-point-row" key={point.id}>
          <div className="delivery-point-title"><div><span className={`delivery-point-status ${point.active ? "is-active" : ""}`}>{point.active ? "Activo" : "Inactivo"}</span><span className="delivery-point-purpose">{purposeLabel(point)}</span><h3>{point.name}</h3><p>{point.organization_name} · {point.public_location_text}</p></div><button className="button button-outline button-small" type="button" onClick={() => startEdit(point)}><Pencil size={14} /> Editar</button></div>
          <dl className="delivery-point-facts">{/* Sin reglas propias el punto no queda sin categorías: hereda las de su organización. */}
            <div><dt>Recibe</dt><dd>{point.accepts_donations ? (point.accepted_categories?.join(", ") || "Hereda las reglas generales de su organización") : "No recibe aportes"}</dd></div><div><dt>Despacha salidas</dt><dd>{point.dispatches_shipments ? "Sí, puede ser origen de un despacho" : "No"}</dd></div><div><dt>Coordenada pública</dt><dd>{point.public_latitude}, {point.public_longitude}</dd></div><div><dt>Cadena de frío</dt><dd>{point.cold_chain_capable ? "Sí" : "No"}</dd></div><div><dt>Instrucción pública</dt><dd>{point.public_instructions || "Sin instrucción adicional"}</dd></div></dl>
        </article>)}
        {!points.length && <p className="ops-empty">Todavía no hay puntos parametrizados para este evento.</p>}
      </div>
    </section>

    <form className="ops-panel delivery-point-form" id="delivery-point-form" onSubmit={submit}>
      <header className="ops-panel-header"><div><h2>{form.id ? "Editar punto" : "Crear punto"}</h2><p>Los campos públicos se muestran en el mapa y al registrar aportes. La dirección exacta permanece privada.</p></div></header>
      <div className="delivery-point-form-body">
        {error && <p className="form-error" role="alert">{error}</p>}
        {message && <p className="form-success" role="status"><CheckCircle2 size={16} /> {message}</p>}
        <div className="field"><label htmlFor="point-organization">Organización responsable <span aria-hidden="true">*</span></label><select id="point-organization" value={form.organizationId} onChange={(event) => change({ organizationId: event.target.value })} disabled={Boolean(form.id)} required>{organizations.map((organization) => <option value={organization.id} key={organization.id}>{organization.name}</option>)}</select><small>Define quién puede reportar y operar sobre este punto.</small></div>
        <div className="field"><label htmlFor="point-name">Nombre operativo <span aria-hidden="true">*</span></label><input id="point-name" value={form.name} onChange={(event) => change({ name: event.target.value })} minLength={3} maxLength={120} placeholder="Ej. Centro de recepción norte" required /></div>
        <div className="field"><label htmlFor="point-public-location">Zona pública aproximada <span aria-hidden="true">*</span></label><input id="point-public-location" value={form.publicLocation} onChange={(event) => change({ publicLocation: event.target.value })} minLength={3} maxLength={180} placeholder="Ej. Cali · zona norte" required /><small>No publiques una dirección exacta ni datos personales.</small></div>
        <div className="field"><label htmlFor="point-exact-address">Dirección exacta privada <span aria-hidden="true">*</span></label><input id="point-exact-address" value={form.exactAddress} onChange={(event) => change({ exactAddress: event.target.value })} minLength={5} maxLength={300} placeholder="Visible solo para el equipo autorizado" required /></div>
        <div className="field"><label htmlFor="point-public-instructions">Instrucciones públicas (opcional)</label><textarea id="point-public-instructions" value={form.publicInstructions} onChange={(event) => change({ publicInstructions: event.target.value })} maxLength={500} placeholder="Ej. Coordina el horario después de recibir tu código APO." /><small>Sin teléfonos personales, nombres de personas ni dirección exacta.</small></div>
        <div className="field-grid"><div className="field"><label htmlFor="point-latitude">Latitud aproximada <span aria-hidden="true">*</span></label><input id="point-latitude" type="number" min="-4.5" max="13.5" step="0.0001" value={form.latitude} onChange={(event) => change({ latitude: event.target.value })} required /></div><div className="field"><label htmlFor="point-longitude">Longitud aproximada <span aria-hidden="true">*</span></label><input id="point-longitude" type="number" min="-82" max="-66.5" step="0.0001" value={form.longitude} onChange={(event) => change({ longitude: event.target.value })} required /></div></div>
        <fieldset className="delivery-purpose-fieldset">
          <legend>¿Para qué sirve este punto? <span aria-hidden="true">*</span></legend>
          <label className="form-check"><input type="checkbox" checked={form.acceptsDonations} onChange={(event) => change({ acceptsDonations: event.target.checked })} /><span><strong>Centro de acopio</strong><small>Recibe aportes. Aparece en el mapa público y en el paso «Punto de entrega» del aliado.</small></span></label>
          <label className="form-check"><input type="checkbox" checked={form.dispatchesShipments} onChange={(event) => change({ dispatchesShipments: event.target.checked })} /><span><strong>Centro de despacho</strong><small>Puede ser el origen de una salida hacia una necesidad. No se publica como punto de recepción.</small></span></label>
        </fieldset>
        {form.acceptsDonations && <fieldset className="delivery-category-fieldset"><legend>Categorías que recibe <span aria-hidden="true">*</span></legend><div className="delivery-category-grid">{categories.map((category) => <label key={category}><input type="checkbox" checked={form.acceptedCategories.includes(category)} onChange={() => toggleCategory(category)} /><span>{category}</span></label>)}</div></fieldset>}
        <label className="form-check"><input type="checkbox" checked={form.coldChain} onChange={(event) => change({ coldChain: event.target.checked })} /><span><strong>Cuenta con cadena de frío</strong><small>Habilita aportes que requieren conservación refrigerada.</small></span></label>
        <label className="form-check"><input type="checkbox" checked={form.active} onChange={(event) => change({ active: event.target.checked })} /><span><strong>Punto activo</strong><small>Si está inactivo no aparece en nuevas solicitudes ni en el mapa público.</small></span></label>
        <p className="delivery-point-security"><ShieldCheck size={17} /><span>Guardar crea una versión auditada de las reglas. No se eliminan puntos ni se reescribe el historial.</span></p>
        <button className="button button-dark" type="submit" disabled={pending}>{pending ? <><LoaderCircle className="spin" size={16} /> Guardando…</> : form.id ? "Guardar cambios" : "Crear punto de entrega"}</button>
      </div>
    </form>
  </div>;
}
