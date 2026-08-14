import type { Metadata } from "next";
import Link from "next/link";
import { BadgeCheck, Boxes, LockKeyhole, ScanLine } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { assertSupabaseSuccess } from "@/lib/supabase/results";
import { DEMO_EVENT_ID } from "@/lib/constants";
import { toPublicCollectionCenter, type PublicCollectionCenterRow } from "@/lib/public-types";
import { DonationIntakeForm } from "@/components/donation-intake-form";

export const metadata: Metadata = { title: "Registrar un aporte" };
export const dynamic = "force-dynamic";

type Partner = { organization_id: string; organizations: { name: string } | null };

export default async function DonatePage({
  searchParams,
}: {
  searchParams: Promise<{ centro?: string | string[] }>;
}) {
  const supabase = await createClient();
  const query = await searchParams;
  const initialCenterId = typeof query.centro === "string" ? query.centro : undefined;
  const [userResult, centersResult] = await Promise.all([
    supabase.auth.getUser(),
    supabase.rpc("public_collection_centers", { p_event_id: DEMO_EVENT_ID }),
  ]);
  assertSupabaseSuccess("centros_aporte", [centersResult]);
  const { data: { user } } = userResult;
  const { data: centerRows } = centersResult;
  const centers = ((centerRows ?? []) as PublicCollectionCenterRow[]).map(toPublicCollectionCenter);
  let partner: Partner | null = null;
  if (user) {
    const membershipResult = await supabase.from("memberships").select("organization_id, organizations(name)").eq("user_id", user.id).eq("role", "partner_reporter").eq("active", true).limit(1).maybeSingle();
    assertSupabaseSuccess("membresia_aliado", [membershipResult]);
    partner = membershipResult.data as unknown as Partner | null;
  }

  return <>
    <section className="page-hero donate-hero"><div className="shell page-hero-grid"><div><p className="eyebrow">Tu ayuda, paso a paso</p><h1>Donar puede ser<br />mucho más sencillo.</h1><p className="lead">Elige qué aportar, dónde entregarlo y recibe un código para seguirlo. Nada cuenta como impacto antes de ser verificado.</p></div><aside className="page-aside"><strong>Entorno sandbox seguro</strong>Este recorrido usa datos sintéticos. No ingreses información real, tarjetas, claves ni cuentas bancarias.</aside></div></section>
    <section className="form-section"><div className="shell form-shell">{partner ? <DonationIntakeForm organizationId={partner.organization_id} organizationName={partner.organizations?.name ?? "Aliado autorizado"} centers={centers} initialCenterId={initialCenterId} /> : <div className="form-card"><div className="form-body"><LockKeyhole size={34} color="var(--forest-2)" /><h2 style={{ marginTop: 18 }}>Inicia sesión como aliado</h2><p>El registro exige identidad y membresía. Para probarlo usa la cuenta aliada incluida en el sandbox.</p><Link className="button button-dark" href="/ingresar?next=/donar">Ingresar para registrar</Link></div></div>}<aside className="privacy-panel"><h2>Qué sucede después</h2><ul><li><ScanLine size={18} /><span>Validamos el formato y evitamos duplicados.</span></li><li><BadgeCheck size={18} /><span>Un equipo autorizado revisa los datos.</span></li><li><Boxes size={18} /><span>Solo lo recibido y aceptado crea inventario.</span></li><li><LockKeyhole size={18} /><span>Contacto y soportes permanecen privados.</span></li></ul></aside></div></section>
  </>;
}
