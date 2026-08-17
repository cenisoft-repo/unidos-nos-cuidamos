export const MAX_INTAKE_PHOTOS = 3;
export const MAX_INTAKE_PHOTO_BYTES = 5 * 1024 * 1024;
export const INTAKE_PHOTO_MIME_TYPES = ["image/jpeg", "image/png"] as const;

type IntakePhotoCandidate = {
  name: string;
  type: string;
  size: number;
};

export function validateIntakePhotos(files: readonly IntakePhotoCandidate[]): string {
  if (files.length > MAX_INTAKE_PHOTOS) {
    return `Puedes adjuntar máximo ${MAX_INTAKE_PHOTOS} fotografías.`;
  }
  if (files.some((file) => !INTAKE_PHOTO_MIME_TYPES.includes(file.type as (typeof INTAKE_PHOTO_MIME_TYPES)[number]))) {
    return "Las fotografías deben estar en formato JPG o PNG.";
  }
  if (files.some((file) => file.size < 1 || file.size > MAX_INTAKE_PHOTO_BYTES)) {
    return "Cada fotografía debe pesar como máximo 5 MB y no puede estar vacía.";
  }
  if (files.some((file) => !file.name.trim() || file.name.length > 240)) {
    return "El nombre de una fotografía no es válido.";
  }
  return "";
}

export async function sha256Hex(file: Blob): Promise<string> {
  const bytes = await file.arrayBuffer();
  const digest = await globalThis.crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (value) => value.toString(16).padStart(2, "0")).join("");
}
