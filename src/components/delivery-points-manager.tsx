"use client";

import { useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { CheckCircle2, LoaderCircle, LocateFixed, MapPin, Pencil, Plus, Search, ShieldCheck } from "lucide-react";
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
type StatusFilter = "all" | "active" | "inactive";
type PurposeFilter = "all" | "acopio" | "despacho";

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

const NAME_MAX = 120;
const LOCATION_MAX = 180;
const ADDRESS_MAX = 300;
const INSTRUCTIONS_MAX = 500;

// Geocodificador para el asistente de dirección. Mismo origen declarado en la CSP
// (connect-src). Nominatim de OpenStreetMap por defecto; configurable por entorno.
const GEOCODER_URL = process.env.NEXT_PUBLIC_GEOCODER_URL || "https://nominatim.openstreetmap.org/search";

type GeocodeResult = {
  display_name: string;
  lat: string;
  lon: string;
  address?: {
    city?: string;
    town?: string;
    village?: string;
    municipality?: string;
    suburb?: string;
    neighbourhood?: string;
    state?: string;
  };
};

// Las coordenadas públicas son aproximadas: se redondean para no revelar el punto exacto.
function approximateCoordinate(value: number) {
  return (Math.round(value * 1e4) / 1e4).toString();
}

// Etiqueta pública de zona a partir del resultado, sin publicar la dirección exacta.
function publicZoneFromResult(result: GeocodeResult) {
  const address = result.address ?? {};
  const city = address.city || address.town || address.village || address.municipality || address.state;
  const area = address.suburb || address.neighbourhood;
  if (city && area) return `${city} · ${area}`;
  if (city) return city;
  return result.display_name.split(",").slice(0, 2).join(",").trim();
}

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

// El nombre operativo sugerido a partir de la organización responsable: acerca el concepto
// «aliado» al de «punto» sin obligar a teclearlo, y solo mientras nadie lo haya editado.
function suggestedName(organizationName: string) {
  return organizationName ? `Acopio ${organizationName}` : "";
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
  const [nameEdited, setNameEdited] = useState(false);
  const [query, setQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");
  const [purposeFilter, setPurposeFilter] = useState<PurposeFilter>("all");
  const [geoQuery, setGeoQuery] = useState("");
  const [geoResults, setGeoResults] = useState<GeocodeResult[]>([]);
  const [geoPending, setGeoPending] = useState(false);
  const [geoNote, setGeoNote] = useState("");
  const idempotencyKey = useRef<string | null>(null);

  const organizationName = useMemo(() => {
    const lookup = new Map(organizations.map((organization) => [organization.id, organization.name]));
    return (id: string) => lookup.get(id) ?? "";
  }, [organizations]);

  function change(patch: Partial<PointForm>) {
    idempotencyKey.current = null;
    setForm((current) => ({ ...current, ...patch }));
    setError("");
    setMessage("");
  }

  // Al elegir la organización responsable en un punto nuevo, propone el nombre operativo
  // mientras el usuario no lo haya escrito a mano.
  function changeOrganization(organizationId: string) {
    setForm((current) => {
      const shouldSuggest = current.id === null && !nameEdited;
      return {
        ...current,
        organizationId,
        name: shouldSuggest ? suggestedName(organizationName(organizationId)) : current.name,
      };
    });
    idempotencyKey.current = null;
    setError("");
    setMessage("");
  }

  function changeName(value: string) {
    setNameEdited(true);
    change({ name: value });
  }

  function startCreate() {
    idempotencyKey.current = null;
    const organizationId = organizations[0]?.id ?? "";
    setForm({ ...blankForm(organizationId), name: suggestedName(organizationName(organizationId)) });
    setNameEdited(false);
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
    setNameEdited(true);
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

  function applyCoordinates(latitude: number, longitude: number) {
    change({ latitude: approximateCoordinate(latitude), longitude: approximateCoordinate(longitude) });
  }

  // Ubicación del dispositivo (permiso del navegador). Solo rellena las coordenadas
  // aproximadas; nunca envía nada a terceros.
  function useMyLocation() {
    if (!("geolocation" in navigator)) {
      setGeoNote("Este navegador no permite usar la ubicación. Ingresa las coordenadas a mano.");
      return;
    }
    setGeoPending(true);
    setGeoNote("");
    navigator.geolocation.getCurrentPosition(
      (position) => {
        applyCoordinates(position.coords.latitude, position.coords.longitude);
        setGeoResults([]);
        setGeoNote("Coordenadas tomadas de tu ubicación. Revísalas y completa la dirección exacta privada.");
        setGeoPending(false);
      },
      () => {
        setGeoNote("No pudimos leer tu ubicación (permiso denegado o sin señal). Usa la búsqueda o las coordenadas manuales.");
        setGeoPending(false);
      },
      { enableHighAccuracy: true, timeout: 10000 },
    );
  }

  // Búsqueda de dirección por texto contra el geocodificador declarado en la CSP.
  async function searchAddress() {
    const term = geoQuery.trim();
    if (term.length < 3) {
      setGeoNote("Escribe al menos 3 caracteres para buscar.");
      return;
    }
    setGeoPending(true);
    setGeoNote("");
    setGeoResults([]);
    try {
      const url = new URL(GEOCODER_URL);
      url.searchParams.set("format", "json");
      url.searchParams.set("addressdetails", "1");
      url.searchParams.set("limit", "6");
      url.searchParams.set("countrycodes", "co");
      url.searchParams.set("accept-language", "es");
      url.searchParams.set("q", term);
      const response = await fetch(url, { headers: { Accept: "application/json" } });
      if (!response.ok) throw new Error("geocoder");
      const results = (await response.json()) as GeocodeResult[];
      setGeoResults(results);
      if (!results.length) setGeoNote("Sin resultados. Ajusta la búsqueda o ingresa las coordenadas a mano.");
    } catch {
      setGeoNote("No fue posible buscar ahora. Usa «Mi ubicación» o ingresa las coordenadas a mano.");
    } finally {
      setGeoPending(false);
    }
  }

  // Aplica un resultado: coordenadas aproximadas, dirección exacta y zona pública sugerida
  // (sin sobrescribir lo que el usuario ya escribió en la zona).
  function pickResult(result: GeocodeResult) {
    change({
      latitude: approximateCoordinate(Number(result.lat)),
      longitude: approximateCoordinate(Number(result.lon)),
      exactAddress: result.display_name.slice(0, ADDRESS_MAX),
      publicLocation: form.publicLocation.trim() || publicZoneFromResult(result).slice(0, LOCATION_MAX),
    });
    setGeoResults([]);
    setGeoNote("Dirección y coordenadas aplicadas. Ajusta la zona pública y verifica antes de guardar.");
  }

  const filteredPoints = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return points.filter((point) => {
      if (statusFilter === "active" && !point.active) return false;
      if (statusFilter === "inactive" && point.active) return false;
      if (purposeFilter === "acopio" && !point.accepts_donations) return false;
      if (purposeFilter === "despacho" && !point.dispatches_shipments) return false;
      if (!needle) return true;
      return (
        point.name.toLowerCase().includes(needle) ||
        point.organization_name.toLowerCase().includes(needle) ||
        point.public_location_text.toLowerCase().includes(needle)
      );
    });
  }, [points, query, statusFilter, purposeFilter]);

  const hasFilters = query.trim() !== "" || statusFilter !== "all" || purposeFilter !== "all";

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
    // Desactivar retira el punto del mapa público y de nuevas solicitudes: se confirma para
    // que nunca sea un descuido, pero sin borrar nada (la trazabilidad se conserva).
    if (form.id && !form.active) {
      const original = points.find((point) => point.id === form.id);
      if (original?.active) {
        const confirmed = globalThis.confirm(
          "El punto quedará inactivo: saldrá del mapa público y de nuevas solicitudes. La trazabilidad se conserva. ¿Continuar?",
        );
        if (!confirmed) return;
      }
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
    if (!form.id) {
      setForm(blankForm(form.organizationId));
      setNameEdited(false);
    }
    router.refresh();
  }

  return <div className="delivery-points-layout">
    <section className="ops-panel delivery-points-list" aria-labelledby="delivery-points-list-title">
      <header className="ops-panel-header"><div><h2 id="delivery-points-list-title"><MapPin size={18} /> Puntos configurados</h2><p>La desactivación conserva la trazabilidad y retira el punto de nuevas solicitudes.</p></div><button className="button button-dark button-small" type="button" onClick={startCreate}><Plus size={15} /> Nuevo punto</button></header>

      {points.length > 0 && <div className="delivery-points-toolbar" role="search">
        <div className="delivery-points-search"><Search size={15} aria-hidden="true" /><input type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Buscar por punto, organización o zona" aria-label="Buscar puntos" /></div>
        <label className="delivery-points-filter"><span>Estado</span><select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value as StatusFilter)}><option value="all">Todos</option><option value="active">Activos</option><option value="inactive">Inactivos</option></select></label>
        <label className="delivery-points-filter"><span>Propósito</span><select value={purposeFilter} onChange={(event) => setPurposeFilter(event.target.value as PurposeFilter)}><option value="all">Todos</option><option value="acopio">Acopio</option><option value="despacho">Despacho</option></select></label>
      </div>}

      {points.length > 0 && <p className="delivery-points-count">{filteredPoints.length} de {points.length} punto{points.length === 1 ? "" : "s"}{hasFilters ? " (filtrado)" : ""}</p>}

      <div className="ops-list">
        {filteredPoints.map((point, index) => {
          const groupHeader = index === 0 || filteredPoints[index - 1].organization_name !== point.organization_name ? point.organization_name : null;
          return <div key={point.id}>
            {groupHeader && <h3 className="delivery-points-group-header">{groupHeader}</h3>}
            <article className="delivery-point-row">
              <div className="delivery-point-title"><div><span className={`delivery-point-status ${point.active ? "is-active" : ""}`}>{point.active ? "Activo" : "Inactivo"}</span><span className="delivery-point-purpose">{purposeLabel(point)}</span><h3>{point.name}</h3><p>{point.organization_name} · {point.public_location_text}</p></div><button className="button button-outline button-small" type="button" onClick={() => startEdit(point)}><Pencil size={14} /> Editar</button></div>
              <dl className="delivery-point-facts">{/* Sin reglas propias el punto no queda sin categorías: hereda las de su organización. */}
                <div><dt>Recibe</dt><dd>{point.accepts_donations ? (point.accepted_categories?.join(", ") || "Hereda las reglas generales de su organización") : "No recibe aportes"}</dd></div><div><dt>Despacha salidas</dt><dd>{point.dispatches_shipments ? "Sí, puede ser origen de un despacho" : "No"}</dd></div><div><dt>Coordenada pública</dt><dd>{point.public_latitude}, {point.public_longitude}</dd></div><div><dt>Cadena de frío</dt><dd>{point.cold_chain_capable ? "Sí" : "No"}</dd></div><div><dt>Instrucción pública</dt><dd>{point.public_instructions || "Sin instrucción adicional"}</dd></div></dl>
            </article>
          </div>;
        })}
        {!points.length && <p className="ops-empty">Todavía no hay puntos parametrizados para este evento.</p>}
        {points.length > 0 && !filteredPoints.length && <p className="ops-empty">Ningún punto coincide con la búsqueda o los filtros.</p>}
      </div>
    </section>

    <form className="ops-panel delivery-point-form" id="delivery-point-form" onSubmit={submit}>
      <header className="ops-panel-header"><div><h2>{form.id ? "Editar punto" : "Crear punto"}</h2><p>Los campos públicos se muestran en el mapa y al registrar aportes. La dirección exacta permanece privada.</p></div></header>
      <div className="delivery-point-form-body">
        {error && <p className="form-error" role="alert">{error}</p>}
        {message && <p className="form-success" role="status"><CheckCircle2 size={16} /> {message}</p>}
        <div className="field"><label htmlFor="point-organization">Organización responsable <span aria-hidden="true">*</span></label><select id="point-organization" value={form.organizationId} onChange={(event) => changeOrganization(event.target.value)} disabled={Boolean(form.id)} required>{organizations.map((organization) => <option value={organization.id} key={organization.id}>{organization.name}</option>)}</select><small>Define quién puede reportar y operar sobre este punto.</small></div>
        <div className="field"><label htmlFor="point-name">Nombre operativo <span aria-hidden="true">*</span></label><input id="point-name" value={form.name} onChange={(event) => changeName(event.target.value)} minLength={3} maxLength={NAME_MAX} placeholder="Ej. Centro de recepción norte" required /><small className="field-counter">{form.name.length}/{NAME_MAX}</small></div>
        <div className="field"><label htmlFor="point-public-location">Zona pública aproximada <span aria-hidden="true">*</span></label><input id="point-public-location" value={form.publicLocation} onChange={(event) => change({ publicLocation: event.target.value })} minLength={3} maxLength={LOCATION_MAX} placeholder="Ej. Cali · zona norte" required /><small>No publiques una dirección exacta ni datos personales. <span className="field-counter">{form.publicLocation.length}/{LOCATION_MAX}</span></small></div>
        <div className="field location-assistant">
          <label htmlFor="point-geo-search">Asistente de ubicación (opcional)</label>
          <div className="location-assistant-row">
            <div className="location-assistant-search"><Search size={15} aria-hidden="true" /><input id="point-geo-search" value={geoQuery} onChange={(event) => setGeoQuery(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter") { event.preventDefault(); searchAddress(); } }} placeholder="Busca una dirección o lugar. Ej. Cra 5 # 10-20, Cali" /></div>
            <button className="button button-outline button-small" type="button" onClick={searchAddress} disabled={geoPending}>{geoPending ? <LoaderCircle className="spin" size={14} /> : <Search size={14} />} Buscar</button>
            <button className="button button-outline button-small" type="button" onClick={useMyLocation} disabled={geoPending}><LocateFixed size={14} /> Mi ubicación</button>
          </div>
          <small>Rellena las coordenadas aproximadas y la dirección exacta privada. Siempre revisa antes de guardar.</small>
          {geoNote && <p className="location-assistant-note" role="status">{geoNote}</p>}
          {geoResults.length > 0 && <ul className="location-results">{geoResults.map((result, index) => <li key={`${result.lat}-${result.lon}-${index}`}><button type="button" onClick={() => pickResult(result)}><MapPin size={13} aria-hidden="true" /> {result.display_name}</button></li>)}</ul>}
        </div>
        <div className="field"><label htmlFor="point-exact-address">Dirección exacta privada <span aria-hidden="true">*</span></label><input id="point-exact-address" value={form.exactAddress} onChange={(event) => change({ exactAddress: event.target.value })} minLength={5} maxLength={ADDRESS_MAX} placeholder="Visible solo para el equipo autorizado" required /><small className="field-counter">{form.exactAddress.length}/{ADDRESS_MAX}</small></div>
        <div className="field"><label htmlFor="point-public-instructions">Instrucciones públicas (opcional)</label><textarea id="point-public-instructions" value={form.publicInstructions} onChange={(event) => change({ publicInstructions: event.target.value })} maxLength={INSTRUCTIONS_MAX} placeholder="Ej. Coordina el horario después de recibir tu código APO." /><small>Sin teléfonos personales, nombres de personas ni dirección exacta. <span className="field-counter">{form.publicInstructions.length}/{INSTRUCTIONS_MAX}</span></small></div>
        <div className="field-grid"><div className="field"><label htmlFor="point-latitude">Latitud aproximada <span aria-hidden="true">*</span></label><input id="point-latitude" type="number" min="-4.5" max="13.5" step="0.0001" value={form.latitude} onChange={(event) => change({ latitude: event.target.value })} required /></div><div className="field"><label htmlFor="point-longitude">Longitud aproximada <span aria-hidden="true">*</span></label><input id="point-longitude" type="number" min="-82" max="-66.5" step="0.0001" value={form.longitude} onChange={(event) => change({ longitude: event.target.value })} required /></div></div>
        <fieldset className="delivery-purpose-fieldset">
          <legend>¿Para qué sirve este punto? <span aria-hidden="true">*</span></legend>
          <label className="form-check"><input type="checkbox" checked={form.acceptsDonations} onChange={(event) => change({ acceptsDonations: event.target.checked })} /><span><strong>Centro de acopio</strong><small>Recibe aportes. Aparece en el mapa público y en el paso «Punto de entrega» del aliado.</small></span></label>
          <label className="form-check"><input type="checkbox" checked={form.dispatchesShipments} onChange={(event) => change({ dispatchesShipments: event.target.checked })} /><span><strong>Centro de despacho</strong><small>Puede ser el origen de una salida hacia una necesidad. No se publica como punto de recepción.</small></span></label>
        </fieldset>
        {form.acceptsDonations && <fieldset className="delivery-category-fieldset"><legend>Categorías que recibe <span aria-hidden="true">*</span> <span className="delivery-category-count">{form.acceptedCategories.length} seleccionada{form.acceptedCategories.length === 1 ? "" : "s"}</span></legend><div className="delivery-category-grid">{categories.map((category) => <label key={category}><input type="checkbox" checked={form.acceptedCategories.includes(category)} onChange={() => toggleCategory(category)} /><span>{category}</span></label>)}</div></fieldset>}
        <label className="form-check"><input type="checkbox" checked={form.coldChain} onChange={(event) => change({ coldChain: event.target.checked })} /><span><strong>Cuenta con cadena de frío</strong><small>Habilita aportes que requieren conservación refrigerada.</small></span></label>
        <label className="form-check"><input type="checkbox" checked={form.active} onChange={(event) => change({ active: event.target.checked })} /><span><strong>Punto activo</strong><small>Si está inactivo no aparece en nuevas solicitudes ni en el mapa público.</small></span></label>
        <p className="delivery-point-security"><ShieldCheck size={17} /><span>Guardar crea una versión auditada de las reglas. No se eliminan puntos ni se reescribe el historial.</span></p>
        <button className="button button-dark" type="submit" disabled={pending}>{pending ? <><LoaderCircle className="spin" size={16} /> Guardando…</> : form.id ? "Guardar cambios" : "Crear punto de entrega"}</button>
      </div>
    </form>
  </div>;
}
