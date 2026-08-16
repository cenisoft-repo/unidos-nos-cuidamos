"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { toOperationalMessage } from "@/lib/user-errors";

export function IntakeActions({ id }: { id: string }) {
  const router = useRouter();
  const [pending, setPending] = useState("");
  const [error, setError] = useState("");

  async function decide(decision: "approve" | "observe" | "reject") {
    setPending(decision); setError("");
    const supabase = createClient();
    const { error: actionError } = await supabase.rpc("review_donation_intake", { p_intake_id: id, p_decision: decision, p_note: decision === "approve" ? "Verificación aprobada" : "Decisión registrada" });
    setPending("");
    if (actionError) { setError(toOperationalMessage(actionError)); return; }
    router.refresh();
  }

  return <><div className="action-bar"><button className="action-button approve" disabled={!!pending} onClick={() => void decide("approve")}>{pending === "approve" ? "…" : "Aprobar"}</button><button className="action-button" disabled={!!pending} onClick={() => void decide("observe")}>Observar</button><button className="action-button" disabled={!!pending} onClick={() => void decide("reject")}>Rechazar</button></div>{error && <span className="field-error">{error}</span>}</>;
}

export function NeedActions({ id, status }: { id: string; status: string }) {
  const router = useRouter();
  const [pending, setPending] = useState("");
  const [error, setError] = useState("");

  async function decide(decision: "verify" | "publish" | "observe" | "reject") {
    setPending(decision); setError("");
    const supabase = createClient();
    const { error: actionError } = await supabase.rpc("review_need_case", { p_need_id: id, p_decision: decision, p_note: `Decisión  registrada`, p_confidence: decision === "verify" || decision === "publish" ? 75 : null, p_expires_at: null });
    setPending("");
    if (actionError) { setError(toOperationalMessage(actionError)); return; }
    router.refresh();
  }

  return <><div className="action-bar">{status === "verified" ? <button className="action-button approve" disabled={!!pending} onClick={() => void decide("publish")}>{pending === "publish" ? "…" : "Publicar seguro"}</button> : <button className="action-button approve" disabled={!!pending} onClick={() => void decide("verify")}>{pending === "verify" ? "…" : "Verificar"}</button>}<button className="action-button" disabled={!!pending} onClick={() => void decide("observe")}>Observar</button><button className="action-button" disabled={!!pending} onClick={() => void decide("reject")}>Rechazar</button></div>{error && <span className="field-error">{error}</span>}</>;
}
