import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { assertSupabaseSuccess } from "@/lib/supabase/results";
import { TreasuryConsole } from "@/components/treasury-console";
import { EVENT_ID } from "@/lib/constants";
import { hasOperationalRole } from "@/lib/authorization";

export const metadata: Metadata = { title: "Tesorería sandbox" };
export const dynamic = "force-dynamic";

export default async function TreasuryPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/ingresar?next=/operaciones/tesoreria");

  // La membresía se comprueba en este evento: un rol vigente en otro evento no abre tesorería.
  const membershipsResult = await supabase.from("memberships").select("role").eq("user_id", user.id).eq("event_id", EVENT_ID).eq("active", true);
  assertSupabaseSuccess("membresia_tesoreria", [membershipsResult]);
  const roles = new Set((membershipsResult.data ?? []).map((item) => item.role));
  if (!hasOperationalRole(roles, ["treasury_requester", "treasury_approver", "event_admin", "auditor"])) redirect("/operaciones");
  const canReviewMoney = hasOperationalRole(roles, ["treasury_approver", "event_admin", "auditor"]);

  const results = await Promise.all([
    supabase.from("funds").select("id,name,verified,currency").eq("event_id", EVENT_ID),
    supabase.from("financial_transactions").select("id,transaction_type,amount,status,public_reference,created_at").eq("event_id", EVENT_ID).eq("status", "reconciled").order("created_at", { ascending: false }).limit(100),
    supabase.from("expense_requests").select("id,amount,purpose,status,requested_by,created_at").eq("event_id", EVENT_ID).order("created_at", { ascending: false }).limit(100),
    // El saldo no se suma sobre la lista visible: sale del libro completo.
    supabase.rpc("treasury_balance", { p_event_id: EVENT_ID }),
    supabase.rpc("expense_decisions", { p_event_id: EVENT_ID }),
  ]);
  assertSupabaseSuccess("tesoreria", results);
  const [funds, transactions, expenses, balance, decisions] = results;
  const pendingMoney = canReviewMoney
    ? await supabase.rpc("treasury_pending_money_donations", { p_event_id: EVENT_ID })
    : { data: [], error: null };
  assertSupabaseSuccess("aportes_monetarios_pendientes", [pendingMoney]);

  return (
    <div className="ops-shell">
      <div className="ops-header"><div><Link className="eyebrow" href="/operaciones"><ArrowLeft size={14}/> Centro operativo</Link><h1>Tesorería sandbox</h1><p>Fondo verificado, conciliación idempotente y gasto con separación de funciones.</p></div></div>
      <TreasuryConsole
        funds={(funds.data ?? []) as never[]}
        transactions={(transactions.data ?? []) as never[]}
        expenses={(expenses.data ?? []) as never[]}
        pendingMoney={(pendingMoney.data ?? []) as never[]}
        ledger={((balance.data ?? [])[0] ?? { balance: 0, reconciled_credits: 0, reconciled_debits: 0, movement_count: 0 }) as never}
        decisions={(decisions.data ?? []) as never[]}
        userId={user.id}
        canRequest={hasOperationalRole(roles, ["treasury_requester", "event_admin"])}
        canApprove={hasOperationalRole(roles, ["treasury_approver", "event_admin"])}
      />
    </div>
  );
}
