"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Banknote, HandCoins, ShieldCheck } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { toOperationalMessage } from "@/lib/user-errors";
import { currencyFormat, formatDate } from "@/lib/format";
import { StatusPill } from "./status-pill";

type Fund = { id: string; name: string; verified: boolean; currency: string };
type Tx = { id: string; transaction_type: string; amount: number; status: string; public_reference: string; created_at: string };
type Expense = { id: string; amount: number; purpose: string; status: string; requested_by: string; created_at: string };
type PendingMoney = { donation_id: string; tracking_code: string; intake_tracking_code: string; declared_amount: number; currency: string; attribution: string; submitted_at: string };
type Ledger = { balance: number; reconciled_credits: number; reconciled_debits: number; movement_count: number };
type Decision = { expense_request_id: string; decision: string; note: string; decided_at: string };

type TreasuryConsoleProps = {
  funds: Fund[];
  transactions: Tx[];
  expenses: Expense[];
  pendingMoney: PendingMoney[];
  ledger: Ledger;
  decisions: Decision[];
  userId: string;
  canRequest: boolean;
  canApprove: boolean;
};

export function TreasuryConsole({
  funds,
  transactions,
  expenses,
  pendingMoney,
  ledger,
  decisions,
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
  const awaitingApproval = expenses.filter((expense) => expense.status === "requested").length;
  const awaitingPayment = expenses.filter((expense) => expense.status === "approved").length;
  const ownAwaiting = expenses.filter((expense) => expense.requested_by === userId && expense.status === "requested").length;

  function start(operation: string) {
    setPending(operation);
    setMessage("");
    setError("");
  }

  function finish(actionError: { message: string } | null, success: string) {
    setPending("");
    if (actionError) {
      setError(toOperationalMessage(actionError as never));
      return;
    }
    setMessage(success);
    router.refresh();
  }

  async function reconcileDonation(donationId: string, form: HTMLFormElement) {
    const data = new FormData(form);
    start(`money-${donationId}`);
    const { error: actionError } = await supabase.rpc("reconcile_money_donation", {
      p_donation_id: donationId,
      p_fund_id: String(data.get("fund")),
      p_provider_reference_private: String(data.get("provider_reference")).trim(),
      p_idempotency_key: crypto.randomUUID(),
    });
    finish(actionError, "Aporte conciliado. El monto ya es público; la referencia del soporte no.");
  }

  async function reconcileOtherIncome(form: HTMLFormElement) {
    const data = new FormData(form);
    start("reconcile-other");
    const { error: actionError } = await supabase.rpc("reconcile_sandbox_payment", {
      p_fund_id: String(data.get("fund")),
      p_amount: Number(data.get("amount")),
      // La referencia la escribe quien concilia: un identificador generado al azar
      // dejaría el ingreso sin nada contra qué contrastarlo en una auditoría.
      p_provider_reference: String(data.get("reference")).trim(),
      p_idempotency_key: crypto.randomUUID(),
    });
    finish(actionError, "Ingreso conciliado contra la referencia registrada.");
  }

  async function requestExpense(form: HTMLFormElement) {
    const data = new FormData(form);
    start("request");
    const { error: actionError } = await supabase.rpc("request_expense", {
      p_fund_id: String(data.get("fund")),
      p_amount: Number(data.get("amount")),
      p_purpose: String(data.get("purpose")).trim(),
    });
    finish(actionError, "Solicitud creada. Debe aprobarla una persona distinta de quien la pidió.");
  }

  async function decide(id: string, decision: "approved" | "rejected", form: HTMLFormElement) {
    const note = String(new FormData(form).get("note") ?? "").trim();
    start(id);
    const { error: actionError } = await supabase.rpc("approve_expense", {
      p_expense_id: id,
      p_decision: decision,
      p_note: note,
    });
    finish(actionError, decision === "approved"
      ? "Solicitud aprobada con su justificación registrada."
      : "Solicitud rechazada con su justificación registrada.");
  }

  async function pay(id: string) {
    start(id);
    const { error: actionError } = await supabase.rpc("pay_expense", {
      p_expense_id: id,
      p_idempotency_key: crypto.randomUUID(),
    });
    finish(actionError, "Gasto pagado. El saldo del libro quedó actualizado.");
  }

  return (
    <>
      {/* Las cuatro etapas del dinero, con la misma lógica de cola que usa bodega. */}
      <nav className="warehouse-steps" aria-label="Etapas de tesorería">
        <a href="#conciliar"><span>01</span> Conciliar <strong>{pendingMoney.length}</strong></a>
        <a href="#solicitar"><span>02</span> Solicitar <strong>{ownAwaiting}</strong></a>
        <a href="#solicitudes"><span>03</span> Aprobar <strong>{awaitingApproval}</strong></a>
        <a href="#solicitudes"><span>04</span> Pagar <strong>{awaitingPayment}</strong></a>
      </nav>

      {message && <p className="form-success" aria-live="polite">{message}</p>}
      {error && <p className="form-error" role="alert" aria-live="assertive">{error}</p>}

      <section className="ops-kpis">
        <div className="ops-kpi"><span>Fondos verificados</span><strong>{verifiedFunds.length}</strong><small>receptores autorizados</small></div>
        <div className="ops-kpi"><span>Saldo conciliado</span><strong>{currencyFormat.format(Number(ledger.balance))}</strong><small>{ledger.movement_count} movimientos del libro completo</small></div>
        <div className="ops-kpi"><span>Ingresos conciliados</span><strong>{currencyFormat.format(Number(ledger.reconciled_credits))}</strong><small>egresos: {currencyFormat.format(Number(ledger.reconciled_debits))}</small></div>
        <div className="ops-kpi"><span>Aportes por conciliar</span><strong>{pendingMoney.length}</strong><small>declarados, todavía no públicos</small></div>
      </section>

      <section className="ops-panel" id="conciliar" style={{ marginBottom: 24 }}>
        <header className="ops-panel-header"><div><h2><Banknote size={18} /> Aportes económicos por conciliar</h2><p>El monto viene del registro ya aprobado. Tesorería solo elige el fondo y anota contra qué soporte lo verificó.</p></div><span>{pendingMoney.length}</span></header>
        <div className="ops-list">
          {pendingMoney.map((donation) => (
            <article className="ops-row" key={donation.donation_id}>
              <div>
                <h3>{donation.intake_tracking_code} · {donation.attribution}</h3>
                <p>Promesa operacional {donation.tracking_code}</p>
                <p>{currencyFormat.format(Number(donation.declared_amount))} declarados · reportado {formatDate(donation.submitted_at)}</p>
                {canApprove ? (
                  <form className="treasury-inline-form" onSubmit={(event) => { event.preventDefault(); void reconcileDonation(donation.donation_id, event.currentTarget); }}>
                    <label>Fondo verificado<select name="fund" required>{verifiedFunds.map((fund) => <option key={fund.id} value={fund.id}>{fund.name}</option>)}</select></label>
                    <label>Referencia del soporte<input name="provider_reference" minLength={4} maxLength={160} placeholder="Número del comprobante" required /></label>
                    <button className="action-button approve" disabled={pending === `money-${donation.donation_id}` || !verifiedFunds.length}>Conciliar aporte</button>
                  </form>
                ) : (
                  <p className="ops-inline-note">Solo tesorería con rol de aprobación puede conciliar. Esta vista es de consulta.</p>
                )}
              </div>
              <StatusPill status="promised">Por conciliar</StatusPill>
            </article>
          ))}
          {!pendingMoney.length && <p className="ops-empty">No hay aportes económicos aprobados esperando conciliación.</p>}
        </div>
      </section>

      <div className="ops-grid">
        {/* Los dos formularios son independientes del rol contrario: quien tiene ambos
            permisos ve los dos, en lugar de perder uno por una condición excluyente. */}
        {canRequest && (
          <section className="ops-panel" id="solicitar">
            <header className="ops-panel-header"><div><h2><HandCoins size={17} /> Solicitar un gasto</h2><p>Queda pendiente hasta que otra persona lo apruebe.</p></div></header>
            <form className="form-body" onSubmit={(event) => { event.preventDefault(); void requestExpense(event.currentTarget); }}>
              <div className="field"><label htmlFor="fund-request">Fondo</label><select id="fund-request" name="fund" required>{verifiedFunds.map((fund) => <option key={fund.id} value={fund.id}>{fund.name}</option>)}</select></div>
              <div className="field"><label htmlFor="amount-request">Monto COP</label><input id="amount-request" name="amount" type="number" min="1" required /></div>
              <div className="field"><label htmlFor="purpose">Finalidad</label><textarea id="purpose" name="purpose" minLength={10} maxLength={500} placeholder="Para qué es el gasto y contra qué necesidad responde" required /><small>Queda en el historial de la solicitud.</small></div>
              <button className="button button-dark button-block" disabled={pending === "request" || !verifiedFunds.length}>Enviar a aprobación</button>
            </form>
          </section>
        )}

        {canApprove && (
          <section className="ops-panel">
            <header className="ops-panel-header"><div><h2>Registrar otro ingreso</h2><p>Solo para ingresos que no nacen de un aporte registrado. Los de la cola de arriba se concilian allí.</p></div></header>
            <form className="form-body" onSubmit={(event) => { event.preventDefault(); void reconcileOtherIncome(event.currentTarget); }}>
              <div className="field"><label htmlFor="fund-reconcile">Fondo</label><select id="fund-reconcile" name="fund" required>{verifiedFunds.map((fund) => <option key={fund.id} value={fund.id}>{fund.name}</option>)}</select></div>
              <div className="field"><label htmlFor="amount-reconcile">Monto COP</label><input id="amount-reconcile" name="amount" type="number" min="1" required /></div>
              <div className="field"><label htmlFor="reference-reconcile">Referencia del soporte</label><input id="reference-reconcile" name="reference" minLength={4} maxLength={160} placeholder="Número del comprobante" required /><small>Sin referencia el ingreso no puede contrastarse en una auditoría.</small></div>
              <button className="button button-dark button-block" disabled={pending === "reconcile-other" || !verifiedFunds.length}>Conciliar ingreso</button>
            </form>
          </section>
        )}

        {!canRequest && !canApprove && (
          <section className="ops-panel">
            <header className="ops-panel-header"><div><h2>Vista de consulta</h2></div></header>
            <p className="ops-empty">Tu rol permite revisar el libro y las solicitudes, no crearlas ni decidirlas. Es la separación de funciones que exige el control financiero.</p>
          </section>
        )}

        <section className="ops-panel">
          <header className="ops-panel-header"><div><h2>Libro financiero</h2><p>Movimientos conciliados, del más reciente al más antiguo.</p></div><span>{transactions.length} de {ledger.movement_count}</span></header>
          <div className="ops-list">
            {transactions.map((transaction) => <article className="ops-row" key={transaction.id}><div><h3>{transaction.public_reference}</h3><p>{currencyFormat.format(transaction.amount)} · {formatDate(transaction.created_at)}</p></div><StatusPill status={transaction.status}>{transaction.transaction_type === "credit" ? "Ingreso" : "Egreso"}</StatusPill></article>)}
            {!transactions.length && <p className="ops-empty">Aún no hay movimientos conciliados.</p>}
          </div>
        </section>
      </div>

      <section className="ops-panel" id="solicitudes" style={{ marginTop: 24 }}>
        <header className="ops-panel-header"><div><h2>Solicitudes de gasto</h2><p>Aprobar y pagar exigen una persona distinta de quien solicitó.</p></div><span>{awaitingApproval} por aprobar · {awaitingPayment} por pagar</span></header>
        <div className="ops-list">
          {expenses.map((expense) => {
            const isOwn = expense.requested_by === userId;
            const history = decisions.filter((entry) => entry.expense_request_id === expense.id);
            return (
              <article className="ops-row" key={expense.id}>
                <div>
                  <h3>{expense.purpose}</h3>
                  <p>{currencyFormat.format(expense.amount)} · solicitado {formatDate(expense.created_at)}{isOwn ? " · lo pediste tú" : ""}</p>
                  {/* La justificación que se exige al decidir tiene que poder leerse después. */}
                  {history.map((entry) => (
                    <p className="ops-decision-note" key={`${entry.expense_request_id}-${entry.decided_at}`}>
                      <strong>{entry.decision === "approved" ? "Aprobada" : "Rechazada"} el {formatDate(entry.decided_at)}:</strong> {entry.note}
                    </p>
                  ))}
                  {canApprove && isOwn && ["requested", "approved"].includes(expense.status) && (
                    <p className="ops-inline-note"><ShieldCheck size={14} /> No puedes decidir sobre tu propia solicitud. Debe resolverla otra persona con rol de aprobación.</p>
                  )}
                  {canApprove && !isOwn && expense.status === "requested" && (
                    <form className="treasury-inline-form" onSubmit={(event) => { event.preventDefault(); void decide(expense.id, (((event.nativeEvent as SubmitEvent).submitter as HTMLButtonElement)?.value === "rejected" ? "rejected" : "approved"), event.currentTarget); }}>
                      <label>Justificación de la decisión<input name="note" minLength={4} maxLength={500} placeholder="Queda en el historial de aprobación" required /></label>
                      <button className="action-button approve" value="approved" disabled={pending === expense.id}>Aprobar</button>
                      <button className="action-button" value="rejected" disabled={pending === expense.id}>Rechazar</button>
                    </form>
                  )}
                  {canApprove && !isOwn && expense.status === "approved" && (
                    <button className="action-button approve" disabled={pending === expense.id} onClick={() => void pay(expense.id)}>Registrar el pago</button>
                  )}
                </div>
                <StatusPill status={expense.status} />
              </article>
            );
          })}
          {!expenses.length && <p className="ops-empty">No hay solicitudes de gasto todavía.</p>}
        </div>
      </section>
    </>
  );
}
