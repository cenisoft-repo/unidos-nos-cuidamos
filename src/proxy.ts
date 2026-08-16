import { type NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/proxy";
import { contentSecurityPolicy } from "@/lib/security-headers";

export async function proxy(request: NextRequest) {
  const nonce = crypto.randomUUID().replaceAll("-", "");
  const policy = contentSecurityPolicy(nonce, { development: process.env.NODE_ENV !== "production" });

  // Next.js firma sus propios scripts cuando encuentra la política en la petición.
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-nonce", nonce);
  requestHeaders.set("content-security-policy", policy);

  const response = await updateSession(request, requestHeaders);
  response.headers.set("content-security-policy", policy);
  return response;
}

export const config = {
  // sw.js queda fuera junto al resto de estáticos: refrescar la sesión ahí
  // añadiría una consulta de autenticación por cada descarga del trabajador.
  matcher: ["/((?!_next/static|_next/image|favicon.ico|sw.js|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)"],
};
