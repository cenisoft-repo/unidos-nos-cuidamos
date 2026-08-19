"use client";

import { useRef, useState } from "react";
import Link from "next/link";
import {
  Banknote,
  BadgeCheck,
  Camera,
  Check,
  CheckCircle2,
  ChevronDown,
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
import { EVENT_ID } from "@/lib/constants";
import type { DonationCategoryOption, DonationFlowCatalogs } from "@/lib/donation-catalogs";
import type { PublicCollectionCenter } from "@/lib/public-types";
import { sha256Hex, validateIntakePhotos } from "@/lib/intake-photo-evidence";
import { CategoryIcon } from "./category-icon";

export type NeedHelpItem = {
  needItemId: string;
  category: string;
  description: string;
  unit: string;
  quantityRequested: number;
  quantityCommitted: number;
  quantityPending: number;
};

export type NeedHelpTarget = {
  needCaseId: string;
  trackingCode: string;
  summary: string;
  locationLabel: string;
  items: NeedHelpItem[];
};

type Item = {
  need_item_id?: string;
  category: string;
  category_code: string;
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
  reportingAlly: string;
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

// El aporte económico no pasa por un punto de entrega: su recorrido tiene un paso menos.
type StepId = "aporte" | "entrega" | "contacto" | "revisar";

const STEP_LABELS: Record<StepId, string> = {
  aporte: "Tu aporte",
  entrega: "Punto de entrega",
  contacto: "Contacto",
  revisar: "Revisar y enviar",
};
const blankItem = (category?: DonationCategoryOption): Item => ({
  category: category?.parentCategory ?? "",
  category_code: category?.value ?? "",
  description: "",
  quantity: "",
  unit: "",
  condition: "sellado",
  storage_requirement: "ambiente",
  declared_estimated_value_cop: "",
});

function OptionalBlock({
  label,
  hint,
  defaultOpen = false,
  children,
}: {
  label: string;
  hint?: string;
  defaultOpen?: boolean;
  children: React.ReactNode;
}) {
  const [open, setOpen] = useState(defaultOpen);
  return (
    <div className={open ? "optional-block is-open" : "optional-block"}>
      <button className="optional-block-toggle" type="button" aria-expanded={open} onClick={() => setOpen((current) => !current)}>
        <ChevronDown size={15} aria-hidden="true" />
        <span>{label}</span>
        {hint && <small>{hint}</small>}
      </button>
      {open && <div className="optional-block-body">{children}</div>}
    </div>
  );
}

export function DonationIntakeForm({
  organizationId,
  organizationName,
  centers,
  initialCenterId,
  catalogs,
  need,
}: {
  organizationId: string;
  organizationName: string;
  centers: PublicCollectionCenter[];
  initialCenterId?: string;
  catalogs: DonationFlowCatalogs;
  need?: NeedHelpTarget;
}) {
  const inKindCategories = catalogs.donationCategories.filter((category) => category.kind === "in_kind");
  const moneyCategory = catalogs.donationCategories.find((category) => category.kind === "money");
  const initialStatus = catalogs.declaredStatuses.find((status) => status.value === "comprometida")?.value
    ?? catalogs.declaredStatuses[0]?.value
    ?? "comprometida";
  // Llegar por AYUDAR precarga exactamente lo que le falta a la necesidad. El aliado puede
  // bajar la cantidad (aporte parcial) y agregar otros artículos en la misma operación.
  const needSeedItems: Item[] = (need?.items ?? [])
    .filter((needItem) => needItem.quantityPending > 0)
    .map((needItem) => {
      const catalogMatch = inKindCategories.find((category) => category.parentCategory === needItem.category);
      return {
        need_item_id: needItem.needItemId,
        category: needItem.category,
        category_code: catalogMatch?.value ?? "",
        description: needItem.description || needItem.category,
        quantity: String(needItem.quantityPending),
        unit: needItem.unit,
        condition: "sellado",
        storage_requirement: "ambiente",
        declared_estimated_value_cop: "",
      };
    });
  const [stepId, setStepId] = useState<StepId>("aporte");
  const [kind, setKind] = useState<"in_kind" | "money">("in_kind");
  const [items, setItems] = useState<Item[]>(needSeedItems.length ? needSeedItems : [blankItem()]);
  const [declaredAmount, setDeclaredAmount] = useState("");
  const [declaredStatus, setDeclaredStatus] = useState(initialStatus);
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
    reportingAlly: "",
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
  const [photos, setPhotos] = useState<File[]>([]);
  const [evidenceNotice, setEvidenceNotice] = useState("");
  const keyRef = useRef<string | null>(null);

  const flow: StepId[] = kind === "in_kind"
    ? ["aporte", "entrega", "contacto", "revisar"]
    : ["aporte", "contacto", "revisar"];
  const stepIndex = Math.max(0, flow.indexOf(stepId));
  const step = flow[stepIndex];
  const selectedCenter = centers.find((center) => center.id === preferredLocationId);
  const coverageDepartments = catalogs.coverageDepartments.filter((department) => catalogs.departments.includes(department));
  const otherDepartments = catalogs.departments.filter((department) => !coverageDepartments.includes(department));
  const reportingAllyLabel = catalogs.reportingAllies.find((ally) => ally.value === reporting.reportingAlly)?.label;
  const hasDestinationData = reporting.specificDestination
    || Boolean(reporting.estimatedBeneficiaries || reporting.deliveryChannel || reporting.destinationNote);
  const hasInternalData = Boolean(
    donor.phone || reporting.donorType || reporting.economicSector || reporting.reportingAlly
    || reporting.internalResponsible || reporting.internalContact || reporting.observations,
  );

  const pendingByNeedItem = new Map((need?.items ?? []).map((needItem) => [needItem.needItemId, needItem.quantityPending]));

  function categoryByCode(categoryCode: string) {
    return inKindCategories.find((category) => category.value === categoryCode);
  }

  function centerAcceptsItems(center: PublicCollectionCenter) {
    return items.every((item) => (
      (!item.category || center.accepts.includes(item.category))
      && (item.storage_requirement !== "frio" || center.coldChainCapable)
    ));
  }

  function updateItem(index: number, field: keyof Item, value: string) {
    setItems((current) => current.map((item, itemIndex) => itemIndex === index ? { ...item, [field]: value } : item));
  }

  function updateItemCategory(index: number, categoryCode: string) {
    const category = categoryByCode(categoryCode);
    if (!category?.parentCategory) return;
    const nextItems = items.map((item, itemIndex) => itemIndex === index
      ? { ...item, category: category.parentCategory ?? "", category_code: category.value }
      : item);
    setItems(nextItems);
    const currentCenter = centers.find((center) => center.id === preferredLocationId);
    if (!currentCenter || !nextItems.every((item) => !item.category || currentCenter.accepts.includes(item.category))) {
      const compatibleCenter = centers.find((center) => nextItems.every((item) => !item.category || center.accepts.includes(item.category)));
      setPreferredLocationId(compatibleCenter?.id ?? "");
    }
    setStepError("");
  }

  function selectCategory(category: DonationCategoryOption) {
    updateItemCategory(0, category.value);
    setStepError("");
  }

  function destinationMessage() {
    if (reporting.specificDestination && (!reporting.destinationDepartment || reporting.destinationMunicipality.trim().length < 2)) return "Completa el departamento y el municipio o zona de la destinación específica.";
    if (reporting.estimatedBeneficiaries && Number(reporting.estimatedBeneficiaries) <= 0) return "La estimación de beneficiarios debe ser mayor que cero.";
    return "";
  }

  function validationMessage(currentStep: StepId) {
    if (currentStep === "aporte" && kind === "money") {
      if (Number(declaredAmount) <= 0) return "Escribe un monto mayor que cero.";
      return destinationMessage();
    }
    if (currentStep === "aporte") {
      if (!items[0]?.category_code) return "Elige la categoría que mejor describe tu ayuda.";
      if (items.some((item) => !item.category_code)) return "Cada artículo necesita una categoría.";
      if (items.some((item) => item.description.trim().length < 3)) return "Describe cada artículo: al menos tres caracteres.";
      if (items.some((item) => Number(item.quantity) <= 0 || !item.unit)) return "Escribe la cantidad y la unidad de cada artículo.";
      if (items.some((item) => item.declared_estimated_value_cop && Number(item.declared_estimated_value_cop) <= 0)) return "El valor estimado debe ser mayor que cero o quedar vacío.";
      const overCommitted = items.find((item) => item.need_item_id && Number(item.quantity) > (pendingByNeedItem.get(item.need_item_id) ?? 0));
      if (overCommitted) return `A esa necesidad solo le faltan ${pendingByNeedItem.get(overCommitted.need_item_id ?? "") ?? 0} ${overCommitted.unit}.`;
      return "";
    }
    if (currentStep === "entrega") {
      if (!preferredLocationId) return "Selecciona el punto donde entregarás el aporte.";
      if (selectedCenter && !centerAcceptsItems(selectedCenter)) return "Ese punto no recibe alguna categoría o no tiene el cuidado que pediste.";
      return destinationMessage();
    }
    if (currentStep === "contacto") {
      if (donor.legalName.trim().length < 2) return "Escribe el nombre privado de la empresa o persona donante.";
      if (!/^\S+@\S+\.\S+$/.test(donor.email)) return "Escribe un correo válido para la coordinación privada.";
      const photoMessage = validateIntakePhotos(photos);
      if (photoMessage) return photoMessage;
      if (["alias", "authorized_name"].includes(donor.attributionKind) && donor.publicAttribution.trim().length < 2) return "Escribe cómo quieres que aparezca la atribución pública.";
      if (donor.attributionKind === "authorized_name" && !donor.attributionAuthorized) return "Confirma que cuentas con autorización para publicar ese nombre.";
      if (reporting.reportingAlly === "otro" && reporting.observations.trim().length < 3) return "Especifica el otro aliado en Observaciones internas.";
      return "";
    }
    return "";
  }

  function selectPhotos(fileList: FileList | null) {
    const selected = Array.from(fileList ?? []);
    const message = validateIntakePhotos(selected);
    if (message) {
      setPhotos([]);
      setStepError(message);
      return;
    }
    setPhotos(selected);
    setStepError("");
  }

  function goNext() {
    const message = validationMessage(step);
    if (message) {
      setStepError(message);
      return;
    }
    setStepError("");
    setStepId(flow[Math.min(flow.length - 1, stepIndex + 1)]);
  }

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (step !== "revisar") {
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
    const { data, error: submitError } = await supabase.rpc("submit_donation_intake_v2", {
      p_event_id: EVENT_ID,
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
        reporting_ally: reporting.reportingAlly,
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
      p_catalog_versions: catalogs.versions,
      p_declared_category_code: kind === "money" ? moneyCategory?.value ?? "" : null,
      p_need_case_id: kind === "in_kind" ? need?.needCaseId ?? null : null,
    });
    if (submitError) {
      setPending(false);
      setError(toOperationalMessage(submitError, "No pudimos guardar el aporte. Tus datos siguen en pantalla; revisa la información e inténtalo de nuevo."));
      return;
    }
    const row = Array.isArray(data) ? data[0] : data;
    const intakeId = String(row?.intake_id ?? "");
    const nextTrackingCode = String(row?.tracking_code ?? "");
    if (!intakeId || !nextTrackingCode) {
      setPending(false);
      setError("El aporte fue procesado, pero no recibimos su comprobante. No repitas el registro; contacta a administración.");
      return;
    }

    let uploadedPhotos = 0;
    for (const photo of photos) {
      try {
        const sha256 = await sha256Hex(photo);
        const { data: prepared, error: prepareError } = await supabase.rpc("prepare_intake_photo_evidence", {
          p_intake_id: intakeId,
          p_file_name_private: photo.name,
          p_mime_type: photo.type,
          p_size_bytes: photo.size,
          p_sha256: sha256,
        });
        if (prepareError) throw prepareError;
        const preparedRow = Array.isArray(prepared) ? prepared[0] : prepared;
        const evidenceId = String(preparedRow?.evidence_id ?? "");
        const storagePath = String(preparedRow?.storage_path ?? "");
        if (!evidenceId || !storagePath) throw new Error("No se pudo reservar la evidencia");

        const { error: uploadError } = await supabase.storage
          .from("evidence-private")
          .upload(storagePath, photo, { contentType: photo.type, upsert: false });
        if (uploadError) throw uploadError;

        const { error: confirmError } = await supabase.rpc("confirm_intake_photo_evidence", {
          p_evidence_id: evidenceId,
        });
        if (confirmError) throw confirmError;
        uploadedPhotos += 1;
      } catch {
        // El intake ya existe: se conserva su código para impedir un segundo registro.
      }
    }

    if (photos.length > 0 && uploadedPhotos === photos.length) {
      setEvidenceNotice(`${uploadedPhotos === 1 ? "La fotografía quedó vinculada" : `Las ${uploadedPhotos} fotografías quedaron vinculadas`} de forma privada y pendiente de revisión segura.`);
    } else if (photos.length > 0) {
      setEvidenceNotice(`El aporte quedó registrado, pero ${photos.length - uploadedPhotos} ${photos.length - uploadedPhotos === 1 ? "fotografía no terminó" : "fotografías no terminaron"} de cargar. No repitas el aporte; conserva este código y contacta a administración.`);
    }
    setPending(false);
    setTrackingCode(nextTrackingCode);
  }

  if (trackingCode) {
    const trackingUrl = `${window.location.origin}/seguimiento?codigo=${encodeURIComponent(trackingCode)}`;
    return (
      <article className="donation-ticket">
        <div className="ticket-celebration"><CheckCircle2 size={44} /><span aria-hidden="true">♡</span></div>
        <p className="eyebrow">Solicitud de verificación recibida</p>
        <h2>Tu aporte quedó reportado con un código.</h2>
        <p>El equipo debe revisar los datos y soportes. Todavía no se considera recibido, entregado ni publicado como impacto.</p>
        {evidenceNotice && <p className={evidenceNotice.includes("no terminó") ? "form-notice" : "form-success"} role="status">{evidenceNotice}</p>}
        <div className="ticket-grid">
          <div className="ticket-summary">
            <span>Resumen</span>
            <strong>{kind === "money" ? `$${Number(declaredAmount).toLocaleString("es-CO")} COP declarados` : `${items.length} ${items.length === 1 ? "artículo" : "artículos"} por verificar`}</strong>
            {selectedCenter && kind === "in_kind" && <small><MapPin size={13} /> {selectedCenter.name} · {selectedCenter.locationLabel}</small>}
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

  const destinationFields = (
    <>
      <label className="form-check"><input type="checkbox" checked={reporting.specificDestination} onChange={(event) => setReporting({ ...reporting, specificDestination: event.target.checked })} /><span><strong>Ya sé a qué zona irá este aporte</strong><small>Actívalo solo si la destinación está definida. No acredita entrega ni beneficio.</small></span></label>
      {reporting.specificDestination && <><div className="field"><label htmlFor="destination-note">Detalle de la destinación (privado)</label><input id="destination-note" value={reporting.destinationNote} onChange={(event) => setReporting({ ...reporting, destinationNote: event.target.value })} maxLength={240} placeholder="Ej. punto comunitario del barrio" /></div><div className="field-grid"><div className="field"><label htmlFor="destination-department">Departamento destino</label><select id="destination-department" value={reporting.destinationDepartment} onChange={(event) => setReporting({ ...reporting, destinationDepartment: event.target.value })}><option value="" disabled>Selecciona</option><optgroup label="Cobertura inicial">{coverageDepartments.map((department) => <option value={department} key={department}>{department}</option>)}</optgroup><optgroup label="Otros departamentos">{otherDepartments.map((department) => <option value={department} key={department}>{department}</option>)}</optgroup></select></div><div className="field"><label htmlFor="destination-municipality">Municipio o zona destino</label><input id="destination-municipality" value={reporting.destinationMunicipality} onChange={(event) => setReporting({ ...reporting, destinationMunicipality: event.target.value })} maxLength={140} /></div></div></>}
      <div className="field-grid"><div className="field"><label htmlFor="estimated-beneficiaries">Beneficiarios estimados</label><input id="estimated-beneficiaries" type="number" min="1" step="1" value={reporting.estimatedBeneficiaries} onChange={(event) => setReporting({ ...reporting, estimatedBeneficiaries: event.target.value })} /><small>Estimación declarada; nunca se publica como impacto sin validación.</small></div><div className="field"><label htmlFor="delivery-channel">Canal u operador previsto</label><input id="delivery-channel" value={reporting.deliveryChannel} onChange={(event) => setReporting({ ...reporting, deliveryChannel: event.target.value })} maxLength={160} placeholder="Ej. transporte de un aliado" /></div></div>
    </>
  );

  return (
    <form className="form-card donation-flow" onSubmit={handleSubmit}>
      <div className="form-card-header donation-flow-head">
        <div><p>Paso {stepIndex + 1} de {flow.length}</p><h2>{STEP_LABELS[step]}</h2></div>
        <span>{organizationName}</span>
      </div>
      <ol className="donation-stepper" style={{ gridTemplateColumns: `repeat(${flow.length}, 1fr)` }} aria-label="Progreso del registro">
        {flow.map((id, index) => (
          <li className={index < stepIndex ? "is-complete" : index === stepIndex ? "is-current" : ""} aria-current={index === stepIndex ? "step" : undefined} key={id}><span>{index < stepIndex ? <Check size={14} /> : index + 1}</span><small>{STEP_LABELS[id]}</small></li>
        ))}
      </ol>

      <div className="form-body donation-step-body">
        {step === "aporte" && (
          <section aria-labelledby="donation-step-title-aporte">
            <h3 id="donation-step-title-aporte">¿Qué vas a aportar?</h3>
            <p className="step-help">Elige el tipo de ayuda y cuéntanos qué es. Nada se publica hasta que el equipo lo verifique.</p>
            {need && (
              <div className="need-help-banner">
                <HeartHandshake size={22} aria-hidden="true" />
                <div>
                  <strong>Estás ayudando a la necesidad {need.trackingCode}</strong>
                  <span>{need.summary} · {need.locationLabel}</span>
                  <small>Puedes aportar una parte de lo que falta y agregar otros artículos en el mismo registro.</small>
                </div>
              </div>
            )}
            <div className="donation-kind-grid">
              <button className={kind === "in_kind" ? "is-selected" : ""} type="button" aria-pressed={kind === "in_kind"} onClick={() => { setKind("in_kind"); setStepError(""); }}><PackageCheck size={25} /><strong>Bienes en especie</strong><span>Agua, alimentos, higiene y otros artículos.</span></button>
              {/* Una necesidad puntual se cubre con bienes; el aporte económico no se registra contra ella. */}
              {!need && <button className={kind === "money" ? "is-selected" : ""} type="button" aria-pressed={kind === "money"} onClick={() => { setKind("money"); setStepError(""); }}><Banknote size={25} /><strong>Aporte económico</strong><span>Solo registro; este canal no procesa pagos.</span></button>}
            </div>

            {kind === "in_kind" ? <>
              {!need && <><h3 className="substep-title">Elige la categoría</h3>
              <div className="category-choice-grid">{inKindCategories.map((category) => <button className={items[0]?.category_code === category.value ? "is-selected" : ""} type="button" aria-pressed={items[0]?.category_code === category.value} onClick={() => selectCategory(category)} key={category.value}><CategoryIcon category={category.parentCategory ?? category.label} size={23} /><span>{category.label}</span></button>)}</div></>}
              {items[0]?.category_code && <>
                <h3 className="substep-title">Describe la ayuda</h3>
                {items.map((item, index) => (
                  <div className="item-editor" key={index}>
                    <div className="item-editor-top"><strong>Artículo {index + 1} · {categoryByCode(item.category_code)?.label ?? "Sin categoría"}</strong>{items.length > 1 && <button className="text-button" type="button" onClick={() => setItems((current) => current.filter((_, itemIndex) => itemIndex !== index))}><Trash2 size={13} /> Quitar</button>}</div>
                    {item.need_item_id && <p className="item-need-note"><HeartHandshake size={13} aria-hidden="true" /> Comprometido con {need?.trackingCode}: faltan {pendingByNeedItem.get(item.need_item_id) ?? 0} {item.unit}. La categoría y la unidad las fija la necesidad.</p>}
                    {/* La categoría del primer artículo se elige con las tarjetas de arriba; solo los adicionales necesitan su propio selector. */}
                    {items.length > 1 && !item.need_item_id && <div className="field"><label htmlFor={`category-${index}`}>Categoría <span aria-hidden="true">*</span></label><select id={`category-${index}`} value={item.category_code} onChange={(event) => updateItemCategory(index, event.target.value)} required><option value="" disabled>Selecciona</option>{inKindCategories.map((category) => <option value={category.value} key={category.value}>{category.label}</option>)}</select></div>}
                    <div className="field"><label htmlFor={`description-${index}`}>¿Qué es? <span aria-hidden="true">*</span></label><input id={`description-${index}`} value={item.description} onChange={(event) => updateItem(index, "description", event.target.value)} placeholder="Ej. botellas de agua selladas de 1 litro" minLength={3} maxLength={500} required /></div>
                    <div className="field-grid"><div className="field"><label htmlFor={`quantity-${index}`}>Cantidad <span aria-hidden="true">*</span></label><input id={`quantity-${index}`} type="number" min="0.001" step="0.001" max={item.need_item_id ? pendingByNeedItem.get(item.need_item_id) : undefined} value={item.quantity} onChange={(event) => updateItem(index, "quantity", event.target.value)} required /></div><div className="field"><label htmlFor={`unit-${index}`}>Unidad <span aria-hidden="true">*</span></label><select id={`unit-${index}`} value={item.unit} onChange={(event) => updateItem(index, "unit", event.target.value)} required disabled={Boolean(item.need_item_id)}><option value="" disabled>Selecciona</option>{catalogs.units.map((value) => <option value={value} key={value}>{value}</option>)}</select></div></div>
                    <OptionalBlock label="Estado, cuidado y valor estimado" hint="Por defecto: sellado, a temperatura ambiente" defaultOpen={Boolean(item.declared_estimated_value_cop) || item.condition !== "sellado" || item.storage_requirement !== "ambiente"}>
                      <div className="field-grid"><div className="field"><label htmlFor={`condition-${index}`}>Estado</label><select id={`condition-${index}`} value={item.condition} onChange={(event) => updateItem(index, "condition", event.target.value)}><option value="sellado">Sellado</option><option value="nuevo">Nuevo</option><option value="abierto">Abierto (no se recibe)</option><option value="vencido">Vencido (no se recibe)</option></select></div><div className="field"><label htmlFor={`storage-${index}`}>Cuidado especial</label><select id={`storage-${index}`} value={item.storage_requirement} onChange={(event) => updateItem(index, "storage_requirement", event.target.value)}><option value="ambiente">Ambiente</option><option value="frio">Cadena de frío</option><option value="seco">Lugar seco</option></select></div></div>
                      <div className="field"><label htmlFor={`estimated-value-${index}`}>Valor estimado del artículo (COP)</label><input id={`estimated-value-${index}`} type="number" min="1" step="1" value={item.declared_estimated_value_cop} onChange={(event) => updateItem(index, "declared_estimated_value_cop", event.target.value)} placeholder="Ej. 250000" /><small>Es una referencia declarada: no crea un ingreso financiero ni una cifra pública.</small></div>
                    </OptionalBlock>
                  </div>
                ))}
                {items.length < 5 && <button className="button button-outline button-small" type="button" onClick={() => setItems((current) => [...current, blankItem(categoryByCode(current[0]?.category_code ?? ""))])}><Plus size={15} /> Agregar otro artículo</button>}
              </>}
            </> : <>
              <div className="simple-confirmation"><HeartHandshake size={30} /><strong>Este canal no recauda dinero</strong><span>Registras un aporte que se gestiona por fuera de la plataforma para que tesorería verifique su soporte. Nunca escribas tarjetas, claves ni cuentas.</span></div>
              <div className="field"><label htmlFor="declared-amount">Monto declarado (COP) <span aria-hidden="true">*</span></label><input id="declared-amount" type="number" min="1" step="1" value={declaredAmount} onChange={(event) => setDeclaredAmount(event.target.value)} placeholder="Ej. 150000" required /></div>
            </>}

            <div className="field"><label htmlFor="declared-status">Situación actual del aporte <span aria-hidden="true">*</span></label><select id="declared-status" value={declaredStatus} onChange={(event) => setDeclaredStatus(event.target.value)} required>{catalogs.declaredStatuses.map((status) => <option value={status.value} key={status.value}>{status.label}</option>)}</select><small>“Entregada” sigue pendiente de validación; el estado operativo cambia solo con evidencia.</small></div>
            {kind === "money" && <OptionalBlock label="Destino previsto y alcance" hint="Opcional" defaultOpen={hasDestinationData}>{destinationFields}</OptionalBlock>}
          </section>
        )}

        {step === "entrega" && (
          <section aria-labelledby="donation-step-title-entrega">
            <h3 id="donation-step-title-entrega">¿Dónde lo entregas?</h3>
            <p className="step-help">Solo aparecen los puntos de tu organización que pueden recibir este aporte. El destino final se define después de la verificación.</p>
            {centers.length ? <div className="donation-center-options">{centers.map((center) => { const isCompatible = centerAcceptsItems(center); return <button className={preferredLocationId === center.id ? "is-selected" : ""} type="button" aria-pressed={preferredLocationId === center.id} disabled={!isCompatible} onClick={() => { setPreferredLocationId(center.id); setStepError(""); }} key={center.id}><span className="center-map-icon"><MapPin size={20} /></span><span><strong>{center.name}</strong><small>{center.locationLabel}</small><em>{isCompatible ? `Recibe ${center.accepts.join(", ")}${center.instructions ? ` · ${center.instructions}` : ""}` : "No compatible con este aporte"}</em></span>{preferredLocationId === center.id && <CheckCircle2 size={20} />}</button>; })}</div> : <div className="form-error" role="status">Tu organización aún no tiene un punto de entrega activo. Pide a la administración que lo configure antes de reportar bienes.</div>}
            <OptionalBlock label="Destino previsto y alcance" hint="Opcional" defaultOpen={hasDestinationData}>{destinationFields}</OptionalBlock>
          </section>
        )}

        {step === "contacto" && (
          <section aria-labelledby="donation-step-title-contacto">
            <h3 id="donation-step-title-contacto">¿Con quién coordinamos?</h3>
            <p className="step-help">Solo pedimos dos datos obligatorios. Todo lo que escribas aquí permanece privado y no se publica.</p>
            <p className="form-success organization-derived"><BadgeCheck size={16} /> Reportas como <strong>{organizationName}</strong></p>
            <div className="field-grid"><div className="field"><label htmlFor="donor-name">Nombre del donante (empresa o persona) <span aria-hidden="true">*</span></label><input id="donor-name" value={donor.legalName} onChange={(event) => setDonor({ ...donor, legalName: event.target.value })} autoComplete="organization" minLength={2} maxLength={160} required /><small>Se usa para control interno; no se publica por defecto.</small></div><div className="field"><label htmlFor="donor-email">Correo de coordinación <span aria-hidden="true">*</span></label><input id="donor-email" type="email" value={donor.email} onChange={(event) => setDonor({ ...donor, email: event.target.value })} autoComplete="email" maxLength={254} required /></div></div>
            <div className="field"><label htmlFor="intake-photo-evidence">Evidencia fotográfica (opcional y privada)</label><input id="intake-photo-evidence" type="file" accept="image/jpeg,image/png" multiple onChange={(event) => selectPhotos(event.currentTarget.files)} /><small><Camera size={13} /> Hasta 3 fotos JPG o PNG, máximo 5 MB cada una. Evita rostros, documentos y datos personales. Se vinculan al código APO, no se publican y no prueban por sí solas recepción o entrega.</small>{photos.length > 0 && <small>{photos.length} {photos.length === 1 ? "fotografía seleccionada" : "fotografías seleccionadas"}: {photos.map((photo) => photo.name).join(" · ")}</small>}</div>
            <div className="field"><label htmlFor="attribution-kind">¿Cómo quieres aparecer públicamente?</label><select id="attribution-kind" value={donor.attributionKind} onChange={(event) => setDonor({ ...donor, attributionKind: event.target.value })}><option value="anonymous">De forma anónima</option><option value="organization">Como organización</option><option value="alias">Con un alias</option><option value="authorized_name">Con mi nombre autorizado</option></select></div>
            {donor.attributionKind === "organization" && <p className="form-success organization-derived"><BadgeCheck size={16} /> La atribución pública será <strong>{organizationName}</strong>.</p>}
            {["alias", "authorized_name"].includes(donor.attributionKind) && <div className="field"><label htmlFor="public-attribution">Nombre o alias público <span aria-hidden="true">*</span></label><input id="public-attribution" value={donor.publicAttribution} onChange={(event) => setDonor({ ...donor, publicAttribution: event.target.value })} minLength={2} maxLength={120} required /></div>}
            {donor.attributionKind === "authorized_name" && <label className="form-check"><input type="checkbox" checked={donor.attributionAuthorized} onChange={(event) => setDonor({ ...donor, attributionAuthorized: event.target.checked })} /><span>Cuento con autorización expresa para publicar este nombre.</span></label>}
            <OptionalBlock label="Más datos internos" hint="Teléfono, perfil del donante, aliado y observaciones" defaultOpen={hasInternalData}>
              <div className="field"><label htmlFor="donor-phone">Teléfono</label><input id="donor-phone" type="tel" value={donor.phone} onChange={(event) => setDonor({ ...donor, phone: event.target.value })} autoComplete="tel" minLength={7} maxLength={30} /></div>
              <div className="field-grid"><div className="field"><label htmlFor="donor-type">Tipo de donante</label><select id="donor-type" value={reporting.donorType} onChange={(event) => setReporting({ ...reporting, donorType: event.target.value })}><option value="">Sin especificar</option>{catalogs.donorTypes.map((option) => <option value={option.value} key={option.value}>{option.label}</option>)}</select></div><div className="field"><label htmlFor="economic-sector">Sector económico</label><select id="economic-sector" value={reporting.economicSector} onChange={(event) => setReporting({ ...reporting, economicSector: event.target.value })}><option value="">Sin especificar</option>{catalogs.economicSectors.map((option) => <option value={option.value} key={option.value}>{option.label}</option>)}</select></div></div>
              <div className="field"><label htmlFor="reporting-ally">Aliado relacionado con el aporte</label><select id="reporting-ally" value={reporting.reportingAlly} onChange={(event) => setReporting({ ...reporting, reportingAlly: event.target.value })}><option value="">Sin aliado de referencia</option>{catalogs.reportingAllies.map((option) => <option value={option.value} key={option.value}>{option.label}</option>)}</select><small>Solo aparece en el resumen interno. No cambia la organización con la que reportas ni concede permisos.</small></div>
              <div className="field-grid"><div className="field"><label htmlFor="internal-responsible">Responsable que registra</label><input id="internal-responsible" value={reporting.internalResponsible} onChange={(event) => setReporting({ ...reporting, internalResponsible: event.target.value })} maxLength={160} /><small>Úsalo si quien diligencia no es el donante.</small></div><div className="field"><label htmlFor="internal-contact">Contacto interno</label><input id="internal-contact" value={reporting.internalContact} onChange={(event) => setReporting({ ...reporting, internalContact: event.target.value })} maxLength={180} placeholder="Correo o teléfono" /></div></div>
              <div className="field"><label htmlFor="private-observations">Observaciones internas</label><textarea id="private-observations" value={reporting.observations} onChange={(event) => setReporting({ ...reporting, observations: event.target.value })} maxLength={2000} placeholder="Condiciones de coordinación que no deben publicarse" /></div>
            </OptionalBlock>
          </section>
        )}

        {step === "revisar" && (
          <section aria-labelledby="donation-step-title-revisar">
            <h3 id="donation-step-title-revisar">Revisa la solicitud antes de enviarla</h3>
            <p className="step-help">Esta solicitud pide verificar un aporte. No es una solicitud de ayuda, un recibo ni una confirmación de entrega.</p>
            <div className="form-notice"><strong>¿Qué pasará al confirmar?</strong> Se generará un código APO para seguimiento y el equipo autorizado revisará la información. Solo después de los controles correspondientes podrá avanzar a recepción o conciliación.</div>
            <dl className="donation-review">
              <div><dt>Qué estás reportando</dt><dd>{kind === "in_kind" ? "Bienes en especie" : "Aporte económico gestionado fuera de la plataforma"}</dd></div>
              <div><dt>Ayuda ofrecida</dt><dd>{kind === "in_kind" ? items.map((item) => `${item.quantity} ${item.unit} de ${item.description} (${categoryByCode(item.category_code)?.label ?? item.category})`).join(" · ") : `$${Number(declaredAmount).toLocaleString("es-CO")} COP declarados`}</dd></div>
              {kind === "in_kind" && <div><dt>Dónde se recibiría</dt><dd>{selectedCenter ? `${selectedCenter.name} · ${selectedCenter.locationLabel}` : "Sin selección"}</dd></div>}
              <div><dt>Para dónde se prevé</dt><dd>{reporting.specificDestination ? `${reporting.destinationDepartment} · ${reporting.destinationMunicipality}${reporting.estimatedBeneficiaries ? ` · alcance estimado: ${reporting.estimatedBeneficiaries} personas` : ""}` : "Aún no tiene destinación específica"}</dd></div>
              <div><dt>Quién dona</dt><dd>{reporting.donorType ? `${catalogs.donorTypes.find((option) => option.value === reporting.donorType)?.label ?? reporting.donorType}${reporting.economicSector ? ` · ${catalogs.economicSectors.find((option) => option.value === reporting.economicSector)?.label ?? reporting.economicSector}` : ""}` : "Perfil sin especificar"}</dd></div>
              <div><dt>Aliado relacionado</dt><dd>{reportingAllyLabel ?? "Sin aliado de referencia"}</dd></div>
              <div><dt>Fotos privadas</dt><dd>{photos.length ? `${photos.length} ${photos.length === 1 ? "foto seleccionada" : "fotos seleccionadas"}; se cargarán después de crear el código` : "No se adjuntarán fotos"}</dd></div>
              <div><dt>Situación que declaras</dt><dd>{catalogs.declaredStatuses.find((status) => status.value === declaredStatus)?.label ?? declaredStatus}{declaredStatus === "entregada" ? " · el equipo todavía debe comprobarla" : ""}</dd></div>
              <div><dt>Contacto para coordinar</dt><dd>{donor.legalName} · {donor.email} · privado</dd></div>
              <div><dt>Cómo podría mostrarse</dt><dd>{donor.attributionKind === "anonymous" ? "Sin nombre (anónimo)" : donor.attributionKind === "organization" ? organizationName : donor.publicAttribution}</dd></div>
            </dl>
            <div className="visibility-review" aria-label="Visibilidad de los datos">
              <article><strong>Se podrá publicar tras verificar</strong><ul><li>Atribución autorizada o anónima</li><li>Tipo de aporte y categoría</li><li>Cantidad recibida o monto conciliado</li><li>Destino aproximado, estado y nivel de evidencia autorizado</li></ul></article>
              <article><strong>Permanece privado</strong><ul><li>Nombre legal, correo y teléfono</li><li>Descripción y valores declarados sin conciliar</li><li>Destino detallado y beneficiarios estimados</li><li>Aliado de referencia, fotografías y observaciones internas</li></ul></article>
            </div>
            <label className="form-check declaration-check"><input type="checkbox" checked={declarationAccepted} onChange={(event) => { setDeclarationAccepted(event.target.checked); setStepError(""); }} /><span>Declaro que la información es de buena fe y entiendo que esta constancia todavía no acredita recepción, entrega ni beneficio.</span></label>
          </section>
        )}

        {/* Los avisos viven junto al botón que los provoca para que no queden fuera de pantalla en móvil. */}
        {error && <p className="form-error step-feedback" role="alert" aria-live="assertive">{error}</p>}
        {stepError && <p className="form-error step-feedback" role="alert" aria-live="assertive">{stepError}</p>}

        <div className="donation-navigation">
          {stepIndex > 0 ? <button className="button button-ghost" type="button" onClick={() => { setStepError(""); setStepId(flow[stepIndex - 1]); }}><ChevronLeft size={16} /> Volver</button> : <span />}
          {step !== "revisar" ? <button className="button button-dark" type="button" onClick={goNext}>Continuar <ChevronRight size={16} /></button> : <button className="button button-dark" type="submit" disabled={pending}>{pending ? <><LoaderCircle className="spin" size={17} /> {photos.length ? "Guardando y cargando evidencia…" : "Guardando…"}</> : <>Confirmar aporte <CheckCircle2 size={16} /></>}</button>}
        </div>
      </div>
    </form>
  );
}
