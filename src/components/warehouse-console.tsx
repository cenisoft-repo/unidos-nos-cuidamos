"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { ArrowLeftRight, CloudOff, PackageCheck, Search, Send, ShieldAlert, Truck } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { toOperationalMessage } from "@/lib/user-errors";
import { enqueueOfflineReception, readOfflineReceptions, removeOfflineReception, type OfflineReception } from "@/lib/offline-queue";
import { StatusPill } from "./status-pill";
import { numberFormat } from "@/lib/format";
import { labelStatus } from "@/lib/constants";
import { transportFromForm, transportProblem, TRANSPORT_MODES } from "@/lib/shipment-transport";

type PromiseItem = { id: string; category: string; description: string; quantity_promised: number; quantity_received: number; quantity_rejected: number; unit: string; donations: { donor_tracking_code: string; status: string; organization_id: string } | null };
type Location = { id: string; name: string; organization_id: string; accepts_donations: boolean; dispatches_shipments: boolean; shares_availability: boolean };
/** Posición derivada del Kardex. `quantity_initial` ya no manda: manda lo disponible. */
type LotPosition = { lot_id: string; lot_code: string; category: string; unit: string; status: string; organization_id: string; location_id: string; quantity_physical: number; quantity_available: number; quantity_reserved: number; quantity_in_transit: number; quantity_delivered: number };
type NeedItem = { id: string; category: string; quantity_required: number; quantity_covered: number; unit: string; need_cases: { public_location_text: string; status: string } | null };
type Allocation = { id: string; quantity: number; status: string; organization_id: string; transfer_request_id: string | null; inventory_lots: { lot_code: string; category: string; unit: string } | null; need_items: { category: string; need_cases: { public_location_text: string } | null } | null };
type Shipment = { id: string; shipment_code: string; status: string; public_destination: string; origin_location_id: string | null; destination_location_id: string | null; transfer_request_id: string | null; transport_mode: string | null; transport_plate: string | null; shipment_items: { quantity: number }[] };
type Delivery = { id: string; status: string; quantity_delivered: number; quantity_damaged: number; quantity_missing: number; shipments: { shipment_code: string } | null };
/**
 * Una solicitud pide N productos, y cada línea dice cómo los pide: una cantidad exacta,
 * un lote completo o todo lo disponible. En los dos últimos la cantidad no viaja desde
 * aquí: la resuelve la base al autorizar, con los lotes bloqueados.
 */
type RequestMode = "exact_quantity" | "full_lot" | "all_available";
type TransferLine = { item_id: string; line_no: number; category: string; unit: string; request_mode: RequestMode; lot_id: string | null; lot_code: string | null; quantity_requested: number | null; quantity_authorized: number; quantity_available_now: number };
type TransferRequest = { request_id: string; request_code: string; status: string; origin_location_id: string; origin_name: string; providing_organization_id: string; providing_organization_name: string; destination_location_id: string; destination_name: string; requesting_organization_id: string; requesting_organization_name: string; justification: string; decision_note: string | null; requested_by: string; is_provider: boolean; is_requester: boolean; lines: TransferLine[] };
/** Lo que otra organización del evento publica a la red: agregado, sin lotes ni PII. */
type Availability = { location_id: string; location_name: string; location_label: string; organization_id: string; organization_name: string; category: string; unit: string; quantity_available: number; cold_chain_capable: boolean; is_own_organization: boolean };
type ShipmentLine = { shipment_id: string; shipment_code: string; shipment_status: string; origin_name: string | null; destination_label: string | null; shipment_item_id: string; category: string; unit: string; quantity_dispatched: number; quantity_received: number; quantity_damaged: number; quantity_missing: number; outcome: string };
type DraftLine = { key: string; category: string; unit: string; mode: RequestMode; quantity: string; lotId: string };

const REQUEST_MODE_LABELS: Record<RequestMode, string> = {
  exact_quantity: "Una cantidad",
  full_lot: "Un lote completo",
  all_available: "Todo lo disponible",
};

const MOVEMENT_LABELS: Record<string, string> = {
  preparing: "Preparando",
  dispatched: "Despachado",
  in_transit: "En movimiento",
  arrived: "Llegó",
  delivered: "Recibido",
  validated: "Validado",
  incident: "Con novedad",
};

function TransportFields() {
  return (
    <>
      <label><span>Tipo de transporte</span><select name="transport_mode" required defaultValue=""><option value="" disabled>Selecciona</option>{TRANSPORT_MODES.map((mode) => <option value={mode.value} key={mode.value}>{mode.label}</option>)}</select></label>
      <label><span>Empresa transportadora</span><input name="transport_company" maxLength={160} placeholder="Obligatoria si es transportadora" /></label>
      <label><span>Nombre de quien transporta</span><input name="transport_contact_name" maxLength={160} required /></label>
      <label><span>Identificación</span><input name="transport_contact_document" maxLength={40} required /></label>
      <label><span>Teléfono</span><input name="transport_contact_phone" maxLength={30} required /></label>
      <label><span>Vehículo</span><input name="transport_vehicle" maxLength={120} required /></label>
      <label><span>Placa</span><input name="transport_plate" maxLength={12} required /></label>
      <label><span>Responsable de la carga</span><input name="transport_responsible" maxLength={160} required /></label>
    </>
  );
}

export function WarehouseConsole({
  promiseItems,
  locations,
  lotPositions,
  needItems,
  allocations,
  shipments,
  deliveries,
  transferRequests,
  availability,
  shipmentLines,
  organizationIds,
  canValidate,
  userId,
}: {
  promiseItems: PromiseItem[];
  locations: Location[];
  lotPositions: LotPosition[];
  needItems: NeedItem[];
  allocations: Allocation[];
  shipments: Shipment[];
  deliveries: Delivery[];
  transferRequests: TransferRequest[];
  availability: Availability[];
  shipmentLines: ShipmentLine[];
  organizationIds: string[];
  canValidate: boolean;
  userId: string;
}) {
  const router = useRouter();
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [pending, setPending] = useState("");
  const [queued, setQueued] = useState(0);
  const [receptionQuery, setReceptionQuery] = useState("");
  const usableLots = lotPositions.filter((lot) => ["available", "reserved"].includes(lot.status) && lot.quantity_available > 0);
  const [selectedLotId, setSelectedLotId] = useState(() => usableLots[0]?.lot_id ?? "");
  /*
   * Puente entre «tengo este lote» y «lo mando a otra bodega». Antes no existía: si el
   * lote no cuadraba con ninguna necesidad, la única acción de la pantalla quedaba
   * deshabilitada y desde ahí no había camino hacia el traslado, que es la operación que
   * de verdad se quería hacer. Sembrar el formulario evita además reescribir a mano la
   * categoría y la unidad, que tienen que coincidir exactamente con las del lote.
   */
  const [requestOrigin, setRequestOrigin] = useState("");
  const [draftLines, setDraftLines] = useState<DraftLine[]>([]);

  function nuevaLinea(partial: Partial<DraftLine> = {}): DraftLine {
    return { key: crypto.randomUUID(), category: "", unit: "", mode: "exact_quantity", quantity: "", lotId: "", ...partial };
  }

  function moverLoteAOtraBodega() {
    if (!selectedLot) return;
    setRequestOrigin(selectedLot.location_id);
    setDraftLines([nuevaLinea({
      category: selectedLot.category,
      unit: selectedLot.unit,
      mode: "full_lot",
      lotId: selectedLot.lot_id,
    })]);
    document.getElementById("traslados")?.scrollIntoView({ behavior: "smooth", block: "start" });
  }
  const supabase = useMemo(() => createClient(), []);
  const normalizedQuery = receptionQuery.trim().toLocaleLowerCase("es");
  const visiblePromiseItems = promiseItems.filter((item) => !normalizedQuery || [
    item.category,
    item.description,
    item.donations?.donor_tracking_code ?? "",
  ].some((value) => value.toLocaleLowerCase("es").includes(normalizedQuery)));
  const selectedLot = lotPositions.find((lot) => lot.lot_id === selectedLotId);
  const compatibleNeedItems = selectedLot
    ? needItems.filter((need) => need.category === selectedLot.category && need.unit === selectedLot.unit && Number(need.quantity_covered) < Number(need.quantity_required))
    : [];
  const locationById = new Map(locations.map((location) => [location.id, location]));
  const preparingShipments = shipments.filter((shipment) => shipment.status === "preparing");
  const movingShipments = shipments.filter((shipment) => ["dispatched", "in_transit", "arrived", "incident"].includes(shipment.status));
  // Preparar y despachar es de quien provee; recibir, de quien recibe.
  const authorizedTransfers = transferRequests.filter((request) => request.status === "authorized" && request.is_provider);
  const openTransfers = transferRequests.filter((request) => request.status === "requested");
  const ownOrganizations = new Set(organizationIds);

  /*
   * De dónde se puede pedir. Dos fuentes que no se solapan: las bodegas propias que
   * despachan —que esta consola ya lee— y las de otras organizaciones del evento, que solo
   * aparecen a través de la proyección de disponibilidad. La tabla de puntos ajena no se
   * lee nunca: pedir no da acceso a la información del proveedor.
   */
  const originOptions = useMemo(() => {
    const propias = new Set(organizationIds);
    const options = new Map<string, { id: string; label: string; own: boolean }>();
    for (const location of locations) {
      if (location.dispatches_shipments && propias.has(location.organization_id)) {
        options.set(location.id, { id: location.id, label: `${location.name} · tu organización`, own: true });
      }
    }
    for (const row of availability) {
      if (options.has(row.location_id)) continue;
      options.set(row.location_id, { id: row.location_id, label: `${row.location_name} · ${row.organization_name}`, own: row.is_own_organization });
    }
    return Array.from(options.values());
  }, [locations, availability, organizationIds]);

  const originAvailability = availability.filter((row) => row.location_id === requestOrigin);
  const originLots = lotPositions.filter((lot) => lot.location_id === requestOrigin && ["available", "reserved"].includes(lot.status) && Number(lot.quantity_available) > 0);
  const originIsOwn = originOptions.find((option) => option.id === requestOrigin)?.own ?? false;
  const destinationOptions = locations.filter((location) => location.accepts_donations && ownOrganizations.has(location.organization_id) && location.id !== requestOrigin);
  const linesByShipment = new Map<string, ShipmentLine[]>();
  for (const line of shipmentLines) {
    linesByShipment.set(line.shipment_id, [...(linesByShipment.get(line.shipment_id) ?? []), line]);
  }

  /*
   * Solo la bodega de destino confirma lo que recibió. `locationById` únicamente contiene
   * puntos de las organizaciones de quien mira, así que una bodega de destino ausente
   * significa que es de la otra organización: quien despachó no registra su recepción.
   */
  function puedeRecibir(shipment: Shipment) {
    if (!shipment.destination_location_id) return true;
    return locationById.has(shipment.destination_location_id);
  }

  async function syncQueue() {
    const queue = readOfflineReceptions();
    setQueued(queue.length);
    for (const operation of queue) {
      const { error: syncError } = await supabase.rpc("receive_donation", { p_donation_item_id: operation.donationItemId, p_location_id: operation.locationId, p_accepted: operation.accepted, p_rejected: operation.rejected, p_condition: operation.condition, p_idempotency_key: operation.id });
      if (!syncError) removeOfflineReception(operation.id);
    }
    setQueued(readOfflineReceptions().length);
    router.refresh();
  }

  useEffect(() => {
    const initialQueueRead = window.setTimeout(() => setQueued(readOfflineReceptions().length), 0);
    const online = () => void syncQueue();
    window.addEventListener("online", online);
    return () => {
      window.clearTimeout(initialQueueRead);
      window.removeEventListener("online", online);
    };
    // The Supabase client and router are stable for the mounted console.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Las llamadas de Supabase devuelven un constructor «thenable», no una promesa nativa.
  async function run(key: string, success: string, action: () => PromiseLike<{ error: unknown }>) {
    setPending(key);
    setError("");
    setMessage("");
    const { error: actionError } = await action();
    setPending("");
    if (actionError) {
      setError(toOperationalMessage(actionError as Parameters<typeof toOperationalMessage>[0]));
      return false;
    }
    setMessage(success);
    router.refresh();
    return true;
  }

  async function receive(item: PromiseItem, form: HTMLFormElement) {
    const data = new FormData(form);
    const accepted = Number(data.get("accepted"));
    const rejected = Number(data.get("rejected"));
    const locationId = String(data.get("location"));
    const operation: OfflineReception = { id: crypto.randomUUID(), donationItemId: item.id, locationId, accepted, rejected, condition: "sellado", createdAt: new Date().toISOString() };
    if (!navigator.onLine) {
      setPending(item.id); setError(""); setMessage("");
      try {
        enqueueOfflineReception(operation);
        setQueued(readOfflineReceptions().length);
        setMessage("Recepción guardada en la cola local sin datos personales. Se sincronizará al recuperar conexión.");
      } catch {
        setError("La cola local está llena o el registro no es válido. Recupera conexión antes de continuar.");
      }
      setPending("");
      return;
    }
    await run(item.id, "Recepción conciliada y lote creado exactamente una vez.", () =>
      supabase.rpc("receive_donation", { p_donation_item_id: item.id, p_location_id: locationId, p_accepted: accepted, p_rejected: rejected, p_condition: "sellado", p_idempotency_key: operation.id }));
  }

  async function allocate(form: HTMLFormElement) {
    const data = new FormData(form);
    await run("allocate", "Existencia reservada.", () =>
      supabase.rpc("allocate_stock", { p_lot_id: String(data.get("lot")), p_need_item_id: String(data.get("need")), p_quantity: Number(data.get("quantity")), p_idempotency_key: crypto.randomUUID() }));
  }

  async function prepareNeedShipment(allocation: Allocation, form: HTMLFormElement) {
    const data = new FormData(form);
    const problem = transportProblem(transportFromForm(data));
    if (problem) { setError(problem); return; }
    await run(allocation.id, "Despacho en preparación con su transporte registrado.", () =>
      supabase.rpc("create_shipment", {
        p_allocation_id: allocation.id,
        p_transfer_request_id: null,
        p_origin_location_id: String(data.get("origin")),
        p_destination_location_id: null,
        p_public_destination: String(data.get("destination")).trim(),
        p_transport: transportFromForm(data),
        p_idempotency_key: crypto.randomUUID(),
      }));
  }

  async function prepareTransferShipment(request: TransferRequest, form: HTMLFormElement) {
    const data = new FormData(form);
    const problem = transportProblem(transportFromForm(data));
    if (problem) { setError(problem); return; }
    await run(request.request_id, "Salida en preparación con su transporte registrado.", () =>
      supabase.rpc("create_shipment", {
        p_allocation_id: null,
        p_transfer_request_id: request.request_id,
        p_origin_location_id: request.origin_location_id,
        p_destination_location_id: request.destination_location_id,
        p_public_destination: null,
        p_transport: transportFromForm(data),
        p_idempotency_key: crypto.randomUUID(),
      }));
  }

  /*
   * Lo que viaja es el modo, no una cantidad calculada aquí. En «un lote completo» y en
   * «todo lo disponible» la cantidad la resuelve la base al autorizar: lo que muestra esta
   * pantalla puede haber dejado de ser cierto antes de que alguien pulse el botón.
   */
  async function requestTransfer(form: HTMLFormElement) {
    const data = new FormData(form);
    const items = draftLines.map((line) => {
      if (line.mode === "full_lot") return { mode: "full_lot", lot_id: line.lotId };
      if (line.mode === "all_available") return { mode: "all_available", category: line.category, unit: line.unit };
      return { mode: "exact_quantity", category: line.category, unit: line.unit, quantity: Number(line.quantity) };
    });
    const incompleta = draftLines.some((line) =>
      (line.mode === "full_lot" && !line.lotId)
      || (line.mode !== "full_lot" && (!line.category || !line.unit))
      || (line.mode === "exact_quantity" && !(Number(line.quantity) > 0)));
    if (!items.length || incompleta) {
      setError("Cada producto necesita qué se pide y, si es una cantidad exacta, cuánto.");
      return;
    }
    const enviada = await run("transfer-request", "Solicitud registrada. Falta la autorización de la bodega de origen.", () =>
      supabase.rpc("request_stock_transfer", {
        p_origin_location_id: requestOrigin,
        p_destination_location_id: String(data.get("destination")),
        p_items: items,
        p_justification: String(data.get("justification")).trim(),
        p_need_case_id: null,
        p_need_item_id: null,
        p_idempotency_key: crypto.randomUUID(),
      }));
    if (enviada) setDraftLines([]);
  }

  /*
   * Autorización parcial: se envía una cantidad SOLO en las líneas cuyo valor cambió. Una
   * línea que el operador no tocó viaja sin cantidad para que la base resuelva la suya, en
   * vez de fijar aquí la cifra que se pintó hace un minuto.
   */
  async function decideTransfer(request: TransferRequest, decision: "authorize" | "reject", form: HTMLFormElement) {
    const data = new FormData(form);
    const overrides = decision === "authorize"
      ? request.lines.flatMap((line) => {
        const raw = data.get(`linea-${line.item_id}`);
        if (raw === null) return [];
        const value = Number(raw);
        if (!Number.isFinite(value) || value === defaultAuthorized(line)) return [];
        return [{ item_id: line.item_id, quantity: value }];
      })
      : [];
    await run(request.request_id, decision === "authorize" ? "Solicitud autorizada; lo autorizado quedó reservado." : "Solicitud rechazada.", () =>
      supabase.rpc("decide_stock_transfer", {
        p_request_id: request.request_id,
        p_decision: decision,
        p_lines: overrides.length ? overrides : null,
        p_note: String(data.get("note")).trim(),
      }));
  }

  /** Lo que se autoriza si nadie escribe nada: lo pedido, o lo que haya cuando no se pidió cifra. */
  function defaultAuthorized(line: TransferLine) {
    return line.request_mode === "exact_quantity"
      ? Number(line.quantity_requested ?? 0)
      : Number(line.quantity_available_now);
  }

  /*
   * Recibir producto a producto. El faltante no se escribe: se deduce de lo despachado
   * menos lo recibido y lo dañado, que es exactamente la conciliación que exige la base.
   */
  async function receiveShipment(shipment: Shipment, form: HTMLFormElement) {
    const data = new FormData(form);
    const lines = (linesByShipment.get(shipment.id) ?? []).map((line) => {
      const delivered = Number(data.get(`recibido-${line.shipment_item_id}`));
      const damaged = Number(data.get(`danado-${line.shipment_item_id}`));
      return {
        shipment_item_id: line.shipment_item_id,
        delivered,
        damaged,
        missing: Number((Number(line.quantity_dispatched) - delivered - damaged).toFixed(3)),
      };
    });
    if (lines.some((line) => !Number.isFinite(line.delivered) || !Number.isFinite(line.damaged) || line.missing < 0)) {
      setError("Lo recibido y lo dañado de cada producto no pueden superar lo despachado.");
      return;
    }
    await run(shipment.id, "Recepción conciliada producto a producto.", () =>
      supabase.rpc("register_delivery", {
        p_shipment_id: shipment.id,
        p_lines: lines,
        p_idempotency_key: crypto.randomUUID(),
      }));
  }

  return (
    <>
      <nav className="warehouse-steps" aria-label="Etapas de bodega y logística">
        <a href="#recepciones"><span>01</span> Recibir <strong>{promiseItems.length}</strong></a>
        <a href="#inventario"><span>02</span> Reservar <strong>{usableLots.length}</strong></a>
        <a href="#traslados"><span>03</span> Solicitar <strong>{openTransfers.length}</strong></a>
        <a href="#despachos"><span>04</span> Preparar <strong>{allocations.filter((allocation) => allocation.status === "reserved" && !allocation.transfer_request_id).length + authorizedTransfers.length}</strong></a>
        <a href="#movimiento"><span>05</span> Mover <strong>{movingShipments.length}</strong></a>
      </nav>

      {queued > 0 && (
        <div className="ops-alert">
          <CloudOff size={17} />
          <strong>{queued} operación(es) en cola local.</strong>
          <button className="action-button" onClick={() => void syncQueue()}>Sincronizar ahora</button>
        </div>
      )}
      {message && <p className="form-success" role="status">{message}</p>}
      {error && <p className="form-error" role="alert">{error}</p>}

      <div className="ops-grid">
        <section className="ops-panel" id="recepciones">
          <header className="ops-panel-header">
            <div><h2><PackageCheck size={18} /> Recepciones pendientes</h2><p>Busca el código del aporte y confirma cantidades.</p></div>
            <span>{visiblePromiseItems.length} de {promiseItems.length}</span>
          </header>
          <div className="warehouse-search">
            <Search size={16} aria-hidden="true" />
            <label htmlFor="reception-search">Buscar aporte, categoría o artículo</label>
            <input id="reception-search" value={receptionQuery} onChange={(event) => setReceptionQuery(event.target.value)} placeholder="Ej. DON-… o Agua" />
          </div>
          <div className="ops-list">
            {visiblePromiseItems.map((item) => {
              const remaining = Number(item.quantity_promised) - Number(item.quantity_received) - Number(item.quantity_rejected);
              // Solo los puntos habilitados como acopio pueden recibir custodia física.
              const validLocations = locations.filter((location) => location.organization_id === item.donations?.organization_id && location.accepts_donations);
              return (
                <article className="ops-row warehouse-reception" key={item.id}>
                  <div>
                    <h3>{item.category} · {item.donations?.donor_tracking_code}</h3>
                    <p>{item.description} · quedan {numberFormat.format(remaining)} {item.unit}</p>
                    <form className="inline-form" onSubmit={(event) => { event.preventDefault(); void receive(item, event.currentTarget); }}>
                      <label><span>Aceptada</span><input name="accepted" type="number" min="0" max={remaining} step="0.001" defaultValue={remaining} required /></label>
                      <label><span>Rechazada</span><input name="rejected" type="number" min="0" max={remaining} step="0.001" defaultValue="0" required /></label>
                      <label><span>Centro receptor</span><select name="location" required>{validLocations.map((location) => <option key={location.id} value={location.id}>{location.name}</option>)}</select></label>
                      <button className="action-button approve" disabled={pending === item.id || !validLocations.length}>Confirmar recepción</button>
                    </form>
                  </div>
                  <StatusPill status={item.donations?.status ?? "promised"} />
                </article>
              );
            })}
            {!visiblePromiseItems.length && <p className="ops-empty">No hay recepciones que coincidan con la búsqueda.</p>}
          </div>
        </section>

        <section className="ops-panel" id="inventario">
          <header className="ops-panel-header">
            <div><h2><ShieldAlert size={18} /> Reservar existencia</h2><p>Cada lote muestra su posición real: físico, disponible y reservado salen del Kardex.</p></div>
            <span>{compatibleNeedItems.length} compatibles</span>
          </header>
          <div className="lot-picker" role="group" aria-label="Seleccionar lote disponible">
            {usableLots.map((lot) => (
              <button key={lot.lot_id} type="button" aria-pressed={selectedLotId === lot.lot_id} onClick={() => setSelectedLotId(lot.lot_id)}>
                <strong>{lot.lot_code}</strong>
                <span>{lot.category}</span>
                <small>{numberFormat.format(lot.quantity_available)} de {numberFormat.format(lot.quantity_physical)} {lot.unit} disponibles</small>
              </button>
            ))}
            {!usableLots.length && <p className="ops-empty">No hay existencias disponibles para reservar.</p>}
          </div>
          {selectedLot && (
            <dl className="lot-position" aria-label={`Posición del lote ${selectedLot.lot_code}`}>
              <div><dt>Físico</dt><dd>{numberFormat.format(selectedLot.quantity_physical)} {selectedLot.unit}</dd></div>
              <div><dt>Disponible</dt><dd>{numberFormat.format(selectedLot.quantity_available)} {selectedLot.unit}</dd></div>
              <div><dt>Reservado</dt><dd>{numberFormat.format(selectedLot.quantity_reserved)} {selectedLot.unit}</dd></div>
              <div><dt>En movimiento</dt><dd>{numberFormat.format(selectedLot.quantity_in_transit)} {selectedLot.unit}</dd></div>
              <div><dt>Entregado</dt><dd>{numberFormat.format(selectedLot.quantity_delivered)} {selectedLot.unit}</dd></div>
            </dl>
          )}
          <form className="form-body" onSubmit={(event) => { event.preventDefault(); void allocate(event.currentTarget); }}>
            <input type="hidden" name="lot" value={selectedLotId} />
            <div className="field">
              <label htmlFor="need">Necesidad compatible</label>
              <select id="need" name="need" key={selectedLotId} required disabled={!compatibleNeedItems.length}>
                {compatibleNeedItems.map((need) => <option key={need.id} value={need.id}>{need.need_cases?.public_location_text} · faltan {numberFormat.format(Number(need.quantity_required) - Number(need.quantity_covered))} {need.unit}</option>)}
              </select>
              {!compatibleNeedItems.length && <small>Ninguna necesidad publicada pide {selectedLot?.category ?? "esta categoría"} en {selectedLot?.unit ?? "esta unidad"}.</small>}
            </div>
            <div className="field"><label htmlFor="allocation-quantity">Cantidad a reservar</label><input id="allocation-quantity" name="quantity" type="number" min="0.001" max={selectedLot?.quantity_available} step="0.001" required /><small>No puede superar lo disponible: {numberFormat.format(selectedLot?.quantity_available ?? 0)} {selectedLot?.unit}</small></div>
            <button className="button button-dark button-block" disabled={pending === "allocate" || !selectedLot || !compatibleNeedItems.length}>Reservar con control de concurrencia</button>
          </form>
          {/*
            Reservar contra una necesidad no es la única salida de un lote, y era la única
            que esta pantalla ofrecía. Lo que va a otra bodega se reserva al autorizar el
            traslado —quien pide no autoriza—, así que aquí se lleva a la operación
            correcta en vez de dejar un botón deshabilitado sin explicación ni salida.
          */}
          {selectedLot && !compatibleNeedItems.length && (
            <div className="lot-alternative">
              <p>
                Lo que va a otra bodega no se reserva aquí: se reserva cuando la
                administración autoriza el traslado, para que nadie mueva existencia sin un
                segundo par de ojos.
              </p>
              <button className="button button-outline button-small" type="button" onClick={moverLoteAOtraBodega}>
                <ArrowLeftRight size={15} /> Trasladar este lote a otra bodega
              </button>
            </div>
          )}
        </section>
      </div>

      <section className="ops-panel" id="traslados">
        <header className="ops-panel-header"><div><h2><ArrowLeftRight size={18} /> Solicitar producto</h2><p>Pide a una bodega tuya o a otra organización del evento. Quien provee autoriza, y autorizar reserva antes de que nada salga.</p></div><span>{openTransfers.length} por revisar</span></header>
        {/*
          Rejilla propia y no `inline-form`: aquella fija cuatro columnas para
          formularios de cuatro campos. Aquí además una solicitud lleva N productos, así
          que las líneas viven en su propia lista y no en la rejilla de la cabecera.
        */}
        <form className="transfer-form" onSubmit={(event) => { event.preventDefault(); void requestTransfer(event.currentTarget); }}>
          <label>
            <span>Pídele a</span>
            <select name="origin" required value={requestOrigin} onChange={(event) => { setRequestOrigin(event.target.value); setDraftLines([]); }}>
              <option value="" disabled>Selecciona la bodega que provee</option>
              {originOptions.map((option) => <option key={option.id} value={option.id}>{option.label}</option>)}
            </select>
          </label>
          <label>
            <span>Llega a</span>
            <select name="destination" required defaultValue="">
              <option value="" disabled>Selecciona tu bodega</option>
              {destinationOptions.map((location) => <option key={location.id} value={location.id}>{location.name}</option>)}
            </select>
          </label>
          <div className="transfer-form-wide request-lines">
            {draftLines.map((line, index) => (
              <fieldset className="request-line" key={line.key}>
                <legend>Producto {index + 1}</legend>
                {originAvailability.length ? (
                  <label>
                    <span>Qué necesitas</span>
                    <select
                      value={line.category ? `${line.category}|${line.unit}` : ""}
                      onChange={(event) => {
                        const [category, unit] = event.target.value.split("|");
                        setDraftLines((lines) => lines.map((current) => current.key === line.key ? { ...current, category, unit, lotId: "" } : current));
                      }}
                      required
                    >
                      <option value="" disabled>Selecciona</option>
                      {originAvailability.map((row) => (
                        <option key={`${row.category}|${row.unit}`} value={`${row.category}|${row.unit}`}>
                          {row.category} · {numberFormat.format(row.quantity_available)} {row.unit} disponibles
                        </option>
                      ))}
                    </select>
                  </label>
                ) : (
                  <>
                    <label><span>Categoría</span><input value={line.category} maxLength={80} required placeholder="Ej. Agua" onChange={(event) => setDraftLines((lines) => lines.map((current) => current.key === line.key ? { ...current, category: event.target.value } : current))} /></label>
                    <label><span>Unidad</span><input value={line.unit} maxLength={40} required placeholder="Ej. litro" onChange={(event) => setDraftLines((lines) => lines.map((current) => current.key === line.key ? { ...current, unit: event.target.value } : current))} /></label>
                  </>
                )}
                <label>
                  <span>Cuánto</span>
                  <select value={line.mode} onChange={(event) => setDraftLines((lines) => lines.map((current) => current.key === line.key ? { ...current, mode: event.target.value as RequestMode, lotId: "" } : current))}>
                    <option value="exact_quantity">{REQUEST_MODE_LABELS.exact_quantity}</option>
                    <option value="all_available">{REQUEST_MODE_LABELS.all_available}</option>
                    {originIsOwn && <option value="full_lot">{REQUEST_MODE_LABELS.full_lot}</option>}
                  </select>
                </label>
                {line.mode === "exact_quantity" && (
                  <label><span>Cantidad</span><input type="number" min="0.001" step="0.001" required value={line.quantity} onChange={(event) => setDraftLines((lines) => lines.map((current) => current.key === line.key ? { ...current, quantity: event.target.value } : current))} /></label>
                )}
                {line.mode === "full_lot" && (
                  <label>
                    <span>Lote</span>
                    <select value={line.lotId} required onChange={(event) => {
                      const lot = originLots.find((candidate) => candidate.lot_id === event.target.value);
                      setDraftLines((lines) => lines.map((current) => current.key === line.key ? { ...current, lotId: event.target.value, category: lot?.category ?? current.category, unit: lot?.unit ?? current.unit } : current));
                    }}>
                      <option value="" disabled>Selecciona el lote</option>
                      {originLots.map((lot) => <option key={lot.lot_id} value={lot.lot_id}>{lot.lot_code} · {numberFormat.format(lot.quantity_available)} {lot.unit}</option>)}
                    </select>
                  </label>
                )}
                {line.mode !== "exact_quantity" && (
                  <p className="request-line-note">La cantidad la calcula la bodega al autorizar, con lo que haya en ese momento.</p>
                )}
                <button className="action-button request-line-remove" type="button" onClick={() => setDraftLines((lines) => lines.filter((current) => current.key !== line.key))}>Quitar</button>
              </fieldset>
            ))}
            <button className="button button-outline button-small" type="button" disabled={!requestOrigin} onClick={() => setDraftLines((lines) => [...lines, nuevaLinea()])}>
              Agregar producto
            </button>
            {!requestOrigin && <p className="request-line-note">Elige primero a qué bodega le pides.</p>}
          </div>
          <label className="transfer-form-wide"><span>Justificación</span><input name="justification" minLength={10} maxLength={500} required placeholder="Por qué se necesita en la bodega de destino" /></label>
          <button className="action-button approve transfer-form-submit" disabled={pending === "transfer-request" || !draftLines.length}>Enviar solicitud</button>
        </form>
        <div className="ops-list">
          {openTransfers.map((request) => (
            <article className="ops-row" key={request.request_id}>
              <div>
                <h3>{request.request_code} · {request.lines.length} {request.lines.length === 1 ? "producto" : "productos"}</h3>
                <p>{request.origin_name} ({request.providing_organization_name}) → {request.destination_name} ({request.requesting_organization_name}) · {request.justification}</p>
                <ul className="request-line-list">
                  {request.lines.map((line) => (
                    <li key={line.item_id}>
                      <strong>{line.category}</strong>{" "}
                      {line.request_mode === "exact_quantity"
                        ? `${numberFormat.format(Number(line.quantity_requested ?? 0))} ${line.unit}`
                        : `${REQUEST_MODE_LABELS[line.request_mode].toLocaleLowerCase("es")}${line.lot_code ? ` (${line.lot_code})` : ""}`}
                      {" · "}<small>hay {numberFormat.format(Number(line.quantity_available_now))} {line.unit}</small>
                    </li>
                  ))}
                </ul>
                {!request.is_provider ? (
                  <p className="ops-inline-warning">La autoriza la bodega de origen. Aquí verás su decisión.</p>
                ) : request.requested_by === userId ? (
                  <p className="ops-inline-warning">Tú registraste esta solicitud: la autoriza otra persona con alcance sobre la bodega de origen.</p>
                ) : (
                  <form className="inline-form" onSubmit={(event) => event.preventDefault()}>
                    {request.lines.map((line) => (
                      <label key={line.item_id}>
                        <span>Autorizar {line.category}</span>
                        <input
                          name={`linea-${line.item_id}`}
                          type="number"
                          min="0"
                          max={line.request_mode === "exact_quantity" ? Number(line.quantity_requested ?? 0) : undefined}
                          step="0.001"
                          defaultValue={defaultAuthorized(line)}
                        />
                      </label>
                    ))}
                    <label><span>Razón de la decisión</span><input name="note" minLength={5} maxLength={240} required /></label>
                    <button className="action-button approve" disabled={pending === request.request_id} onClick={(event) => void decideTransfer(request, "authorize", event.currentTarget.form!)}>Autorizar y reservar</button>
                    <button className="action-button" disabled={pending === request.request_id} onClick={(event) => void decideTransfer(request, "reject", event.currentTarget.form!)}>Rechazar</button>
                  </form>
                )}
              </div>
              <StatusPill status={request.status} />
            </article>
          ))}
          {!openTransfers.length && <p className="ops-empty">No hay solicitudes por revisar.</p>}
        </div>
      </section>

      <div className="ops-bottom">
        <section className="ops-panel" id="despachos">
          <header className="ops-panel-header"><div><h2>Preparar salida</h2><p>Sin datos de transporte completos el despacho no puede salir.</p></div></header>
          <div className="ops-list">
            {allocations.filter((allocation) => allocation.status === "reserved" && !allocation.transfer_request_id).map((allocation) => {
              const origins = locations.filter((location) => location.organization_id === allocation.organization_id && location.dispatches_shipments);
              return <article className="ops-row" key={allocation.id}>
                <div>
                  <h3>{allocation.inventory_lots?.lot_code}</h3>
                  <p>{numberFormat.format(allocation.quantity)} {allocation.inventory_lots?.unit} · {allocation.inventory_lots?.category}</p>
                  {origins.length ? (
                    <form className="inline-form" onSubmit={(event) => { event.preventDefault(); void prepareNeedShipment(allocation, event.currentTarget); }}>
                      <label><span>Sale desde</span><select name="origin" required>{origins.map((origin) => <option key={origin.id} value={origin.id}>{origin.name}</option>)}</select></label>
                      <label><span>Zona de destino</span><input name="destination" defaultValue={allocation.need_items?.need_cases?.public_location_text ?? ""} minLength={3} maxLength={180} required /></label>
                      <TransportFields />
                      <button className="action-button approve" disabled={pending === allocation.id}><Send size={12} /> Preparar despacho</button>
                    </form>
                  ) : (
                    <p className="ops-inline-warning">Esta organización no tiene ningún punto habilitado para despachar. Actívalo en <a href="/operaciones/centros">Puntos de entrega</a>.</p>
                  )}
                </div>
                <StatusPill status={allocation.status} />
              </article>;
            })}
            {authorizedTransfers.map((request) => (
              <article className="ops-row" key={request.request_id}>
                <div>
                  <h3>{request.request_code} · solicitud autorizada</h3>
                  <p>{request.origin_name} → {request.destination_name} ({request.requesting_organization_name})</p>
                  <ul className="request-line-list">
                    {request.lines.filter((line) => Number(line.quantity_authorized) > 0).map((line) => (
                      <li key={line.item_id}><strong>{line.category}</strong> {numberFormat.format(Number(line.quantity_authorized))} {line.unit}</li>
                    ))}
                  </ul>
                  <form className="inline-form" onSubmit={(event) => { event.preventDefault(); void prepareTransferShipment(request, event.currentTarget); }}>
                    <TransportFields />
                    <button className="action-button approve" disabled={pending === request.request_id}><Send size={12} /> Preparar salida</button>
                  </form>
                </div>
                <StatusPill status={request.status} />
              </article>
            ))}
            {!allocations.some((allocation) => allocation.status === "reserved") && !authorizedTransfers.length && <p className="ops-empty">Aún no hay existencias reservadas por despachar.</p>}
          </div>
        </section>

        <section className="ops-panel" id="movimiento">
          <header className="ops-panel-header"><div><h2><Truck size={17} /> Movimiento</h2><p>Preparando → Despachado → En movimiento → Llegó → Recibido.</p></div></header>
          <div className="ops-list">
            {preparingShipments.map((shipment) => (
              <article className="ops-row" key={shipment.id}>
                <div>
                  <h3>{shipment.shipment_code}</h3>
                  <p>{linesByShipment.get(shipment.id)?.[0]?.origin_name ?? locationById.get(shipment.origin_location_id ?? "")?.name ?? "Origen"} → {linesByShipment.get(shipment.id)?.[0]?.destination_label ?? shipment.public_destination} · {shipment.transport_mode ?? "sin transporte"} {shipment.transport_plate ?? ""}</p>
                  <button className="action-button approve" disabled={pending === shipment.id} onClick={() => void run(shipment.id, "Despacho fuera de la bodega. La existencia salió del inventario de origen.", () => supabase.rpc("dispatch_shipment", { p_shipment_id: shipment.id }))}>Despachar</button>
                </div>
                <StatusPill status={shipment.status}>{MOVEMENT_LABELS[shipment.status] ?? labelStatus(shipment.status)}</StatusPill>
              </article>
            ))}
            {movingShipments.map((shipment) => {
              const lines = linesByShipment.get(shipment.id) ?? [];
              const shipped = shipment.shipment_items.reduce((sum, item) => sum + Number(item.quantity), 0);
              const conciliado = lines.length > 0 && lines.every((line) => line.outcome !== "PENDIENTE");
              return (
                <article className="ops-row" key={shipment.id}>
                  <div>
                    <h3>{shipment.shipment_code}</h3>
                    <p>{lines[0]?.origin_name ?? locationById.get(shipment.origin_location_id ?? "")?.name ?? "Origen"} → {lines[0]?.destination_label ?? shipment.public_destination} · {numberFormat.format(shipped)} despachadas</p>
                    <div className="ops-actions">
                      {shipment.status === "dispatched" && <button className="action-button" disabled={pending === shipment.id} onClick={() => void run(shipment.id, "Despacho en movimiento.", () => supabase.rpc("advance_shipment", { p_shipment_id: shipment.id, p_next_state: "in_transit" }))}>Marcar en movimiento</button>}
                      {["dispatched", "in_transit"].includes(shipment.status) && <button className="action-button" disabled={pending === shipment.id} onClick={() => void run(shipment.id, "Despacho reportado como llegado.", () => supabase.rpc("advance_shipment", { p_shipment_id: shipment.id, p_next_state: "arrived" }))}>Marcar llegada</button>}
                    </div>
                    {/*
                      Se recibe producto a producto: 500 litros de agua y 100 mercados no
                      se suman. El faltante no se escribe, se deduce de lo que salió menos
                      lo recibido y lo dañado.
                    */}
                    {conciliado ? (
                      <ul className="request-line-list">
                        {lines.map((line) => (
                          <li key={line.shipment_item_id}>
                            <strong>{line.category}</strong> {numberFormat.format(Number(line.quantity_received))} de {numberFormat.format(Number(line.quantity_dispatched))} {line.unit} · {line.outcome}
                          </li>
                        ))}
                      </ul>
                    ) : puedeRecibir(shipment) && lines.length ? (
                      <form className="reception-form" onSubmit={(event) => { event.preventDefault(); void receiveShipment(shipment, event.currentTarget); }}>
                        {lines.map((line) => (
                          <div className="reception-line" key={line.shipment_item_id}>
                            <p><strong>{line.category}</strong> · esperado {numberFormat.format(Number(line.quantity_dispatched))} {line.unit}</p>
                            <label><span>Recibido</span><input name={`recibido-${line.shipment_item_id}`} type="number" min="0" max={Number(line.quantity_dispatched)} step="0.001" defaultValue={Number(line.quantity_dispatched)} required /></label>
                            <label><span>Dañado</span><input name={`danado-${line.shipment_item_id}`} type="number" min="0" max={Number(line.quantity_dispatched)} step="0.001" defaultValue="0" required /></label>
                          </div>
                        ))}
                        <button className="action-button approve" disabled={pending === shipment.id}>Confirmar en destino</button>
                      </form>
                    ) : (
                      <p className="ops-inline-warning">Solo la bodega de destino confirma lo que recibió.</p>
                    )}
                  </div>
                  <StatusPill status={shipment.status}>{MOVEMENT_LABELS[shipment.status] ?? labelStatus(shipment.status)}</StatusPill>
                </article>
              );
            })}
            {!preparingShipments.length && !movingShipments.length && <p className="ops-empty">No hay despachos en curso.</p>}
          </div>
        </section>

        <section className="ops-panel" id="entregas">
          <header className="ops-panel-header"><div><h2>Entregas conciliadas</h2><p>CONFORME cuando concilia; NOVEDAD cuando hay daño o faltante.</p></div></header>
          <div className="ops-list">
            {deliveries.map((delivery) => {
              const conforme = Number(delivery.quantity_damaged) === 0 && Number(delivery.quantity_missing) === 0;
              return (
                <article className="ops-row" key={delivery.id}>
                  <div>
                    <h3>{delivery.shipments?.shipment_code} · {conforme ? "CONFORME" : "NOVEDAD"}</h3>
                    <p>{numberFormat.format(delivery.quantity_delivered)} recibidas · {numberFormat.format(delivery.quantity_damaged)} dañadas · {numberFormat.format(delivery.quantity_missing)} faltantes</p>
                    {canValidate && ["delivered", "incident"].includes(delivery.status) && <button className="action-button approve" disabled={pending === delivery.id} onClick={() => void run(delivery.id, "Entrega validada. Cobertura actualizada.", () => supabase.rpc("validate_delivery", { p_delivery_id: delivery.id, p_note: "Validación registrada" }))}>Validar y conciliar</button>}
                  </div>
                  <StatusPill status={delivery.status} />
                </article>
              );
            })}
            {!deliveries.length && <p className="ops-empty">Todavía no hay entregas registradas.</p>}
          </div>
        </section>
      </div>

      <aside className="ops-safety-note"><ShieldAlert size={18} /><div><strong>Sin escritura directa de stock</strong><p>Ninguna cifra de inventario se edita a mano: todas salen de movimientos registrados en el Kardex.</p></div></aside>
    </>
  );
}
