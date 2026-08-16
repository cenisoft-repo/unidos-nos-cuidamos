"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { toOperationalMessage } from "@/lib/user-errors";
import { currencyFormat, formatDate } from "@/lib/format";
import { StatusPill } from "./status-pill";

type Fund = { id: string; name: string; verified: boolean; currency: string };
type Tx = { id: string; transaction_type: string; amount: number; status: string; public_reference: string; created_at: string };
type Expense = { id: string; amount: number; purpose: string; status: string; requested_by: string; created_at: string };
type PendingMoney = { donation_id: string; tracking_code: string; intake_tracking_code: string; declared_amount: number; currency: string; attribution: string; submitted_at: string };

type TreasuryConsoleProps = {
  funds: Fund[];
  transactions: Tx[];
  expenses: Expense[];
  pendingMoney: PendingMoney[];
  userId: string;
  canRequest: boolean;
  canApprove: boolean;
};

export function TreasuryConsole({
  funds,
  transactions,
  expenses,
  pendingMoney,
  userId,
  canRequest,
  canApprove,
}: TreasuryConsoleProps) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const [pending, setPending] = useState("");
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const verifiedFunds = funds.filter((fund) => fund.verified);

  async function reconcileDonation(donationId: string, form: HTMLFormElement) {
    const data = new FormData(form);
    const operation = `money-${donationId}`;
    setPending(operation);
    setMessage("");
    setError("");
    const { error: actionError } = await supabase.rpc("reconcile_money_donation", {
      p_donation_id: donationId,
      p_fund_id: String(data.get("fund")),
      p_provider_reference_private: String(data.get("provider_reference")),
      p_idempotency_key: crypto.randomUUID(),
    });
    setPending("");
    if (actionError) {
      setError(toOperationalMessage(actionError));
      return;
    }
    setMessage("Aporte conciliado y publicado.");
    router.refresh();
  }

  async function reconcileOtherIncome(form: HTMLFormElement) {
    const data = new FormData(form);
    setPending("reconcile-other");
    setMessage("");
    setError("");
    const { error: actionError } = await supabase.rpc("reconcile_sandbox_payment", {
      p_fund_id: String(data.get("fund")),
      p_amount: Number(data.get("amount")),
      p_provider_reference: `SANDBOX-${crypto.randomUUID()}`,
      p_idempotency_key: crypto.randomUUID(),
    });
    setPending("");
    if (actionError) {
      setError(toOperationalMessage(actionError));
      return;
    }
    setMessage("Ingreso confirmado y conciliado.");
    router.refresh();
  }

  async function requestExpense(form: HTMLFormElement) {
    const data = new FormData(form);
    setPending("request");
    setMessage("");
    setError("");
    const { error: actionError } = await supabase.rpc("request_expense", {
      p_fund_id: String(data.get("fund")),
      p_amount: Number(data.get("amount")),
      p_purpose: String(data.get("purpose")),
    });
    setPending("");
    if (actionError) {
      setError(toOperationalMessage(actionError));
      return;
    }
    setMessage("Solicitud creada. Debe aprobarla una persona diferente.");
    router.refresh();
  }

  async function approve(id: string, decision: "approved" | "rejected") {
    setPending(id);
    setMessage("");
    setError("");
    const { error: actionError } = await supabase.rpc("approve_expense", {
      p_expense_id: id,
      p_decision: decision,
      p_note: "Decisión de tesorería",
    });
    setPending("");
    if (actionError) {
      setError(toOperationalMessage(actionError));
      return;
    }
    setMessage(`Solicitud ${decision === "approved" ? "aprobada" : "rechazada"}.`);
    router.refresh();
  }

  async function pay(id: string) {
    setPending(id);
    setMessage("");
    setError("");
    const { error: actionError } = await supabase.rpc("pay_expense", {
      p_expense_id: id,
      p_idempotency_key: crypto.randomUUID(),
    });
    setPending("");
    if (actionError) {
      setError(toOperationalMessage(actionError));
      return;
    }
    setMessage("Gasto pagado. Saldo actualizado.");
    router.refresh();
  }

  const balance = transactions.reduce(
    (sum, transaction) => sum + (transaction.transaction_type === "credit" ? Number(transaction.amount) : -Number(transaction.amount)),
    0,
  );

  return (
    <>
      {message && <p className="form-success" aria-live="polite">{message}</p>}
      {error && <p className="form-error" role="alert" aria-live="assertive">{error}</p>}

      <section className="ops-kpis">
        <div className="ops-kpi"><span>Fondos verificados</span><strong>{verifiedFunds.length}</strong><small>receptores autorizados</small></div>
        <div className="ops-kpi"><span>Saldo conciliado</span><strong>{currencyFormat.format(balance)}</strong><small>créditos menos débitos</small></div>
        <div className="ops-kpi"><span>Aportes por conciliar</span><strong>{pendingMoney.length}</strong><small>declarados, todavía no públicos</small></div>
        <div className="ops-kpi"><span>Operaciones</span><strong>{transactions.length}</strong><small>historial completo</small></div>
      </section>

      <section className="ops-panel" style={{ marginBottom: 24 }}>
        <header className="ops-panel-header"><div><h2>Aportes económicos pendientes</h2><p>El monto se toma del registro aprobado; tesorería solo aporta el fondo y la referencia privada del soporte.</p></div><span>{pendingMoney.length}</span></header>
        <div className="ops-list">
          {pendingMoney.map((donation) => (
            <article className="ops-row" key={donation.donation_id}>
              <div>
                <h3>{donation.intake_tracking_code} · {donation.attribution}</h3>
                <p>Promesa operacional {donation.tracking_code}</p>
                <p>{currencyFormat.format(Number(donation.declared_amount))} declarados · {formatDate(donation.submitted_at)}</p>
                {canApprove && (
                  <form className="treasury-inline-form" onSubmit={(event) => { event.preventDefault(); void reconcileDonation(donation.donation_id, event.currentTarget); }}>
                    <label>Fondo verificado<select name="fund" required>{verifiedFunds.map((fund) => <option key={fund.id} value={fund.id}>{fund.name}</option>)}</select></label>
                    <label>Referencia del soporte<input name="provider_reference" minLength={4} maxLength={160} placeholder="Número o código del soporte" required /></label>
                    <button className="action-button approve" disabled={pending === `money-${donation.donation_id}` || !verifiedFunds.length}>Conciliar aporte</button>
                  </form>
                )}
              </div>
              <StatusPill status="promised">Por conciliar</StatusPill>
            </article>
          ))}
          {!pendingMoney.length && <p className="ops-empty">No hay aportes económicos aprobados pendientes de conciliación.</p>}
        </div>
      </section>

      <div className="ops-grid">
        <section className="ops-panel">
          <header className="ops-panel-header"><h2>Libro financiero</h2><span>{transactions.length} movimientos</span></header>
          <div className="ops-list">
            {transactions.map((transaction) => <article className="ops-row" key={transaction.id}><div><h3>{transaction.public_reference}</h3><p>{currencyFormat.format(transaction.amount)} · {formatDate(transaction.created_at)}</p></div><StatusPill status={transaction.status}>{transaction.transaction_type === "credit" ? "Ingreso" : "Egreso"}</StatusPill></article>)}
            {!transactions.length && <p className="ops-empty">Aún no hay movimientos conciliados.</p>}
          </div>
        </section>

        <section className="ops-panel">
          <header className="ops-panel-header"><h2>{canApprove ? "Otros ingresos" : "Solicitar gasto"}</h2></header>
          {canApprove ? (
            <form className="form-body" onSubmit={(event) => { event.preventDefault(); void reconcileOtherIncome(event.currentTarget); }}>
              <p className="step-help">Para ingresos que no nacen de un aporte registrado. No los uses para conciliar la cola anterior.</p>
              <div className="field"><label htmlFor="fund-reconcile">Fondo</label><select id="fund-reconcile" name="fund" required>{verifiedFunds.map((fund) => <option key={fund.id} value={fund.id}>{fund.name}</option>)}</select></div>
              <div className="field"><label htmlFor="amount-reconcile">Monto COP</label><input id="amount-reconcile" name="amount" type="number" min="1" required /></div>
              <button className="button button-dark button-block" disabled={pending === "reconcile-other" || !verifiedFunds.length}>Conciliar otro ingreso</button>
            </form>
          ) : canRequest ? (
            <form className="form-body" onSubmit={(event) => { event.preventDefault(); void requestExpense(event.currentTarget); }}>
              <div className="field"><label htmlFor="fund-request">Fondo</label><select id="fund-request" name="fund" required>{verifiedFunds.map((fund) => <option key={fund.id} value={fund.id}>{fund.name}</option>)}</select></div>
              <div className="field"><label htmlFor="amount-request">Monto COP</label><input id="amount-request" name="amount" type="number" min="1" required /></div>
              <div className="field"><label htmlFor="purpose">Finalidad</label><textarea id="purpose" name="purpose" minLength={10} required /></div>
              <button className="button button-dark button-block" disabled={pending === "request" || !verifiedFunds.length}>Enviar a aprobación</button>
            </form>
          ) : <p className="ops-empty">Tu rol es de consulta.</p>}
        </section>
      </div>

      <section className="ops-panel" style={{ marginTop: 24 }}>
        <header className="ops-panel-header"><h2>Solicitudes de gasto</h2><span>{expenses.length}</span></header>
        <div className="ops-list">
          {expenses.map((expense) => (
            <article className="ops-row" key={expense.id}>
              <div>
                <h3>{expense.purpose}</h3>
                <p>{currencyFormat.format(expense.amount)} · {formatDate(expense.created_at)}</p>
                {canApprove && expense.requested_by !== userId && expense.status === "requested" && <div className="action-bar"><button className="action-button approve" disabled={pending === expense.id} onClick={() => void approve(expense.id, "approved")}>Aprobar</button><button className="action-button" disabled={pending === expense.id} onClick={() => void approve(expense.id, "rejected")}>Rechazar</button></div>}
                {canApprove && expense.requested_by !== userId && expense.status === "approved" && <button className="action-button approve" disabled={pending === expense.id} onClick={() => void pay(expense.id)}>Pagar</button>}
              </div>
              <StatusPill status={expense.status} />
            </article>
          ))}
          {!expenses.length && <p className="ops-empty">No hay solicitudes todavía.</p>}
        </div>
      </section>
    </>
  );
}
