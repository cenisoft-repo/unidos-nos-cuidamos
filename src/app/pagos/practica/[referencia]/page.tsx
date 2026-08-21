import type { Metadata } from "next";
import Link from "next/link";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { AlertTriangle, ShieldCheck } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { assertSupabaseSuccess } from "@/lib/supabase/results";
import { currencyFormat } from "@/lib/format";
import { CABECERA_FIRMA, CANAL_PRACTICA } from "@/lib/payments";
import { firmar, secretoDelCanal } from "@/lib/payments-server";

export const metadata: Metadata = { title: "Pasarela de práctica" };
export const dynamic = "force-dynamic";

/**
 * La «pasarela» del canal de práctica.
 *
 * No es una maqueta: firma su aviso con el mismo secreto y lo envía al mismo webhook que
 * usaría un proveedor real, así que el recorrido que se prueba aquí —intención, cobro,
 * aviso firmado, conciliación— es el que se va a operar. Lo único simulado es que nadie
 * paga nada.
 */
/**
 * A dónde envía su aviso la pasarela de práctica: a esta misma instancia.
 *
 * En local y en las pruebas el puerto cambia —la suite levanta su propio servidor—, así que
 * el destino sale de la cabecera `host`... pero solo si es loopback. Con cualquier otro host
 * se usa la URL declarada del despliegue: una cabecera `Host` falsificada no puede desviar
 * un mensaje firmado hacia un servidor ajeno.
 */
async function origenPropio() {
  const declarada = process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000";
  const host = (await headers()).get("host") ?? "";
  const esLoopback = /^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/.test(host);
  return esLoopback ? `http://${host}` : declarada;
}

async function avisarResultado(formData: FormData) {
  "use server";
  const referencia = String(formData.get("referencia") ?? "");
  const resultado = formData.get("resultado") === "confirmed" ? "confirmed" : "failed";
  const monto = Number(formData.get("monto") ?? 0);

  const secreto = secretoDelCanal(CANAL_PRACTICA);
  if (!secreto) redirect(`/pagos/practica/${encodeURIComponent(referencia)}?estado=sin-canal`);
  const base = await origenPropio();

  const cuerpo = JSON.stringify({
    referencia,
    resultado,
    referencia_proveedor: `PRACTICA-${referencia.slice(-8)}`,
    monto,
    nota: resultado === "failed" ? "Rechazo simulado en el canal de práctica" : null,
  });

  const respuesta = await fetch(`${base}/api/pagos/${CANAL_PRACTICA}/webhook`, {
    method: "POST",
    headers: { "content-type": "application/json", [CABECERA_FIRMA]: firmar(cuerpo, secreto) },
    body: cuerpo,
    cache: "no-store",
  });

  const estado = respuesta.ok ? resultado : "rechazado";
  redirect(`/pagos/practica/${encodeURIComponent(referencia)}?estado=${estado}`);
}

export default async function PracticeCheckoutPage({
  params,
  searchParams,
}: {
  params: Promise<{ referencia: string }>;
  searchParams: Promise<{ estado?: string }>;
}) {
  const { referencia } = await params;
  const { estado } = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect(`/ingresar?next=${encodeURIComponent(`/pagos/practica/${referencia}`)}`);

  const intentResult = await supabase
    .from("payment_intents")
    .select("reference,amount,currency,status,failure_reason,payment_providers(display_name,sandbox,provider_key)")
    .eq("reference", referencia)
    .maybeSingle();
  assertSupabaseSuccess("pasarela_practica", [intentResult]);
  const intent = intentResult.data as unknown as {
    reference: string;
    amount: number;
    currency: string;
    status: string;
    failure_reason: string | null;
    payment_providers: { display_name: string; sandbox: boolean; provider_key: string } | null;
  } | null;

  if (!intent) {
    return (
      <main className="form-shell">
        <section className="form-card">
          <h1>Cobro no encontrado</h1>
          <p>Esa referencia no corresponde a ningún cobro que puedas ver.</p>
          <Link className="button button-outline" href="/operaciones">Volver</Link>
        </section>
      </main>
    );
  }

  const pagado = intent.status === "confirmed";
  const fallido = intent.status === "failed";

  return (
    <main className="form-shell">
      <section className="form-card">
        <p className="eyebrow">{intent.payment_providers?.display_name ?? "Canal de recaudo"}</p>
        <h1>Pasarela de práctica</h1>
        <div className="ops-alert">
          <AlertTriangle size={17} />
          <span><strong>Aquí no se cobra dinero.</strong> Este canal simula la respuesta de un proveedor para que el recorrido completo pueda probarse sin mover un peso.</span>
        </div>

        <dl className="ops-request-facts">
          <div><dt>Referencia del cobro</dt><dd>{intent.reference}</dd></div>
          <div><dt>Valor</dt><dd>{currencyFormat.format(Number(intent.amount))} {intent.currency}</dd></div>
          <div><dt>Estado</dt><dd>{pagado ? "Confirmado por el proveedor" : fallido ? "Rechazado" : "Esperando el pago"}</dd></div>
        </dl>

        {fallido && intent.failure_reason && <p className="form-notice" role="status">{intent.failure_reason}</p>}
        {pagado && (
          <p className="form-success" role="status">
            El proveedor confirmó el cobro. Todavía no es saldo: tesorería tiene que conciliarlo contra el extracto.
          </p>
        )}

        {!pagado && (
          <form action={avisarResultado} className="ops-actions">
            <input type="hidden" name="referencia" value={intent.reference} />
            <input type="hidden" name="monto" value={String(intent.amount)} />
            <button className="button button-dark" name="resultado" value="confirmed">Simular pago aprobado</button>
            <button className="button button-outline" name="resultado" value="failed">Simular pago rechazado</button>
          </form>
        )}

        {estado === "rechazado" && <p className="form-notice" role="status">El aviso del canal no fue aceptado. Revisa el secreto configurado para la pasarela.</p>}

        <p className="ticket-legal">
          <ShieldCheck size={15} /> La plataforma no recibe ni guarda datos de tarjeta, cuenta o clave: eso ocurre en el proveedor y aquí solo llega el resultado.
        </p>
        <Link className="button button-outline" href="/operaciones">Volver al centro operativo</Link>
      </section>
    </main>
  );
}
