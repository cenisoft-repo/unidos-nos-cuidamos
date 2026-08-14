"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { CloudOff, PackageCheck, Send, ShieldAlert, Truck } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { enqueueOfflineReception, readOfflineReceptions, removeOfflineReception, type OfflineReception } from "@/lib/offline-queue";
import { StatusPill } from "./status-pill";
import { numberFormat } from "@/lib/format";

type PromiseItem = { id: string; category: string; description: string; quantity_promised: number; quantity_received: number; quantity_rejected: number; unit: string; donations: { donor_tracking_code: string; status: string; organization_id: string } | null };
type Location = { id: string; name: string; organization_id: string };
type Lot = { id: string; lot_code: string; category: string; status: string; quantity_initial: number; unit: string; organization_id: string };
type NeedItem = { id: string; category: string; quantity_required: number; quantity_covered: number; unit: string; need_cases: { public_location_text: string; status: string } | null };
type Allocation = { id: string; quantity: number; status: string; inventory_lots: { lot_code: string; category: string; unit: string } | null; need_items: { category: string; need_cases: { public_location_text: string } | null } | null };
type Shipment = { id: string; shipment_code: string; status: string; public_destination: string; shipment_items: { quantity: number }[] };
type Delivery = { id: string; status: string; quantity_delivered: number; quantity_damaged: number; shipments: { shipment_code: string } | null };

export function WarehouseConsole({ promiseItems, locations, lots, needItems, allocations, shipments, deliveries, canValidate }: { promiseItems: PromiseItem[]; locations: Location[]; lots: Lot[]; needItems: NeedItem[]; allocations: Allocation[]; shipments: Shipment[]; deliveries: Delivery[]; canValidate: boolean }) {
  const router = useRouter();
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [pending, setPending] = useState("");
  const [queued, setQueued] = useState(() => readOfflineReceptions().length);
  const supabase = useMemo(() => createClient(), []);

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
    const online = () => void syncQueue();
    window.addEventListener("online", online);
    return () => window.removeEventListener("online", online);
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
      enqueueOfflineReception(operation); setQueued(readOfflineReceptions().length); setMessage("Recepción guardada en la cola local sin datos personales. Se sincronizará al recuperar conexión."); setPending(""); return;
    }
    const { error: actionError } = await supabase.rpc("receive_donation", { p_donation_item_id: item.id, p_location_id: locationId, p_accepted: accepted, p_rejected: rejected, p_condition: "sellado", p_idempotency_key: operation.id });
    setPending("");
    if (actionError) { setError(actionError.message); return; }
    setMessage("Recepción conciliada y lote creado exactamente una vez."); router.refresh();
  }

  async function allocate(form: HTMLFormElement) {
    const data = new FormData(form); setPending("allocate"); setError("");
    const { error: actionError } = await supabase.rpc("allocate_stock", { p_lot_id: String(data.get("lot")), p_need_item_id: String(data.get("need")), p_quantity: Number(data.get("quantity")), p_idempotency_key: crypto.randomUUID() });
    setPending(""); if (actionError) { setError(actionError.message); return; } setMessage("Existencia reservada sin permitir saldo negativo."); router.refresh();
  }

  async function dispatch(allocation: Allocation) {
    setPending(allocation.id); setError("");
    const publicDestination = allocation.need_items?.need_cases?.public_location_text ?? "Destino territorial aproximado";
    const { error: actionError } = await supabase.rpc("create_shipment", { p_allocation_id: allocation.id, p_public_destination: publicDestination, p_carrier_name: "Transportador sandbox", p_idempotency_key: crypto.randomUUID() });
    setPending(""); if (actionError) { setError(actionError.message); return; } setMessage("Despacho creado con custodia y movimientos append-only."); router.refresh();
  }

  async function deliver(shipment: Shipment) {
    const quantity = shipment.shipment_items.reduce((sum, item) => sum + Number(item.quantity), 0);
    setPending(shipment.id); setError("");
    const { error: actionError } = await supabase.rpc("register_delivery", { p_shipment_id: shipment.id, p_quantity_delivered: quantity, p_quantity_damaged: 0, p_idempotency_key: crypto.randomUUID() });
    setPending(""); if (actionError) { setError(actionError.message); return; } setMessage("Entrega registrada; espera validación independiente."); router.refresh();
  }

  async function validate(id: string) {
    setPending(id); setError("");
    const { error: actionError } = await supabase.rpc("validate_delivery", { p_delivery_id: id, p_note: "Validación de demostración" });
    setPending(""); if (actionError) { setError(actionError.message); return; } setMessage("Entrega validada; cobertura y proyección pública conciliadas."); router.refresh();
  }

  return <>
    {queued > 0 && <div className="ops-alert"><CloudOff size={17} /><strong>{queued} operación(es) en cola local.</strong><button className="action-button" onClick={() => void syncQueue()}>Sincronizar ahora</button></div>}
    {message && <p className="form-success">{message}</p>}{error && <p className="form-error" role="alert">{error}</p>}
    <div className="ops-grid"><section className="ops-panel"><header className="ops-panel-header"><h2><PackageCheck size={18} style={{display:"inline",marginRight:7}} /> Recepciones pendientes</h2><span>{promiseItems.length}</span></header><div className="ops-list">{promiseItems.map((item) => { const remaining=Number(item.quantity_promised)-Number(item.quantity_received)-Number(item.quantity_rejected); const validLocations=locations.filter((location)=>location.organization_id===item.donations?.organization_id); return <article className="ops-row" key={item.id}><div><h3>{item.category} · {item.donations?.donor_tracking_code}</h3><p>{item.description} · quedan {numberFormat.format(remaining)} {item.unit}</p><form className="inline-form" onSubmit={(event) => {event.preventDefault();void receive(item,event.currentTarget);}}><input name="accepted" aria-label={`Cantidad aceptada ${item.category}`} type="number" min="0" max={remaining} step="0.001" defaultValue={remaining} required /><input name="rejected" aria-label={`Cantidad rechazada ${item.category}`} type="number" min="0" max={remaining} step="0.001" defaultValue="0" required /><select name="location" aria-label={`Centro receptor ${item.category}`} required>{validLocations.map((location)=><option key={location.id} value={location.id}>{location.name}</option>)}</select><button className="action-button approve" disabled={pending===item.id||!validLocations.length}>Recibir</button></form></div><StatusPill status={item.donations?.status ?? "promised"} /></article>})}{!promiseItems.length&&<p className="ops-empty">No hay promesas aprobadas pendientes de recepción.</p>}</div></section>
    <section className="ops-panel"><header className="ops-panel-header"><h2><ShieldAlert size={18} style={{display:"inline",marginRight:7}} /> Reservar existencia</h2><span>{lots.filter(l=>["available","reserved"].includes(l.status)).length} lotes</span></header><form className="form-body" onSubmit={(event)=>{event.preventDefault();void allocate(event.currentTarget);}}><div className="field"><label htmlFor="lot">Lote disponible</label><select id="lot" name="lot" required>{lots.filter((lot)=>["available","reserved"].includes(lot.status)).map((lot)=><option key={lot.id} value={lot.id}>{lot.lot_code} · {lot.category} · {numberFormat.format(lot.quantity_initial)} {lot.unit}</option>)}</select></div><div className="field"><label htmlFor="need">Necesidad compatible</label><select id="need" name="need" required>{needItems.map((need)=><option key={need.id} value={need.id}>{need.category} · {need.need_cases?.public_location_text} · faltan {numberFormat.format(Number(need.quantity_required)-Number(need.quantity_covered))} {need.unit}</option>)}</select></div><div className="field"><label htmlFor="allocation-quantity">Cantidad</label><input id="allocation-quantity" name="quantity" type="number" min="0.001" step="0.001" required /></div><button className="button button-dark button-block" disabled={pending==="allocate"}>Reservar con control de concurrencia</button></form></section></div>
    <div className="ops-bottom"><section className="ops-panel"><header className="ops-panel-header"><h2>Asignaciones</h2></header><div className="ops-list">{allocations.map((allocation)=><article className="ops-row" key={allocation.id}><div><h3>{allocation.inventory_lots?.lot_code}</h3><p>{numberFormat.format(allocation.quantity)} {allocation.inventory_lots?.unit} · {allocation.inventory_lots?.category}</p>{allocation.status==="reserved"&&<button className="action-button approve" disabled={pending===allocation.id} onClick={()=>void dispatch(allocation)}><Send size={12} style={{display:"inline"}} /> Despachar</button>}</div><StatusPill status={allocation.status} /></article>)}</div></section><section className="ops-panel"><header className="ops-panel-header"><h2><Truck size={17} style={{display:"inline",marginRight:6}} /> Despachos</h2></header><div className="ops-list">{shipments.map((shipment)=><article className="ops-row" key={shipment.id}><div><h3>{shipment.shipment_code}</h3><p>{shipment.public_destination}</p>{["dispatched","in_transit"].includes(shipment.status)&&<button className="action-button approve" disabled={pending===shipment.id} onClick={()=>void deliver(shipment)}>Registrar entrega</button>}</div><StatusPill status={shipment.status} /></article>)}</div></section><section className="ops-panel"><header className="ops-panel-header"><h2>Entregas</h2></header><div className="ops-list">{deliveries.map((delivery)=><article className="ops-row" key={delivery.id}><div><h3>{delivery.shipments?.shipment_code}</h3><p>{numberFormat.format(delivery.quantity_delivered)} entregadas · {numberFormat.format(delivery.quantity_damaged)} dañadas</p>{canValidate&&["delivered","incident"].includes(delivery.status)&&<button className="action-button approve" disabled={pending===delivery.id} onClick={()=>void validate(delivery.id)}>Validar resultado</button>}</div><StatusPill status={delivery.status} /></article>)}</div></section></div>
  </>;
}
