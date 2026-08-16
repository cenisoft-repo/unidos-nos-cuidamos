import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

export async function updateSession(request: NextRequest, requestHeaders?: Headers) {
  const nextInit = requestHeaders ? { request: { headers: requestHeaders } } : { request };
  let response = NextResponse.next(nextInit);
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next(nextInit);
          cookiesToSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
        },
      },
    },
  );
  const { error } = await supabase.auth.getUser();
  if (error?.code === "refresh_token_not_found" || error?.code === "refresh_token_already_used") {
    for (const cookie of request.cookies.getAll()) {
      if (cookie.name.startsWith("sb-") && cookie.name.includes("-auth-token")) {
        request.cookies.delete(cookie.name);
        response.cookies.set(cookie.name, "", { path: "/", maxAge: 0 });
      }
    }
  }
  return response;
}
