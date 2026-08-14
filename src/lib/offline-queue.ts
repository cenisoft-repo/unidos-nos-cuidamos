export type OfflineReception = {
  id: string;
  donationItemId: string;
  locationId: string;
  accepted: number;
  rejected: number;
  condition: string;
  createdAt: string;
};

const KEY = "ruta-solidaria:offline-receptions:v1";

export function readOfflineReceptions(): OfflineReception[] {
  if (typeof window === "undefined") return [];
  try {
    const parsed = JSON.parse(window.localStorage.getItem(KEY) ?? "[]");
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export function enqueueOfflineReception(operation: OfflineReception) {
  const queue = readOfflineReceptions();
  if (!queue.some((item) => item.id === operation.id)) queue.push(operation);
  window.localStorage.setItem(KEY, JSON.stringify(queue));
}

export function removeOfflineReception(id: string) {
  window.localStorage.setItem(KEY, JSON.stringify(readOfflineReceptions().filter((item) => item.id !== id)));
}
