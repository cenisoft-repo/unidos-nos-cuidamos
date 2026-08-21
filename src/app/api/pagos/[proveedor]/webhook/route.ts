import { createClient } from "@supabase/supabase-js";
import { logOperationalEvent } from "@/lib/observability";
import { CABECERA_FIRMA, leerAviso } from "@/lib/payments";
import { firmaValida, secretoDelCanal } from "@/lib/payments-server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * Vuelta del proveedor sobre una intención de cobro.
 *
 * Dos comprobaciones independientes, y ninguna sobra: la firma HMAC del cuerpo demuestra
 * que el mensaje no fue alterado en el camino, y el secreto que se envía a PostgreSQL
 * demuestra ante la base que quien llama conoce el canal. La base compara ese secreto con
 * la huella que guardó al registrarlo; nunca lo almacena.
 *
 * Esta ruta NO usa una clave de administración. Habla con la API con la misma clave
 * publicable que el navegador, y lo que la autoriza a escribir es el secreto del canal
 * verificado dentro de la transacción. Una clave `service_role` en el servidor web sería un
 * poder mucho mayor del que este recorrido necesita.
 *
 * Las respuestas no distinguen «referencia inexistente» de «secreto equivocado»: quien
 * pruebe a ciegas no obtiene ninguna pista.
 */
export async function POST(request: Request, contexto: { params: Promise<{ proveedor: string }> }) {
  const { proveedor } = await contexto.params;
  const canal = proveedor.toLowerCase();
  const secreto = secretoDelCanal(canal);
  const cuerpoCrudo = await request.text();

  function rechazar(motivo: string, estado: number) {
    logOperationalEvent("warn", {
      event: "payment_webhook_rejected",
      operation: `pagos/${canal}`,
      outcome: motivo,
    });
    return Response.json({ error: "Aviso de pago no aceptado" }, { status: estado, headers: { "Cache-Control": "no-store" } });
  }

  if (!secreto) return rechazar("canal_sin_secreto", 404);
  if (!firmaValida(cuerpoCrudo, secreto, request.headers.get(CABECERA_FIRMA))) return rechazar("firma_invalida", 401);

  let aviso: ReturnType<typeof leerAviso> = null;
  try {
    aviso = leerAviso(JSON.parse(cuerpoCrudo));
  } catch {
    aviso = null;
  }
  if (!aviso) return rechazar("aviso_malformado", 400);

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const clavePublicable = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !clavePublicable) return rechazar("entorno_incompleto", 503);

  const supabase = createClient(url, clavePublicable, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await supabase.rpc("confirm_payment_intent", {
    p_reference: aviso.referencia,
    p_provider_key: canal,
    p_webhook_secret: secreto,
    p_outcome: aviso.resultado,
    p_provider_reference: aviso.referenciaProveedor,
    p_amount: aviso.monto,
    p_note: aviso.nota,
  });

  if (error) return rechazar(error.code ?? "rechazado_por_la_base", 401);

  const resultado = (Array.isArray(data) ? data[0] : data) as { intent_status: string; was_duplicate: boolean } | null;
  logOperationalEvent("info", {
    event: "payment_webhook_accepted",
    operation: `pagos/${canal}`,
    outcome: resultado?.intent_status ?? "desconocido",
  });
  // Se devuelve el estado y nada más: ni importes, ni aporte, ni organización.
  return Response.json(
    { estado: resultado?.intent_status ?? "desconocido", repetido: resultado?.was_duplicate ?? false },
    { headers: { "Cache-Control": "no-store" } },
  );
}
