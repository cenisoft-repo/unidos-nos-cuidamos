import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { assertSupabaseSuccess } from "@/lib/supabase/results";
import { EVENT_ID } from "@/lib/constants";
import { hasOperationalRole } from "@/lib/authorization";
import { OperationalReports } from "@/components/operational-reports";

export const metadata: Metadata = { title: "Reportes operativos" };
export const dynamic = "force-dynamic";

export default async function ReportsPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/ingresar?next=/operaciones/reportes");

  const membershipsResult = await supabase.from("memberships").select("role").eq("user_id", user.id).eq("event_id", EVENT_ID).eq("active", true);
  assertSupabaseSuccess("membresia_reportes", [membershipsResult]);
  const roles = new Set((membershipsResult.data ?? []).map((item) => item.role));
  if (!hasOperationalRole(roles, ["warehouse_operator", "logistics_operator", "event_admin", "auditor"])) redirect("/operaciones");

  // Todos los reportes salen del Kardex y de las funciones `security invoker`: cada persona
  // ve exactamente lo que su membresía ya podía leer.
  const results = await Promise.all([
    supabase.rpc("inventory_position", { p_event_id: EVENT_ID }),
    supabase.rpc("stock_reservations", { p_event_id: EVENT_ID }),
    supabase.rpc("shipments_in_movement", { p_event_id: EVENT_ID }),
    supabase.rpc("pending_dispatches", { p_event_id: EVENT_ID }),
    supabase.rpc("donations_by_ally", { p_event_id: EVENT_ID }),
    supabase.rpc("donations_by_need", { p_event_id: EVENT_ID }),
    supabase.rpc("stock_movement_history", { p_event_id: EVENT_ID, p_location_id: null, p_limit: 100 }),
  ]);
  assertSupabaseSuccess("reportes_operativos", results);
  const [position, reservations, movement, pendingDispatch, byAlly, byNeed, history] = results;

  return (
    <div className="ops-shell">
      <div className="ops-header"><div><Link className="eyebrow" href="/operaciones"><ArrowLeft size={14} /> Centro operativo</Link><h1>Reportes operativos</h1><p>Stock, reservas, movimiento, entregas y trazabilidad, derivados del Kardex.</p></div></div>
      <OperationalReports
        position={(position.data ?? []) as never[]}
        reservations={(reservations.data ?? []) as never[]}
        movement={(movement.data ?? []) as never[]}
        pendingDispatch={(pendingDispatch.data ?? []) as never[]}
        byAlly={(byAlly.data ?? []) as never[]}
        byNeed={(byNeed.data ?? []) as never[]}
        history={(history.data ?? []) as never[]}
      />
    </div>
  );
}
