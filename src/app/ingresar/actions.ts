"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { resolveSafeNext } from "@/lib/safe-redirect";

export async function login(formData: FormData) {
  const supabase = await createClient();
  const email = String(formData.get("email") ?? "");
  const password = String(formData.get("password") ?? "");
  // G-062: la comprobación vive en su módulo y se resuelve con el analizador de URL, no con
  // `startsWith`. La que había aquí aceptaba `/\evil.example`, que el navegador lleva a otro
  // dominio: un enlace de ingreso podía terminar en un sitio ajeno con la contraseña ya
  // escrita.
  const safeNext = resolveSafeNext(formData.get("next"));
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) redirect(`/ingresar?error=${encodeURIComponent("Correo o contraseña inválidos")}&next=${encodeURIComponent(safeNext)}`);
  redirect(safeNext);
}

export async function logout() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/");
}
