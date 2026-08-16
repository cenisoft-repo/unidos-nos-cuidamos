"use client";

import { useRef, useState } from "react";
import Link from "next/link";
import {
  Banknote,
  BadgeCheck,
  Check,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  HeartHandshake,
  LoaderCircle,
  MapPin,
  PackageCheck,
  Plus,
  Printer,
  Trash2,
} from "lucide-react";
import { QRCodeSVG } from "qrcode.react";
import { createClient } from "@/lib/supabase/client";
import { toOperationalMessage } from "@/lib/user-errors";
import { COLOMBIA_DEPARTMENTS, DEMO_EVENT_ID, DONOR_TYPES, ECONOMIC_SECTORS, NEED_CATEGORIES, NORMALIZED_UNITS } from "@/lib/constants";
import type { PublicCollectionCenter } from "@/lib/public-types";
import { CategoryIcon } from "./category-icon";

type Item = {
  category: string;
  description: string;
  quantity: string;
  unit: string;
  condition: string;
  storage_requirement: string;
  declared_estimated_value_cop: string;
};

type DonorDetails = {
  legalName: string;
  email: string;
  phone: string;
  attributionKind: string;
  publicAttribution: string;
  attributionAuthorized: boolean;
};

type ReportingContext = {
  donorType: string;
  economicSector: string;
  specificDestination: boolean;
  destinationNote: string;
  destinationDepartment: string;
  destinationMunicipality: string;
  estimatedBeneficiaries: string;
  deliveryChannel: string;
  internalResponsible: string;
  internalContact: string;
  observations: string;
};

const STEP_LABELS = ["Qué donarás", "Cantidad", "Dónde llevarlo", "Tus datos", "Confirmar"];
const blankItem = (category = ""): Item => ({ category, description: "", quantity: "", unit: "", condition: "sellado", storage_requirement: "ambiente", declared_estimated_value_cop: "" });

export function DonationIntakeForm({
  organizationId,
  organizationName,
  centers,
  initialCenterId,
}: {
  organizationId: string;
  organizationName: string;
  centers: PublicCollectionCenter[];
  initialCenterId?: string;
}) {
  const [step, setStep] = useState(1);
  const [kind, setKind] = useState<"in_kind" | "money">("in_kind");
  const [items, setItems] = useState<Item[]>([blankItem()]);
  const [declaredAmount, setDeclaredAmount] = useState("");
  const [declaredStatus, setDeclaredStatus] = useState("comprometida");
  const [preferredLocationId, setPreferredLocationId] = useState(
    centers.some((center) => center.id === initialCenterId) ? (initialCenterId ?? "") : (centers[0]?.id ?? ""),
  );
  const [donor, setDonor] = useState<DonorDetails>({
    legalName: "",
    email: "",
    phone: "",
    attributionKind: "anonymous",
    publicAttribution: "",
    attributionAuthorized: false,
  });
  const [reporting, setReporting] = useState<ReportingContext>({
    donorType: "",
    economicSector: "",
    specificDestination: false,
    destinationNote: "",
    destinationDepartment: "",
    destinationMunicipality: "",
    estimatedBeneficiaries: "",
    deliveryChannel: "",
    internalResponsible: "",
    internalContact: "",
    observations: "",
  });
  const [declarationAccepted, setDeclarationAccepted] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const [stepError, setStepError] = useState("");
  const [trackingCode, setTrackingCode] = useState("");
  const keyRef = useRef<string | null>(null);

  const selectedCenter = centers.find((center) => center.id === preferredLocationId);

  function updateItem(index: number, field: keyof Item, value: string) {
    setItems((current) => current.map((item, itemIndex) => itemIndex === index ? { ...item, [field]: value } : item));
  }

  function selectCategory(category: string) {
    setItems((current) => current.map((item, index) => index === 0 ? { ...item, category } : item));
    setStepError("");
  }

  function validationMessage(currentStep: number) {
    if (currentStep === 1 && kind === "in_kind" && !items[0]?.category) return "Elige la categoría que mejor describe tu ayuda.";
    if (currentStep === 2 && kind === "money" && Number(declaredAmount) <= 0) return "Escribe un monto mayor que cero.";
    if (currentStep === 2 && kind === "in_kind" && items.some((item) => item.description.trim().length < 3 || Number(item.quantity) <= 0 || !item.unit)) return "Completa la descripción, cantidad y unidad de cada artículo.";
    if (currentStep === 2 && kind === "in_kind" && items.some((item) => item.declared_estimated_value_cop && Number(item.declared_estimated_value_cop) <= 0)) return "El valor estimado debe ser mayor que cero o quedar vacío.";
    if (currentStep === 3 && kind === "in_kind" && !preferredLocationId) return "Selecciona un centro para coordinar la entrega.";
    if (currentStep === 3 && reporting.specificDestination && (!reporting.destinationDepartment || reporting.destinationMunicipality.trim().length < 2)) return "Completa el departamento y el municipio o zona de la destinación específica.";
    if (currentStep === 3 && reporting.estimatedBeneficiaries && Number(reporting.estimatedBeneficiaries) <= 0) return "La estimación de beneficiarios debe ser mayor que cero.";
    if (currentStep === 4 && donor.legalName.trim().length < 2) return "Escribe el nombre privado de la empresa o persona donante.";
    if (currentStep === 4 && !/^\S+@\S+\.\S+$/.test(donor.email)) return "Escribe un correo válido para la coordinación privada.";
    if (currentStep === 4 && ["alias", "authorized_name"].includes(donor.attributionKind) && donor.publicAttribution.trim().length < 2) return "Escribe cómo quieres que aparezca la atribución pública.";
    if (currentStep === 4 && donor.attributionKind === "authorized_name" && !donor.attributionAuthorized) return "Confirma que cuentas con autorización para publicar ese nombre.";
    return "";
  }

  function goNext() {
    const message = validationMessage(step);
    if (message) {
      setStepError(message);
      return;
    }
    setStepError("");
    setStep((current) => Math.min(5, current + 1));
  }

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (step < 5) {
      goNext();
      return;
    }
    if (!declarationAccepted) {
      setStepError("Confirma la declaración de buena fe antes de registrar el aporte.");
      return;
    }

    setPending(true);
    setError("");
    setStepError("");
    keyRef.current ??= globalThis.crypto.randomUUID();
    const supabase = createClient();
    const payloadItems = kind === "in_kind" ? items.map((item) => ({ ...item, quantity: Number(item.quantity), declared_estimated_value_cop: item.declared_estimated_value_cop ? Number(item.declared_estimated_value_cop) : null, expires_on: null })) : [];
    const { data, error: submitError } = await supabase.rpc("submit_donation_intake", {
      p_event_id: DEMO_EVENT_ID,
      p_organization_id: organizationId,
      p_kind: kind,
      p_idempotency_key: keyRef.current,
      p_donor_name_private: donor.legalName.trim(),
      p_contact_private: { email: donor.email.trim(), phone: donor.phone.trim() },
      p_attribution_kind: donor.attributionKind,
      p_public_attribution: donor.attributionKind === "organization" ? organizationName : donor.attributionKind === "anonymous" ? "" : donor.publicAttribution.trim(),
      p_attribution_authorized: donor.attributionKind === "authorized_name" && donor.attributionAuthorized,
      p_declared_status: declaredStatus,
      p_items: payloadItems,
      p_declared_amount: kind === "money" ? Number(declaredAmount) : null,
      p_preferred_location_id: kind === "in_kind" ? preferredLocationId : null,
      p_reporting_context: {
        donor_type: reporting.donorType,
        economic_sector: reporting.economicSector,
        specific_destination: reporting.specificDestination,
        destination_note: reporting.destinationNote,
        destination_department: reporting.destinationDepartment,
        destination_municipality: reporting.destinationMunicipality,
        estimated_beneficiaries: reporting.estimatedBeneficiaries,
        delivery_channel: reporting.deliveryChannel,
        internal_responsible: reporting.internalResponsible,
        internal_contact: reporting.internalContact ? { value: reporting.internalContact } : {},
        observations: reporting.observations,
      },
    });
    setPending(false);
    if (submitError) {
      setError(toOperationalMessage(submitError, "No pudimos guardar el aporte. Tus datos siguen en pantalla; revisa la información e inténtalo de nuevo."));
      return;
    }
    const row = Array.isArray(data) ? data[0] : data;
    setTrackingCode(String(row?.tracking_code ?? ""));
  }

  if (trackingCode) {
    const trackingUrl = `${window.location.origin}/seguimiento?codigo=${encodeURIComponent(trackingCode)}`;
    return (
      <article className="donation-ticket">
        <div className="ticket-celebration"><CheckCircle2 size={44} /><span aria-hidden="true">♡</span></div>
        <p className="eyebrow">Registro recibido</p>
        <h2>Tu aporte ya tiene una ruta segura.</h2>
        <p>Gracias por dar el primer paso. Ahora la organización verificará la información antes de contarla como recepción o impacto.</p>
        <div className="ticket-grid">
          <div className="ticket-summary">
            <span>Resumen</span>
            <strong>{kind === "money" ? `$${Number(declaredAmount).toLocaleString("es-CO")} COP declarados` : `${items.length} ${items.length === 1 ? "artículo" : "artículos"} por verificar`}</strong>
            {selectedCenter && <small><MapPin size={13} /> {selectedCenter.name} · {selectedCenter.locationLabel}</small>}
            <div className="ticket-code"><span>Código de seguimiento</span><strong>{trackingCode}</strong></div>
          </div>
          <div className="ticket-qr">
            <QRCodeSVG value={trackingUrl} size={158} level="M" title="Código QR para consultar el seguimiento" />
            <span>Escanea para consultar el estado</span>
          </div>
        </div>
        <div className="ticket-actions">
          <Link className="button button-dark" href={`/seguimiento?codigo=${trackingCode}`}>Seguir mi aporte <ChevronRight size={16} /></Link>
          <button className="button button-outline" type="button" onClick={() => globalThis.print()}><Printer size={16} /> Guardar comprobante</button>
        </div>
        <p className="ticket-legal">Esta constancia confirma el reporte, no la recepción, conciliación, entrega ni beneficio.</p>
      </article>
    );
  }

  return (
    <form className="form-card donation-flow" onSubmit={handleSubmit}>
      <div className="form-card-header donation-flow-head">
        <div><p>Paso {step} de 5</p><h2>{STEP_LABELS[step - 1]}</h2></div>
        <span>{organizationName}</span>
      </div>
      <ol className="donation-stepper" aria-label="Progreso del registro">
        {STEP_LABELS.map((label, index) => {
          const number = index + 1;
          return <li className={number < step ? "is-complete" : number === step ? "is-current" : ""} aria-current={number === step ? "step" : undefined} key={label}><span>{number < step ? <Check size={14} /> : number}</span><small>{label}</small></li>;
        })}
      </ol>

      <div className="form-body donation-step-body">
        {error && <p className="form-error" role="alert" aria-live="assertive">{error}</p>}
        {stepError && <p className="form-error" role="alert" aria-live="assertive">{stepError}</p>}

        {step === 1 && (
          <section aria-labelledby="donation-step-title-1">
            <h3 id="donation-step-title-1">¿Qué quieres aportar?</h3>
            <p className="step-help">Primero elige el tipo de ayuda. Nada se publicará hasta que sea verificado.</p>
            <div className="donation-kind-grid">
              <button className={kind === "in_kind" ? "is-selected" : ""} type="button" aria-pressed={kind === "in_kind"} onClick={() => { setKind("in_kind"); setStepError(""); }}><PackageCheck size={25} /><strong>Bienes en especie</strong><span>Agua, alimentos, higiene y otros artículos.</span></button>
              <button className={kind === "money" ? "is-selected" : ""} type="button" aria-pressed={kind === "money"} onClick={() => { setKind("money"); setStepError(""); }}><Banknote size={25} /><strong>Aporte económico</strong><span>Solo registro; este canal no procesa pagos.</span></button>
            </div>
            {kind === "in_kind" && <><h3 className="substep-title">Elige una categoría</h3><div className="category-choice-grid">{NEED_CATEGORIES.map((category) => <button className={items[0]?.category === category ? "is-selected" : ""} type="button" aria-pressed={items[0]?.category === category} onClick={() => selectCategory(category)} key={category}><CategoryIcon category={category} size={23} /><span>{category}</span></button>)}</div></>}
          </section>
        )}

        {step === 2 && (
          <section aria-labelledby="donation-step-title-2">
            <h3 id="donation-step-title-2">Cuéntanos cuánto y en qué estado</h3>
            <p className="step-help">Estos datos permiten preparar la recepción y evitar traslados innecesarios.</p>
            {kind === "in_kind" ? <>
              {items.map((item, index) => (
                <div className="item-editor" key={index}>
                  <div className="item-editor-top"><strong>Artículo {index + 1} · {item.category || "Sin categoría"}</strong>{items.length > 1 && <button className="text-button" type="button" onClick={() => setItems((current) => current.filter((_, itemIndex) => itemIndex !== index))}><Trash2 size={13} /> Quitar</button>}</div>
                  <div className="field"><label htmlFor={`description-${index}`}>¿Qué es? <span aria-hidden="true">*</span></label><input id={`description-${index}`} value={item.description} onChange={(event) => updateItem(index, "description", event.target.value)} placeholder="Ej. botellas de agua selladas de 1 litro" minLength={3} maxLength={500} required /></div>
                  <div className="field-grid"><div className="field"><label htmlFor={`quantity-${index}`}>Cantidad <span aria-hidden="true">*</span></label><input id={`quantity-${index}`} type="number" min="0.001" step="0.001" value={item.quantity} onChange={(event) => updateItem(index, "quantity", event.target.value)} required /></div><div className="field"><label htmlFor={`unit-${index}`}>Unidad <span aria-hidden="true">*</span></label><select id={`unit-${index}`} value={item.unit} onChange={(event) => updateItem(index, "unit", event.target.value)} required><option value="" disabled>Selecciona</option>{NORMALIZED_UNITS.map((value) => <option value={value} key={value}>{value}</option>)}</select></div></div>
                  <div className="field"><label htmlFor={`estimated-value-${index}`}>Valor estimado del artículo (COP, opcional)</label><input id={`estimated-value-${index}`} type="number" min="1" step="1" value={item.declared_estimated_value_cop} onChange={(event) => updateItem(index, "declared_estimated_value_cop", event.target.value)} placeholder="Ej. 250000" /><small>Es una referencia declarada: no crea un ingreso financiero ni una cifra pública.</small></div>
                  <div className="field-grid"><div className="field"><label htmlFor={`condition-${index}`}>Estado</label><select id={`condition-${index}`} value={item.condition} onChange={(event) => updateItem(index, "condition", event.target.value)}><option value="sellado">Sellado</option><option value="nuevo">Nuevo</option><option value="abierto">Abierto (no se recibe)</option><option value="vencido">Vencido (no se recibe)</option></select></div><div className="field"><label htmlFor={`storage-${index}`}>Cuidado especial</label><select id={`storage-${index}`} value={item.storage_requirement} onChange={(event) => updateItem(index, "storage_requirement", event.target.value)}><option value="ambiente">Ambiente</option><option value="frio">Cadena de frío</option><option value="seco">Lugar seco</option></select></div></div>
                </div>
              ))}
              {items.length < 5 && <button className="button button-outline button-small" type="button" onClick={() => setItems((current) => [...current, blankItem(current[0]?.category)])}><Plus size={15} /> Agregar otro artículo</button>}
            </> : <div className="form-notice"><strong>Este canal no recauda dinero.</strong> Solo registra un aporte administrado por fuera de la plataforma para que tesorería verifique su soporte.<div className="field"><label htmlFor="declared-amount">Monto declarado (COP) <span aria-hidden="true">*</span></label><input id="declared-amount" type="number" min="1" step="1" value={declaredAmount} onChange={(event) => setDeclaredAmount(event.target.value)} placeholder="Ej. 150000" required /></div></div>}
          </section>
        )}

        {step === 3 && (
          <section aria-labelledby="donation-step-title-3">
            <h3 id="donation-step-title-3">Destino y entrega</h3>
            <p className="step-help">Diferenciamos el centro de recepción de la destinación final. Ninguno de estos datos acredita entrega o beneficio.</p>
            {kind === "in_kind" ? <><h4 className="form-subheading">Centro preferido</h4><div className="donation-center-options">{centers.map((center) => <button className={preferredLocationId === center.id ? "is-selected" : ""} type="button" aria-pressed={preferredLocationId === center.id} onClick={() => { setPreferredLocationId(center.id); setStepError(""); }} key={center.id}><span className="center-map-icon"><MapPin size={20} /></span><span><strong>{center.name}</strong><small>{center.locationLabel}</small><em>{center.accepts.length ? `Recibe ${center.accepts.join(", ")}` : "Recepción por coordinar"}</em></span>{preferredLocationId === center.id && <CheckCircle2 size={20} />}</button>)}</div></> : <div className="simple-confirmation"><HeartHandshake size={30} /><strong>La verificación económica será remota</strong><span>Tesorería revisará el soporte fuera de esta plataforma. Nunca ingreses tarjetas, claves o cuentas.</span></div>}
            <div className="destination-context">
              <label className="form-check"><input type="checkbox" checked={reporting.specificDestination} onChange={(event) => setReporting({ ...reporting, specificDestination: event.target.checked })} /><span><strong>Este aporte tiene una destinación específica</strong><small>Actívalo solo si ya existe una zona prevista.</small></span></label>
              {reporting.specificDestination && <><div className="field"><label htmlFor="destination-note">Detalle de la destinación (privado)</label><input id="destination-note" value={reporting.destinationNote} onChange={(event) => setReporting({ ...reporting, destinationNote: event.target.value })} maxLength={240} placeholder="Ej. punto comunitario del barrio" /></div><div className="field-grid"><div className="field"><label htmlFor="destination-department">Departamento destino</label><select id="destination-department" value={reporting.destinationDepartment} onChange={(event) => setReporting({ ...reporting, destinationDepartment: event.target.value })}><option value="" disabled>Selecciona</option>{COLOMBIA_DEPARTMENTS.map((department) => <option value={department} key={department}>{department}</option>)}</select></div><div className="field"><label htmlFor="destination-municipality">Municipio o zona destino</label><input id="destination-municipality" value={reporting.destinationMunicipality} onChange={(event) => setReporting({ ...reporting, destinationMunicipality: event.target.value })} maxLength={140} /></div></div></>}
              <div className="field-grid"><div className="field"><label htmlFor="estimated-beneficiaries">Beneficiarios estimados (opcional)</label><input id="estimated-beneficiaries" type="number" min="1" step="1" value={reporting.estimatedBeneficiaries} onChange={(event) => setReporting({ ...reporting, estimatedBeneficiaries: event.target.value })} /><small>Estimación declarada; nunca se publica como impacto sin validación.</small></div><div className="field"><label htmlFor="delivery-channel">Canal u operador previsto (opcional)</label><input id="delivery-channel" value={reporting.deliveryChannel} onChange={(event) => setReporting({ ...reporting, deliveryChannel: event.target.value })} maxLength={160} placeholder="Ej. transporte de un aliado" /></div></div>
              <div className="field"><label htmlFor="declared-status">Estado declarado del aporte <span aria-hidden="true">*</span></label><select id="declared-status" value={declaredStatus} onChange={(event) => setDeclaredStatus(event.target.value)} required><option value="comprometida">Comprometido</option><option value="en_transito">En tránsito hacia recepción</option><option value="entregada_por_validar">Entregado, pendiente de validar</option></select><small>Es una declaración inicial; el estado operativo cambia solo con evidencia.</small></div>
            </div>
          </section>
        )}

        {step === 4 && (
          <section aria-labelledby="donation-step-title-4">
            <h3 id="donation-step-title-4">¿Cómo podemos coordinar contigo?</h3>
            <p className="step-help">La organización reportante se obtiene de tu membresía; no se elige de una lista. Los contactos permanecen privados.</p>
            <p className="form-success organization-derived"><BadgeCheck size={16} /> Reportas como <strong>{organizationName}</strong></p>
            <div className="field-grid"><div className="field"><label htmlFor="donor-type">Tipo de donante (opcional)</label><select id="donor-type" value={reporting.donorType} onChange={(event) => setReporting({ ...reporting, donorType: event.target.value })}><option value="">Sin especificar</option>{DONOR_TYPES.map(([value,label]) => <option value={value} key={value}>{label}</option>)}</select></div><div className="field"><label htmlFor="economic-sector">Sector económico (opcional)</label><select id="economic-sector" value={reporting.economicSector} onChange={(event) => setReporting({ ...reporting, economicSector: event.target.value })}><option value="">Sin especificar</option>{ECONOMIC_SECTORS.map((sector) => <option value={sector} key={sector}>{sector}</option>)}</select></div></div>
            <div className="field-grid"><div className="field"><label htmlFor="donor-name">Nombre del donante (empresa o persona) <span aria-hidden="true">*</span></label><input id="donor-name" value={donor.legalName} onChange={(event) => setDonor({ ...donor, legalName: event.target.value })} autoComplete="organization" minLength={2} maxLength={160} required /><small>Se usa para control interno; no se publica por defecto.</small></div><div className="field"><label htmlFor="donor-email">Correo de coordinación <span aria-hidden="true">*</span></label><input id="donor-email" type="email" value={donor.email} onChange={(event) => setDonor({ ...donor, email: event.target.value })} autoComplete="email" maxLength={254} required /></div></div>
            <div className="field"><label htmlFor="donor-phone">Teléfono (opcional)</label><input id="donor-phone" type="tel" value={donor.phone} onChange={(event) => setDonor({ ...donor, phone: event.target.value })} autoComplete="tel" minLength={7} maxLength={30} /></div>
            <div className="field-grid"><div className="field"><label htmlFor="internal-responsible">Responsable que registra (opcional y privado)</label><input id="internal-responsible" value={reporting.internalResponsible} onChange={(event) => setReporting({ ...reporting, internalResponsible: event.target.value })} maxLength={160} /><small>Úsalo si quien diligencia no es el donante.</small></div><div className="field"><label htmlFor="internal-contact">Contacto interno (opcional y privado)</label><input id="internal-contact" value={reporting.internalContact} onChange={(event) => setReporting({ ...reporting, internalContact: event.target.value })} maxLength={180} placeholder="Correo o teléfono" /></div></div>
            <div className="field"><label htmlFor="private-observations">Observaciones internas (opcional)</label><textarea id="private-observations" value={reporting.observations} onChange={(event) => setReporting({ ...reporting, observations: event.target.value })} maxLength={2000} placeholder="Condiciones de coordinación que no deben publicarse" /></div>
            <div className="field"><label htmlFor="attribution-kind">¿Cómo quieres aparecer públicamente?</label><select id="attribution-kind" value={donor.attributionKind} onChange={(event) => setDonor({ ...donor, attributionKind: event.target.value })}><option value="anonymous">De forma anónima</option><option value="organization">Como organización</option><option value="alias">Con un alias</option><option value="authorized_name">Con mi nombre autorizado</option></select></div>
            {donor.attributionKind === "organization" && <p className="form-success organization-derived"><BadgeCheck size={16} /> La atribución pública será <strong>{organizationName}</strong>.</p>}
            {["alias", "authorized_name"].includes(donor.attributionKind) && <div className="field"><label htmlFor="public-attribution">Nombre o alias público <span aria-hidden="true">*</span></label><input id="public-attribution" value={donor.publicAttribution} onChange={(event) => setDonor({ ...donor, publicAttribution: event.target.value })} minLength={2} maxLength={120} required /></div>}
            {donor.attributionKind === "authorized_name" && <label className="form-check"><input type="checkbox" checked={donor.attributionAuthorized} onChange={(event) => setDonor({ ...donor, attributionAuthorized: event.target.checked })} /><span>Cuento con autorización expresa para publicar este nombre.</span></label>}
          </section>
        )}

        {step === 5 && (
          <section aria-labelledby="donation-step-title-5">
            <h3 id="donation-step-title-5">Revisa antes de confirmar</h3>
            <p className="step-help">Todavía puedes volver y corregir cualquier dato.</p>
            <dl className="donation-review">
              <div><dt>Tipo de aporte</dt><dd>{kind === "in_kind" ? "Bienes en especie" : "Aporte económico externo"}</dd></div>
              <div><dt>Detalle</dt><dd>{kind === "in_kind" ? items.map((item) => `${item.quantity} ${item.unit} de ${item.description}`).join(" · ") : `$${Number(declaredAmount).toLocaleString("es-CO")} COP declarados`}</dd></div>
              {kind === "in_kind" && <div><dt>Centro preferido</dt><dd>{selectedCenter ? `${selectedCenter.name} · ${selectedCenter.locationLabel}` : "Sin selección"}</dd></div>}
              <div><dt>Destino declarado</dt><dd>{reporting.specificDestination ? `${reporting.destinationDepartment} · ${reporting.destinationMunicipality}${reporting.estimatedBeneficiaries ? ` · ${reporting.estimatedBeneficiaries} beneficiarios estimados` : ""}` : "Sin destinación específica"}</dd></div>
              <div><dt>Perfil del donante</dt><dd>{reporting.donorType ? `${DONOR_TYPES.find(([value]) => value === reporting.donorType)?.[1] ?? reporting.donorType}${reporting.economicSector ? ` · ${reporting.economicSector}` : ""}` : "Sin especificar"}</dd></div>
              <div><dt>Estado declarado</dt><dd>{declaredStatus === "comprometida" ? "Comprometido" : declaredStatus === "en_transito" ? "En tránsito hacia recepción" : "Entregado, pendiente de validar"}</dd></div>
              <div><dt>Identidad y contacto privados</dt><dd>{donor.legalName} · {donor.email}</dd></div>
              <div><dt>Atribución pública</dt><dd>{donor.attributionKind === "anonymous" ? "Anónima" : donor.attributionKind === "organization" ? organizationName : donor.publicAttribution}</dd></div>
            </dl>
            <div className="visibility-review" aria-label="Visibilidad de los datos">
              <article><strong>Se podrá publicar tras verificar</strong><ul><li>Atribución autorizada o anónima</li><li>Tipo de aporte y categoría</li><li>Cantidad recibida o monto conciliado</li><li>Destino aproximado, estado y evidencia</li></ul></article>
              <article><strong>Permanece privado</strong><ul><li>Nombre legal, correo y teléfono</li><li>Descripción y valores declarados sin conciliar</li><li>Destino detallado y beneficiarios estimados</li><li>Responsables, canal y observaciones internas</li></ul></article>
            </div>
            <label className="form-check declaration-check"><input type="checkbox" checked={declarationAccepted} onChange={(event) => { setDeclarationAccepted(event.target.checked); setStepError(""); }} /><span>Declaro que la información es de buena fe y entiendo que esta constancia todavía no acredita recepción, entrega ni beneficio.</span></label>
          </section>
        )}

        <div className="donation-navigation">
          {step > 1 ? <button className="button button-ghost" type="button" onClick={() => { setStepError(""); setStep((current) => current - 1); }}><ChevronLeft size={16} /> Volver</button> : <span />}
          {step < 5 ? <button className="button button-dark" type="button" onClick={goNext}>Continuar <ChevronRight size={16} /></button> : <button className="button button-dark" type="submit" disabled={pending}>{pending ? <><LoaderCircle className="spin" size={17} /> Guardando…</> : <>Confirmar aporte <CheckCircle2 size={16} /></>}</button>}
        </div>
      </div>
    </form>
  );
}
