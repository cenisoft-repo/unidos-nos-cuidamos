import { describe, expect, it } from "vitest";
import { MAX_INTAKE_PHOTO_BYTES, validateIntakePhotos } from "./intake-photo-evidence";

const photo = (overrides: Partial<{ name: string; type: string; size: number }> = {}) => ({
  name: "evidencia.png",
  type: "image/png",
  size: 1024,
  ...overrides,
});

describe("validateIntakePhotos", () => {
  it("acepta hasta tres fotografías JPG o PNG dentro del límite", () => {
    expect(validateIntakePhotos([photo(), photo({ type: "image/jpeg" }), photo()])).toBe("");
  });

  it("rechaza más de tres fotografías", () => {
    expect(validateIntakePhotos([photo(), photo(), photo(), photo()])).toMatch(/máximo 3/);
  });

  it("rechaza archivos que no son imagen o superan 5 MB", () => {
    expect(validateIntakePhotos([photo({ type: "application/pdf" })])).toMatch(/JPG o PNG/);
    expect(validateIntakePhotos([photo({ size: MAX_INTAKE_PHOTO_BYTES + 1 })])).toMatch(/5 MB/);
  });
});
