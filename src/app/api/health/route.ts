import { NextResponse } from "next/server";
import { observeRequest } from "@/lib/observability";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const observation = observeRequest(request, "health");

  try {
    const supabase = await createClient();
    const { error } = await supabase.from("emergency_events").select("id", { count: "exact", head: true });
    const response = NextResponse.json(
      {
        status: error ? "degraded" : "ok",
        checks: { database: error ? "unavailable" : "connected" },
        timestamp: new Date().toISOString(),
      },
      {
        status: error ? 503 : 200,
        headers: {
          "Cache-Control": "no-store",
          ...(error ? { "Retry-After": "30" } : {}),
        },
      },
    );
    return observation.complete(response, error ? "database_unavailable" : "healthy");
  } catch {
    return observation.complete(
      NextResponse.json(
        {
          status: "degraded",
          checks: { database: "unavailable" },
          timestamp: new Date().toISOString(),
        },
        { status: 503, headers: { "Cache-Control": "no-store", "Retry-After": "30" } },
      ),
      "health_check_failed",
    );
  }
}
