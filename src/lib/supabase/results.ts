import { logOperationalEvent } from "@/lib/observability";

type SupabaseErrorLike = {
  code?: string;
  message: string;
};

export type SupabaseResultLike = {
  error: SupabaseErrorLike | null;
};

export function firstSupabaseError(results: readonly SupabaseResultLike[]) {
  return results.find((result) => result.error)?.error ?? null;
}

export function assertSupabaseSuccess(context: string, results: readonly SupabaseResultLike[]) {
  const error = firstSupabaseError(results);
  if (!error) return;

  throw new Error(`[supabase:${context}] ${error.code ?? "unknown_error"}`);
}

export function databaseUnavailableResponse(context: string, error: SupabaseErrorLike) {
  logOperationalEvent("error", {
    event: "database_query_unavailable",
    operation: context,
    outcome: error.code ?? "unknown_error",
  });
  return Response.json(
    { error: "No fue posible consultar la información en este momento. Intenta de nuevo en unos minutos." },
    {
      status: 503,
      headers: {
        "Cache-Control": "no-store",
        "Retry-After": "30",
      },
    },
  );
}
