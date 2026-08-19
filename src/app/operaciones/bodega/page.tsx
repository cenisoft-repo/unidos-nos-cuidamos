import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { assertSupabaseSuccess } from "@/lib/supabase/results";
import { EVENT_ID } from "@/lib/constants";
import { WarehouseConsole } from "@/components/warehouse-console";

export const metadata: Metadata = { title: "Bodega y logística" };
export const dynamic = "force-dynamic";

export default async function WarehousePage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/ingresar?next=/operaciones/bodega");

  // La membresía se comprueba en este evento: un rol vigente en otro evento no abre esta consola.
  const membershipsResult = await supabase.from("memberships").select("role").eq("user_id", user.id).eq("event_id", EVENT_ID).eq("active", true);
  assertSupabaseSuccess("membresia_bodega", [membershipsResult]);
  const roles = new Set((membershipsResult.data ?? []).map((item) => item.role));
  if (!["warehouse_operator", "logistics_operator", "event_admin"].some((role) => roles.has(role))) redirect("/operaciones");

  // Las tablas sin `event_id` propio se acotan por su padre con un join interno.
  const results = await Promise.all([
    supabase.from("donation_items").select("id,category,description,quantity_promised,quantity_received,quantity_rejected,unit,donations!inner(donor_tracking_code,status,organization_id,event_id)").eq("donations.event_id", EVENT_ID).order("created_at"),
    supabase.from("inventory_locations").select("id,name,organization_id,accepts_donations,dispatches_shipments").eq("event_id", EVENT_ID).eq("active", true),
    // La posición del lote sale del Kardex, no del saldo con el que nació.
    supabase.from("inventory_lot_positions").select("lot_id,lot_code,category,unit,status,organization_id,location_id,quantity_physical,quantity_available,quantity_reserved,quantity_in_transit,quantity_delivered").eq("event_id", EVENT_ID).order("lot_code"),
    supabase.from("need_items").select("id,category,quantity_required,quantity_covered,unit,need_cases!inner(public_location_text,status,event_id)").eq("need_cases.event_id", EVENT_ID).order("created_at"),
    supabase.from("allocations").select("id,quantity,status,organization_id,transfer_request_id,inventory_lots(lot_code,category,unit),need_items(category,need_cases(public_location_text))").eq("event_id", EVENT_ID).order("created_at", { ascending: false }),
    supabase.from("shipments").select("id,shipment_code,status,public_destination,origin_location_id,destination_location_id,transfer_request_id,transport_mode,transport_plate,shipment_items(quantity)").eq("event_id", EVENT_ID).order("created_at", { ascending: false }),
    supabase.from("deliveries").select("id,status,quantity_delivered,quantity_damaged,quantity_missing,shipments!inner(shipment_code,event_id)").eq("shipments.event_id", EVENT_ID).order("created_at", { ascending: false }),
    supabase.from("transfer_requests").select("id,request_code,status,category,unit,quantity_requested,quantity_authorized,justification,origin_location_id,destination_location_id,requested_by").eq("event_id", EVENT_ID).order("requested_at", { ascending: false }),
  ]);
  assertSupabaseSuccess("bodega", results);
  const [itemsResult, locationsResult, lotsResult, needsResult, allocationsResult, shipmentsResult, deliveriesResult, transfersResult] = results;
  const items = (itemsResult.data ?? []).filter((item) => Number(item.quantity_received) + Number(item.quantity_rejected) < Number(item.quantity_promised));

  return (
    <div className="ops-shell">
      <div className="ops-header"><div><Link className="eyebrow" href="/operaciones"><ArrowLeft size={14}/> Centro operativo</Link><h1>Bodega y logística</h1><p>Recepción exacta, inventario por lote, reserva, despacho y entrega.</p></div></div>
      <WarehouseConsole
        promiseItems={items as never[]}
        locations={(locationsResult.data ?? []) as never[]}
        lotPositions={(lotsResult.data ?? []) as never[]}
        needItems={(needsResult.data ?? []) as never[]}
        allocations={(allocationsResult.data ?? []) as never[]}
        shipments={(shipmentsResult.data ?? []) as never[]}
        deliveries={(deliveriesResult.data ?? []) as never[]}
        transferRequests={(transfersResult.data ?? []) as never[]}
        canValidate={roles.has("verifier") || roles.has("event_admin")}
        userId={user.id}
      />
    </div>
  );
}
