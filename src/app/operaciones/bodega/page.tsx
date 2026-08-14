import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { WarehouseConsole } from "@/components/warehouse-console";

export const metadata: Metadata = { title: "Bodega y logística" };
export const dynamic = "force-dynamic";

export default async function WarehousePage() {
  const supabase=await createClient(); const {data:{user}}=await supabase.auth.getUser(); if(!user) redirect("/ingresar?next=/operaciones/bodega");
  const {data:memberships}=await supabase.from("memberships").select("role").eq("user_id",user.id).eq("active",true);
  const roles=new Set((memberships??[]).map((item)=>item.role)); if(!["warehouse_operator","logistics_operator","event_admin"].some((role)=>roles.has(role))) redirect("/operaciones");
  const [itemsResult,locationsResult,lotsResult,needsResult,allocationsResult,shipmentsResult,deliveriesResult]=await Promise.all([
    supabase.from("donation_items").select("id,category,description,quantity_promised,quantity_received,quantity_rejected,unit,donations(donor_tracking_code,status,organization_id)").order("created_at"),
    supabase.from("inventory_locations").select("id,name,organization_id").eq("active",true),
    supabase.from("inventory_lots").select("id,lot_code,category,status,quantity_initial,unit,organization_id").order("created_at",{ascending:false}),
    supabase.from("need_items").select("id,category,quantity_required,quantity_covered,unit,need_cases(public_location_text,status)").order("created_at"),
    supabase.from("allocations").select("id,quantity,status,inventory_lots(lot_code,category,unit),need_items(category,need_cases(public_location_text))").order("created_at",{ascending:false}),
    supabase.from("shipments").select("id,shipment_code,status,public_destination,shipment_items(quantity)").order("created_at",{ascending:false}),
    supabase.from("deliveries").select("id,status,quantity_delivered,quantity_damaged,shipments(shipment_code)").order("created_at",{ascending:false}),
  ]);
  const items=(itemsResult.data??[]).filter((item)=>Number(item.quantity_received)+Number(item.quantity_rejected)<Number(item.quantity_promised));
  return <div className="ops-shell"><div className="ops-header"><div><Link className="eyebrow" href="/operaciones"><ArrowLeft size={14}/> Centro operativo</Link><h1>Bodega y logística</h1><p>Recepción exacta, inventario por lote, reserva, despacho y entrega.</p></div></div><WarehouseConsole promiseItems={items as never[]} locations={(locationsResult.data??[]) as never[]} lots={(lotsResult.data??[]) as never[]} needItems={(needsResult.data??[]) as never[]} allocations={(allocationsResult.data??[]) as never[]} shipments={(shipmentsResult.data??[]) as never[]} deliveries={(deliveriesResult.data??[]) as never[]} canValidate={roles.has("verifier")||roles.has("event_admin")} /></div>;
}
