import { Boxes, ClipboardList, HeartHandshake, History, PackageSearch, Truck } from "lucide-react";
import { numberFormat } from "@/lib/format";
import { labelStatus } from "@/lib/constants";

type Position = { location_name: string; category: string; unit: string; quantity_physical: number; quantity_available: number; quantity_reserved: number; quantity_in_transit: number; quantity_delivered: number; lots: number };
type Reservation = { allocation_id: string; location_name: string; lot_code: string; category: string; unit: string; quantity: number; destination_kind: string; destination_label: string };
type Movement = { shipment_id: string; shipment_code: string; status: string; origin_name: string | null; destination_label: string | null; is_transfer: boolean; quantity: number; unit: string | null; category: string | null; transport_mode: string | null; transport_plate: string | null };
type PendingDispatch = { reference: string; kind: string; origin_name: string | null; destination_label: string | null; category: string | null; unit: string | null; quantity: number; status: string };
type ByAlly = { organization_id: string; organization_name: string; donations: number; quantity_promised: number; quantity_received: number; category: string; unit: string };
type ByNeed = { need_tracking_code: string; need_location: string; category: string; unit: string; quantity_requested: number; quantity_committed: number; quantity_received: number; quantity_delivered: number; quantity_pending: number; contributing_allies: number };
type HistoryRow = { moved_at: string; location_name: string; lot_code: string; category: string; unit: string; movement_type: string; quantity_delta: number; reason: string };

const MOVEMENT_TYPES: Record<string, string> = {
  receipt: "Recepción",
  transfer_in: "Entrada por traslado",
  transfer_out: "Salida por traslado",
  reserve: "Reserva",
  release: "Liberación",
  dispatch: "Despacho",
  adjustment: "Ajuste",
  write_off: "Baja",
  return: "Devolución",
};

function ReportSection({ title, hint, icon, children }: { title: string; hint: string; icon: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="ops-panel report-panel">
      <header className="ops-panel-header"><div><h2>{icon} {title}</h2><p>{hint}</p></div></header>
      <div className="report-scroll">{children}</div>
    </section>
  );
}

export function OperationalReports({ position, reservations, movement, pendingDispatch, byAlly, byNeed, history }: {
  position: Position[];
  reservations: Reservation[];
  movement: Movement[];
  pendingDispatch: PendingDispatch[];
  byAlly: ByAlly[];
  byNeed: ByNeed[];
  history: HistoryRow[];
}) {
  return (
    <div className="report-grid">
      <ReportSection title="Estado global del inventario" hint="Por centro, categoría y unidad. La unidad nunca se convierte." icon={<Boxes size={18} />}>
        <table className="report-table">
          <thead><tr><th>Centro</th><th>Categoría</th><th>Físico</th><th>Disponible</th><th>Reservado</th><th>En movimiento</th><th>Entregado</th><th>Lotes</th></tr></thead>
          <tbody>
            {position.map((row) => (
              <tr key={`${row.location_name}-${row.category}-${row.unit}`}>
                <td>{row.location_name}</td>
                <td>{row.category} <small>({row.unit})</small></td>
                <td>{numberFormat.format(row.quantity_physical)}</td>
                <td>{numberFormat.format(row.quantity_available)}</td>
                <td>{numberFormat.format(row.quantity_reserved)}</td>
                <td>{numberFormat.format(row.quantity_in_transit)}</td>
                <td>{numberFormat.format(row.quantity_delivered)}</td>
                <td>{row.lots}</td>
              </tr>
            ))}
            {!position.length && <tr><td colSpan={8}>Todavía no hay existencias registradas.</td></tr>}
          </tbody>
        </table>
      </ReportSection>

      <ReportSection title="Reservas vigentes" hint="Comprometido con una necesidad o con un traslado, todavía sin salir." icon={<ClipboardList size={18} />}>
        <table className="report-table">
          <thead><tr><th>Lote</th><th>Centro</th><th>Cantidad</th><th>Destino</th></tr></thead>
          <tbody>
            {reservations.map((row) => (
              <tr key={row.allocation_id}>
                <td>{row.lot_code} <small>{row.category}</small></td>
                <td>{row.location_name}</td>
                <td>{numberFormat.format(row.quantity)} {row.unit}</td>
                <td>{row.destination_kind === "traslado" ? "Traslado" : "Necesidad"} · {row.destination_label}</td>
              </tr>
            ))}
            {!reservations.length && <tr><td colSpan={4}>No hay reservas vigentes.</td></tr>}
          </tbody>
        </table>
      </ReportSection>

      <ReportSection title="Productos en movimiento" hint="Ya salieron y el destino todavía no confirma." icon={<Truck size={18} />}>
        <table className="report-table">
          <thead><tr><th>Despacho</th><th>Ruta</th><th>Cantidad</th><th>Transporte</th><th>Estado</th></tr></thead>
          <tbody>
            {movement.map((row) => (
              <tr key={row.shipment_id}>
                <td>{row.shipment_code} {row.is_transfer && <small>traslado</small>}</td>
                <td>{row.origin_name} → {row.destination_label}</td>
                <td>{numberFormat.format(row.quantity)} {row.unit ?? ""}</td>
                <td>{row.transport_mode ?? "—"} {row.transport_plate ?? ""}</td>
                <td>{labelStatus(row.status)}</td>
              </tr>
            ))}
            {!movement.length && <tr><td colSpan={5}>Nada en movimiento ahora mismo.</td></tr>}
          </tbody>
        </table>
      </ReportSection>

      <ReportSection title="Despachos pendientes" hint="Traslados autorizados sin salir y despachos en preparación." icon={<PackageSearch size={18} />}>
        <table className="report-table">
          <thead><tr><th>Referencia</th><th>Tipo</th><th>Ruta</th><th>Cantidad</th><th>Estado</th></tr></thead>
          <tbody>
            {pendingDispatch.map((row) => (
              <tr key={row.reference}>
                <td>{row.reference}</td>
                <td>{row.kind}</td>
                <td>{row.origin_name} → {row.destination_label}</td>
                <td>{numberFormat.format(row.quantity)} {row.unit ?? ""} {row.category ? `· ${row.category}` : ""}</td>
                <td>{labelStatus(row.status)}</td>
              </tr>
            ))}
            {!pendingDispatch.length && <tr><td colSpan={5}>No hay despachos pendientes.</td></tr>}
          </tbody>
        </table>
      </ReportSection>

      <ReportSection title="Donaciones por aliado" hint="Lo prometido y lo efectivamente recibido, sin sumar unidades distintas." icon={<HeartHandshake size={18} />}>
        <table className="report-table">
          <thead><tr><th>Aliado</th><th>Categoría</th><th>Donaciones</th><th>Prometido</th><th>Recibido</th></tr></thead>
          <tbody>
            {byAlly.map((row) => (
              <tr key={`${row.organization_id}-${row.category}-${row.unit}`}>
                <td>{row.organization_name}</td>
                <td>{row.category} <small>({row.unit})</small></td>
                <td>{row.donations}</td>
                <td>{numberFormat.format(row.quantity_promised)}</td>
                <td>{numberFormat.format(row.quantity_received)}</td>
              </tr>
            ))}
            {!byAlly.length && <tr><td colSpan={5}>Todavía no hay donaciones aprobadas.</td></tr>}
          </tbody>
        </table>
      </ReportSection>

      <ReportSection title="Donaciones asociadas a necesidades" hint="Solicitado, comprometido, recibido, entregado y pendiente por caso." icon={<HeartHandshake size={18} />}>
        <table className="report-table">
          <thead><tr><th>Necesidad</th><th>Categoría</th><th>Solicitado</th><th>Comprometido</th><th>Recibido</th><th>Entregado</th><th>Pendiente</th><th>Aliados</th></tr></thead>
          <tbody>
            {byNeed.map((row) => (
              <tr key={`${row.need_tracking_code}-${row.category}-${row.unit}`}>
                <td>{row.need_tracking_code} <small>{row.need_location}</small></td>
                <td>{row.category} <small>({row.unit})</small></td>
                <td>{numberFormat.format(row.quantity_requested)}</td>
                <td>{numberFormat.format(row.quantity_committed)}</td>
                <td>{numberFormat.format(row.quantity_received)}</td>
                <td>{numberFormat.format(row.quantity_delivered)}</td>
                <td>{numberFormat.format(row.quantity_pending)}</td>
                <td>{row.contributing_allies}</td>
              </tr>
            ))}
            {!byNeed.length && <tr><td colSpan={8}>No hay necesidades con artículos registrados.</td></tr>}
          </tbody>
        </table>
      </ReportSection>

      <ReportSection title="Historial de movimientos" hint="El Kardex tal cual: la fuente de todas las cifras anteriores." icon={<History size={18} />}>
        <table className="report-table">
          <thead><tr><th>Fecha</th><th>Centro</th><th>Lote</th><th>Movimiento</th><th>Cantidad</th><th>Motivo</th></tr></thead>
          <tbody>
            {history.map((row, index) => (
              <tr key={`${row.lot_code}-${row.moved_at}-${index}`}>
                <td>{new Date(row.moved_at).toLocaleString("es-CO", { timeZone: "America/Bogota" })}</td>
                <td>{row.location_name}</td>
                <td>{row.lot_code} <small>{row.category}</small></td>
                <td>{MOVEMENT_TYPES[row.movement_type] ?? row.movement_type}</td>
                <td>{numberFormat.format(row.quantity_delta)} {row.unit}</td>
                <td>{row.reason}</td>
              </tr>
            ))}
            {!history.length && <tr><td colSpan={6}>El Kardex todavía no tiene movimientos.</td></tr>}
          </tbody>
        </table>
      </ReportSection>
    </div>
  );
}
