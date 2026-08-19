"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { toOperationalMessage } from "@/lib/user-errors";

type Item = { id: string; description: string; quantity: number; unit: string };

/**
 * Respuesta del aliado a una observación (G-028).
 *
 * Permite corregir cantidades y monto, no solo escribir una nota: la observación
 * más frecuente es que la cantidad no coincide con el soporte, y sin esto el
 * aporte quedaba atrapado en «Con observaciones» sin salida.
 *
 * La versión viaja al servidor: si alguien más movió el ingreso mientras este
 * formulario estaba abierto, la RPC lo rechaza en vez de pisar el cambio.
 */
export function IntakeAmendmentForm({
  intakeId,
  version,
  kind,
  declaredAmount,
  items,
  observation,
}: {
  intakeId: string;
  version: number;
  kind: string;
  declaredAmount: number | null;
  items: Item[];
  observation: string | null;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [note, setNote] = useState("");
  const [amount, setAmount] = useState(declaredAmount === null ? "" : String(declaredAmount));
  const [quantities, setQuantities] = useState<Record<string, string>>(
    Object.fromEntries(items.map((item) => [item.id, String(item.quantity)])),
  );
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");

  const changedItems = items.filter((item) => Number(quantities[item.id]) !== item.quantity);
  const amountChanged = kind === "money" && amount !== "" && Number(amount) !== declaredAmount;

  async function submit() {
    setPending(true);
    setError("");
    const supabase = createClient();
    const { error: actionError } = await supabase.rpc("amend_donation_intake", {
      p_intake_id: intakeId,
      p_note: note,
      p_expected_version: version,
      p_items: changedItems.map((item) => ({ item_id: item.id, quantity: Number(quantities[item.id]) })),
      p_declared_amount: amountChanged ? Number(amount) : null,
    });
    setPending(false);
    if (actionError) {
      setError(toOperationalMessage(actionError));
      return;
    }
    setOpen(false);
    setNote("");
    router.refresh();
  }

  if (!open) {
    return (
      <div className="amendment-prompt">
        {observation && (
          <p className="amendment-observation">
            <strong>Observación de verificación:</strong> {observation}
          </p>
        )}
        <button className="button button-outline button-small" onClick={() => setOpen(true)}>
          Responder y corregir
        </button>
      </div>
    );
  }

  return (
    <div className="amendment-form">
      {observation && (
        <p className="amendment-observation">
          <strong>Observación de verificación:</strong> {observation}
        </p>
      )}

      {items.length > 0 && (
        <fieldset className="amendment-items">
          <legend>Cantidades</legend>
          {items.map((item) => (
            <label key={item.id} className="amendment-item">
              <span>
                {item.description}
                <small>
                  Registrado: {item.quantity} {item.unit}
                </small>
              </span>
              <input
                type="number"
                min="0"
                step="any"
                inputMode="decimal"
                value={quantities[item.id] ?? ""}
                aria-label={`Cantidad corregida de ${item.description}`}
                onChange={(event) =>
                  setQuantities((previous) => ({ ...previous, [item.id]: event.target.value }))
                }
              />
            </label>
          ))}
        </fieldset>
      )}

      {kind === "money" && (
        <label className="amendment-item">
          <span>Monto declarado</span>
          <input
            type="number"
            min="0"
            step="any"
            inputMode="decimal"
            value={amount}
            aria-label="Monto declarado corregido"
            onChange={(event) => setAmount(event.target.value)}
          />
        </label>
      )}

      <label className="amendment-note">
        <span>¿Qué corregiste?</span>
        <textarea
          rows={3}
          value={note}
          onChange={(event) => setNote(event.target.value)}
          placeholder="Ej.: cantidad ajustada contra la remisión física 0012"
        />
        <small>
          No incluyas teléfonos, cuentas ni datos de contacto: el registro los rechaza.
        </small>
      </label>

      <div className="action-bar">
        <button
          className="action-button approve"
          disabled={pending || note.trim().length < 10}
          onClick={() => void submit()}
        >
          {pending ? "…" : "Enviar corrección"}
        </button>
        <button className="action-button" disabled={pending} onClick={() => setOpen(false)}>
          Cancelar
        </button>
      </div>

      <p className="amendment-hint">
        {changedItems.length + (amountChanged ? 1 : 0)} dato(s) por corregir. El aporte vuelve a la cola de
        verificación y la versión anterior queda en el historial.
      </p>

      {error && <span className="field-error">{error}</span>}
    </div>
  );
}
