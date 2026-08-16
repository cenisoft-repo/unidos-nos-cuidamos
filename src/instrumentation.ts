import type { Instrumentation } from "next";
import { logOperationalEvent, safeOperationalIdentifier } from "@/lib/observability";

export function register() {
  logOperationalEvent("info", { event: "server_started" });
}

export const onRequestError: Instrumentation.onRequestError = (error, request, context) => {
  const digest = typeof error === "object" && error !== null && "digest" in error
    ? safeOperationalIdentifier(String(error.digest)) ?? undefined
    : undefined;

  logOperationalEvent("error", {
    event: "server_error",
    operation: context.routePath,
    method: request.method,
    route_type: context.routeType,
    digest,
  });
};
