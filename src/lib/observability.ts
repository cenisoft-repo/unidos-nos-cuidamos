type LogLevel = "info" | "warn" | "error";

type OperationalEvent = {
  event: string;
  request_id?: string;
  operation?: string;
  method?: string;
  status?: number;
  outcome?: string;
  duration_ms?: number;
  route_type?: string;
  digest?: string;
};

export function safeOperationalIdentifier(value: string | null | undefined) {
  const normalized = value?.trim().slice(0, 128) ?? "";
  return /^[A-Za-z0-9._:-]+$/.test(normalized) ? normalized : null;
}

export function logOperationalEvent(level: LogLevel, details: OperationalEvent) {
  const entry = JSON.stringify({
    service: "ruta-solidaria-web",
    environment: process.env.VERCEL_ENV ?? process.env.NODE_ENV ?? "local",
    timestamp: new Date().toISOString(),
    ...details,
  });
  console[level](entry);
}

export function observeRequest(request: Request, operation: string) {
  const requestId = safeOperationalIdentifier(request.headers.get("x-request-id"))
    ?? safeOperationalIdentifier(request.headers.get("x-vercel-id"))
    ?? crypto.randomUUID();
  const startedAt = performance.now();

  return {
    requestId,
    complete(response: Response, outcome = response.ok ? "ok" : "rejected") {
      const duration = Math.round((performance.now() - startedAt) * 10) / 10;
      const level: LogLevel = response.status >= 500 ? "error" : response.status >= 400 ? "warn" : "info";
      logOperationalEvent(level, {
        event: "request_complete",
        request_id: requestId,
        operation,
        method: request.method,
        status: response.status,
        outcome,
        duration_ms: duration,
      });
      response.headers.set("X-Request-Id", requestId);
      response.headers.set("Server-Timing", `app;dur=${duration}`);
      return response;
    },
  };
}
