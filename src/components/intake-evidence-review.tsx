"use client";

import { useState } from "react";
import { Eye, LoaderCircle } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { toOperationalMessage } from "@/lib/user-errors";
import { formatDate } from "@/lib/format";

type EvidenceRow = {
  evidence_id: string;
  evidence_position: number;
  storage_path: string;
  mime_type: string;
  uploaded_at: string | null;
};

type Viewable = { id: string; url: string; position: number; uploadedAt: string | null };

/*
 * Revisión de la evidencia fotográfica de un aporte.
 *
 * Se carga a petición y no al abrir la cola: cada foto necesita una URL firmada, y pedir
 * una por cada aporte de la lista sería trabajo tirado para quien solo va a mirar uno.
 *
 * Las URL se firman por poco tiempo y no se guardan: el bucket es privado y la evidencia
 * no debe quedar accesible desde un enlace que sobreviva a la sesión.
 */
export function IntakeEvidenceReview({ intakeId, total }: { intakeId: string; total: number }) {
  const [photos, setPhotos] = useState<Viewable[] | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");

  async function load() {
    setPending(true);
    setError("");
    const supabase = createClient();
    const { data, error: reviewError } = await supabase.rpc("intake_evidence_for_review", {
      p_intake_id: intakeId,
    });
    if (reviewError) {
      setPending(false);
      setError(toOperationalMessage(reviewError));
      return;
    }
    const rows = (data ?? []) as EvidenceRow[];
    const firmadas = await Promise.all(
      rows.map(async (row) => {
        const { data: signed } = await supabase.storage
          .from("evidence-private")
          .createSignedUrl(row.storage_path, 120);
        return signed?.signedUrl
          ? { id: row.evidence_id, url: signed.signedUrl, position: row.evidence_position, uploadedAt: row.uploaded_at }
          : null;
      }),
    );
    const viewables = firmadas.filter((row): row is Viewable => row !== null);
    setPending(false);
    if (!viewables.length) {
      setError("No fue posible abrir la evidencia. Vuelve a intentarlo.");
      return;
    }
    setPhotos(viewables);
  }

  if (!total) return null;

  return (
    <div className="evidence-review">
      {photos === null ? (
        <button className="button button-outline button-small" type="button" disabled={pending} onClick={load}>
          {pending ? <LoaderCircle className="spin" size={15} /> : <Eye size={15} />} Ver evidencia ({total})
        </button>
      ) : (
        <div className="evidence-grid">
          {photos.map((photo) => (
            <figure key={photo.id}>
              {/* eslint-disable-next-line @next/next/no-img-element -- URL firmada y efímera de un bucket privado: no puede pasar por el optimizador de imágenes. */}
              <img src={photo.url} alt={`Soporte ${photo.position} del aporte`} loading="lazy" />
              <figcaption>
                Soporte {photo.position}
                {photo.uploadedAt ? ` · ${formatDate(photo.uploadedAt)}` : ""}
              </figcaption>
            </figure>
          ))}
        </div>
      )}
      {error && <p className="field-error" role="alert">{error}</p>}
      {photos !== null && (
        <p className="evidence-note">
          Los enlaces caducan en dos minutos. La evidencia no se publica ni se adjunta a
          ninguna exportación.
        </p>
      )}
    </div>
  );
}
