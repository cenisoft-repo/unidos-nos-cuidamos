"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { CloudOff, PackageCheck, Search, Send, ShieldAlert, Truck } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { toOperationalMessage } from "@/lib/user-errors";
import { enqueueOfflineReception, readOfflineReceptions, removeOfflineReception, type OfflineReception } from "@/lib/offline-queue";
import { StatusPill } from "./status-pill";
import { numberFormat } from "@/lib/format";

type PromiseItem = { id: string; category: string; description: string; quantity_promised: number; quantity_received: number; quantity_rejected: number; unit: string; donations: { donor_tracking_code: string; status: string; organization_id: string } | null };
type Location = { id: string; name: string; organization_id: string; accepts_donations: boolean; dispatches_shipments: boolean };
type Lot = { id: string; lot_code: string; category: string; status: string; quantity_initial: number; unit: string; organization_id: string };
type NeedItem = { id: string; category: string; quantity_required: number; quantity_covered: number; unit: string; need_cases: { public_location_text: string; status: string } | null };
type Allocation = { id: string; quantity: number; status: string; organization_id: string; inventory_lots: { lot_code: string; category: string; unit: string } | null; need_items: { category: string; need_cases: { public_location_text: string } | null } | null };
type Shipment = { id: string; shipment_code: string; status: string; public_destination: string; origin_location_id: string | null; shipment_items: { quantity: number }[] };
type Delivery = { id: string; status: string; quantity_delivered: number; quantity_damaged: number; shipments: { shipment_code: string } | null };

export function WarehouseConsole({ promiseItems, locations, lots, needItems, allocations, shipments, deliveries, canValidate }: { promiseItems: PromiseItem[]; locations: Location[]; lots: Lot[]; needItems: NeedItem[]; allocations: Allocation[]; shipments: Shipment[]; deliveries: Delivery[]; canValidate: boolean }) {
  const router = useRouter();
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [pending, setPending] = useState("");
  const [queued, setQueued] = useState(0);
  const [receptionQuery, setReceptionQuery] = useState("");
  const [selectedLotId, setSelectedLotId] = useState(() => lots.find((lot) => ["available", "reserved"].includes(lot.status))?.id ?? "");
  const supabase = useMemo(() => createClient(), []);
  const normalizedQuery = receptionQuery.trim().toLocaleLowerCase("es");
  const visiblePromiseItems = promiseItems.filter((item) => !normalizedQuery || [
    item.category,
    item.description,
    item.donations?.donor_tracking_code ?? "",
  ].some((value) => value.toLocaleLowerCase("es").includes(normalizedQuery)));
  const selectedLot = lots.find((lot) => lot.id === selectedLotId);
  const compatibleNeedItems = selectedLot
    ? needItems.filter((need) => need.category === selectedLot.category && need.unit === selectedLot.unit && Number(need.quantity_covered) < Number(need.quantity_required))
    : [];

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

  async function receive(item: PromiseItem, form: HTMLFormElement) {
    const data = new FormData(form);
    const accepted = Number(data.get("accepted"));
    const rejected = Number(data.get("rejected"));
    const locationId = String(data.get("location"));
    const operation: OfflineReception = { id: crypto.randomUUID(), donationItemId: item.id, locationId, accepted, rejected, condition: "sellado", createdAt: new Date().toISOString() };
    setPending(item.id); setError(""); setMessage("");
    if (!navigator.onLine) {
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
    const { error: actionError } = await supabase.rpc("receive_donation", { p_donation_item_id: item.id, p_location_id: locationId, p_accepted: accepted, p_rejected: rejected, p_condition: "sellado", p_idempotency_key: operation.id });
    setPending("");
    if (actionError) { setError(toOperationalMessage(actionError)); return; }
    setMessage("Recepción conciliada y lote creado exactamente una vez."); router.refresh();
  }

  async function allocate(form: HTMLFormElement) {
    const data = new FormData(form); setPending("allocate"); setError("");
    const { error: actionError } = await supabase.rpc("allocate_stock", { p_lot_id: String(data.get("lot")), p_need_item_id: String(data.get("need")), p_quantity: Number(data.get("quantity")), p_idempotency_key: crypto.randomUUID() });
    setPending(""); if (actionError) { setError(toOperationalMessage(actionError)); return; } setMessage("Existencia reservada."); router.refresh();
  }

  async function dispatch(allocation: Allocation, form: HTMLFormElement) {
    const data = new FormData(form);
    setPending(allocation.id); setError("");
    const { error: actionError } = await supabase.rpc("create_shipment", {
      p_allocation_id: allocation.id,
      p_origin_location_id: String(data.get("origin")),
      p_public_destination: String(data.get("destination")).trim(),
      p_carrier_name: String(data.get("carrier") ?? "").trim(),
      p_idempotency_key: crypto.randomUUID(),
    });
    setPending(""); if (actionError) { setError(toOperationalMessage(actionError)); return; } setMessage("Despacho creado con origen y destino registrados."); router.refresh();
  }

  async function deliver(shipment: Shipment) {
    const quantity = shipment.shipment_items.reduce((sum, item) => sum + Number(item.quantity), 0);
    setPending(shipment.id); setError("");
    const { error: actionError } = await supabase.rpc("register_delivery", { p_shipment_id: shipment.id, p_quantity_delivered: quantity, p_quantity_damaged: 0, p_idempotency_key: crypto.randomUUID() });
    setPending(""); if (actionError) { setError(toOperationalMessage(actionError)); return; } setMessage("Entrega registrada; espera validación independiente."); router.refresh();
  }

  async function validate(id: string) {
    setPending(id); setError("");
    const { error: actionError } = await supabase.rpc("validate_delivery", { p_delivery_id: id, p_note: "Validación registrada" });
    setPending(""); if (actionError) { setError(toOperationalMessage(actionError)); return; } setMessage("Entrega validada. Cobertura actualizada."); router.refresh();
  }

  return (
    <>
      <nav className="warehouse-steps" aria-label="Etapas de bodega y logística">
        <a href="#recepciones"><span>01</span> Recibir <strong>{promiseItems.length}</strong></a>
        <a href="#inventario"><span>02</span> Reservar <strong>{lots.filter((lot) => ["available", "reserved"].includes(lot.status)).length}</strong></a>
        <a href="#despachos"><span>03</span> Despachar <strong>{allocations.filter((allocation) => allocation.status === "reserved").length}</strong></a>
        <a href="#entregas"><span>04</span> Entregar <strong>{shipments.filter((shipment) => ["dispatched", "in_transit"].includes(shipment.status)).length}</strong></a>
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
            <div><h2><ShieldAlert size={18} /> Reservar existencia</h2><p>Solo se muestran necesidades con categoría y unidad compatibles.</p></div>
            <span>{compatibleNeedItems.length} compatibles</span>
          </header>
          <div className="lot-picker" role="group" aria-label="Seleccionar lote disponible">
            {lots.filter((lot) => ["available", "reserved"].includes(lot.status)).map((lot) => (
              <button key={lot.id} type="button" aria-pressed={selectedLotId === lot.id} onClick={() => setSelectedLotId(lot.id)}>
                <strong>{lot.lot_code}</strong>
                <span>{lot.category}</span>
                <small>{numberFormat.format(lot.quantity_initial)} {lot.unit}</small>
              </button>
            ))}
          </div>
          <form className="form-body" onSubmit={(event) => { event.preventDefault(); void allocate(event.currentTarget); }}>
            <input type="hidden" name="lot" value={selectedLotId} />
            <div className="field">
              <label htmlFor="need">Necesidad compatible</label>
              <select id="need" name="need" key={selectedLotId} required disabled={!compatibleNeedItems.length}>
                {compatibleNeedItems.map((need) => <option key={need.id} value={need.id}>{need.need_cases?.public_location_text} · faltan {numberFormat.format(Number(need.quantity_required) - Number(need.quantity_covered))} {need.unit}</option>)}
              </select>
              {!compatibleNeedItems.length && <small>Elige otro lote o espera una necesidad con la misma categoría y unidad.</small>}
            </div>
            <div className="field"><label htmlFor="allocation-quantity">Cantidad a reservar</label><input id="allocation-quantity" name="quantity" type="number" min="0.001" max={selectedLot?.quantity_initial} step="0.001" required /></div>
            <button className="button button-dark button-block" disabled={pending === "allocate" || !selectedLot || !compatibleNeedItems.length}>Reservar con control de concurrencia</button>
          </form>
        </section>
      </div>

      <div className="ops-bottom">
        <section className="ops-panel" id="despachos">
          <header className="ops-panel-header"><div><h2>Asignaciones listas</h2><p>Indica desde qué punto sale y hacia qué zona.</p></div></header>
          <div className="ops-list">
            {allocations.map((allocation) => {
              const origins = locations.filter((location) => location.organization_id === allocation.organization_id && location.dispatches_shipments);
              return <article className="ops-row" key={allocation.id}>
                <div>
                  <h3>{allocation.inventory_lots?.lot_code}</h3>
                  <p>{numberFormat.format(allocation.quantity)} {allocation.inventory_lots?.unit} · {allocation.inventory_lots?.category}</p>
                  {allocation.status === "reserved" && (origins.length ? (
                    <form className="inline-form" onSubmit={(event) => { event.preventDefault(); void dispatch(allocation, event.currentTarget); }}>
                      <label><span>Sale desde</span><select name="origin" required>{origins.map((origin) => <option key={origin.id} value={origin.id}>{origin.name}</option>)}</select></label>
                      <label><span>Zona de destino</span><input name="destination" defaultValue={allocation.need_items?.need_cases?.public_location_text ?? ""} minLength={3} maxLength={180} required /></label>
                      <label><span>Transportador</span><input name="carrier" maxLength={160} placeholder="Opcional y privado" /></label>
                      <button className="action-button approve" disabled={pending === allocation.id}><Send size={12} /> Crear despacho</button>
                    </form>
                  ) : (
                    <p className="ops-inline-warning">Esta organización no tiene ningún punto habilitado para despachar. Actívalo en <a href="/operaciones/centros">Puntos de entrega</a>.</p>
                  ))}
                </div>
                <StatusPill status={allocation.status} />
              </article>;
            })}
            {!allocations.length && <p className="ops-empty">Aún no hay existencias reservadas.</p>}
          </div>
        </section>
        <section className="ops-panel">
          <header className="ops-panel-header"><div><h2><Truck size={17} /> Despachos</h2><p>Siguiente acción: registrar el resultado.</p></div></header>
          <div className="ops-list">
            {shipments.map((shipment) => {
              const origin = locations.find((location) => location.id === shipment.origin_location_id);
              return <article className="ops-row" key={shipment.id}><div><h3>{shipment.shipment_code}</h3><p>{origin ? `${origin.name} → ` : ""}{shipment.public_destination}</p>{["dispatched", "in_transit"].includes(shipment.status) && <button className="action-button approve" disabled={pending === shipment.id} onClick={() => void deliver(shipment)}>Registrar entrega</button>}</div><StatusPill status={shipment.status} /></article>;
            })}
            {!shipments.length && <p className="ops-empty">No hay despachos creados.</p>}
          </div>
        </section>
        <section className="ops-panel" id="entregas">
          <header className="ops-panel-header"><div><h2>Entregas</h2><p>La validación independiente publica el resultado.</p></div></header>
          <div className="ops-list">
            {deliveries.map((delivery) => <article className="ops-row" key={delivery.id}><div><h3>{delivery.shipments?.shipment_code}</h3><p>{numberFormat.format(delivery.quantity_delivered)} entregadas · {numberFormat.format(delivery.quantity_damaged)} dañadas</p>{canValidate && ["delivered", "incident"].includes(delivery.status) && <button className="action-button approve" disabled={pending === delivery.id} onClick={() => void validate(delivery.id)}>Validar y conciliar</button>}</div><StatusPill status={delivery.status} /></article>)}
            {!deliveries.length && <p className="ops-empty">Todavía no hay entregas registradas.</p>}
          </div>
        </section>
      </div>

      <aside className="ops-safety-note"><ShieldAlert size={18} /><div><strong>Evidencia privada</strong><p>La carga de fotos y documentos aún no está disponible. Los movimientos operativos quedan registrados.</p></div></aside>
    </>
  );
}
