import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { enqueueOfflineReception, readOfflineReceptions, removeOfflineReception } from "./offline-queue";

const validOperation = {
  id: "11111111-1111-4111-8111-111111111111",
  donationItemId: "22222222-2222-4222-8222-222222222222",
  locationId: "33333333-3333-4333-8333-333333333333",
  accepted: 10,
  rejected: 0,
  condition: "sellado" as const,
  createdAt: "2026-08-15T12:00:00.000Z",
};

describe("cola offline de recepción", () => {
  beforeEach(() => {
    window.localStorage.clear();
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-08-15T13:00:00.000Z"));
  });

  afterEach(() => vi.useRealTimers());

  it("conserva únicamente el contrato mínimo sin PII", () => {
    expect(enqueueOfflineReception(validOperation)).toBe(1);
    expect(readOfflineReceptions()).toEqual([validOperation]);
    expect(window.localStorage.getItem("ruta-solidaria:offline-receptions:v1")).not.toContain("email");
  });

  it("descarta cargas alteradas, campos adicionales y operaciones vencidas", () => {
    window.localStorage.setItem("ruta-solidaria:offline-receptions:v1", JSON.stringify([
      { ...validOperation, email: "no-debe-guardarse@example.invalid" },
      { ...validOperation, id: "44444444-4444-4444-8444-444444444444", createdAt: "2026-08-10T12:00:00.000Z" },
      { ...validOperation, id: "no-es-uuid" },
    ]));
    expect(readOfflineReceptions()).toEqual([]);
  });

  it("evita duplicados y permite retirar una operación sincronizada", () => {
    enqueueOfflineReception(validOperation);
    expect(enqueueOfflineReception(validOperation)).toBe(1);
    removeOfflineReception(validOperation.id);
    expect(readOfflineReceptions()).toEqual([]);
  });

  it("impide crecer más allá de cincuenta operaciones", () => {
    for (let index = 0; index < 50; index += 1) {
      enqueueOfflineReception({
        ...validOperation,
        id: `00000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
      });
    }
    expect(() => enqueueOfflineReception({ ...validOperation, id: "ffffffff-ffff-4fff-8fff-ffffffffffff" })).toThrow("capacidad segura");
  });
});
