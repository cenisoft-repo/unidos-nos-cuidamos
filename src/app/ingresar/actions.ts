"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function login(formData: FormData) {
  const supabase = await createClient();
  const email = String(formData.get("email") ?? "");
  const password = String(formData.get("password") ?? "");
  const next = String(formData.get("next") ?? "/operaciones");
  const safeNext = next.startsWith("/") && !next.startsWith("//") ? next : "/operaciones";
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) redirect(`/ingresar?error=${encodeURIComponent("Correo o contraseña inválidos")}&next=${encodeURIComponent(safeNext)}`);
  redirect(safeNext);
}

export async function logout() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/");
}
