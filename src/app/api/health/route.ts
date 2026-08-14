import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET() {
  const supabase = await createClient();
  const { error } = await supabase.from("emergency_events").select("id", { count: "exact", head: true });
  return NextResponse.json({ status: error ? "degraded" : "ok", database: error ? "unavailable" : "connected", timestamp: new Date().toISOString() }, { status: error ? 503 : 200 });
}
