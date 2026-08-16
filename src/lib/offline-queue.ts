import { z } from "zod";

const offlineReceptionSchema = z.object({
  id: z.string().uuid(),
  donationItemId: z.string().uuid(),
  locationId: z.string().uuid(),
  accepted: z.number().finite().nonnegative(),
  rejected: z.number().finite().nonnegative(),
  condition: z.literal("sellado"),
  createdAt: z.string().datetime({ offset: true }),
}).strict().refine((operation) => operation.accepted + operation.rejected > 0, {
  message: "La operación debe registrar una cantidad",
});

export type OfflineReception = z.infer<typeof offlineReceptionSchema>;

const KEY = "ruta-solidaria:offline-receptions:v1";
const MAX_QUEUE_SIZE = 50;
const MAX_AGE_MS = 72 * 60 * 60 * 1000;

function isCurrent(operation: OfflineReception) {
  const createdAt = Date.parse(operation.createdAt);
  return Number.isFinite(createdAt)
    && createdAt <= Date.now() + 5 * 60 * 1000
    && createdAt >= Date.now() - MAX_AGE_MS;
}

export function readOfflineReceptions(): OfflineReception[] {
  if (typeof window === "undefined") return [];
  try {
    const parsed = JSON.parse(window.localStorage.getItem(KEY) ?? "[]");
    if (!Array.isArray(parsed)) return [];
    return parsed.flatMap((candidate) => {
      const result = offlineReceptionSchema.safeParse(candidate);
      return result.success && isCurrent(result.data) ? [result.data] : [];
    }).slice(-MAX_QUEUE_SIZE);
  } catch {
    return [];
  }
}

export function enqueueOfflineReception(operation: OfflineReception) {
  const validated = offlineReceptionSchema.parse(operation);
  const queue = readOfflineReceptions();
  if (queue.some((item) => item.id === validated.id)) return queue.length;
  if (queue.length >= MAX_QUEUE_SIZE) throw new Error("La cola local alcanzó su capacidad segura");
  queue.push(validated);
  window.localStorage.setItem(KEY, JSON.stringify(queue));
  return queue.length;
}

export function removeOfflineReception(id: string) {
  window.localStorage.setItem(KEY, JSON.stringify(readOfflineReceptions().filter((item) => item.id !== id)));
}
