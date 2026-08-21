import type { Metadata } from "next";
import Link from "next/link";
import { BadgeCheck, Boxes, Hourglass, LockKeyhole, ScanLine } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { assertSupabaseSuccess } from "@/lib/supabase/results";
import { EVENT_ID } from "@/lib/constants";
import { toDonationFlowCatalogs, type DonationCatalogRow } from "@/lib/donation-catalogs";
import { servesNonProductionData } from "@/lib/environment";
import { toPublicCollectionCenter, type PublicCollectionCenterRow } from "@/lib/public-types";
import { DonationIntakeForm, type NeedHelpTarget } from "@/components/donation-intake-form";

export const metadata: Metadata = { title: "Registrar un aporte" };
export const dynamic = "force-dynamic";

type Partner = { organization_id: string; organizations: { name: string; verified: boolean; status: string } | null };

type NeedHelpRow = {
  need_case_id: string;
  tracking_code: string;
  summary: string;
  location_label: string;
  need_item_id: string;
  category: string;
  description: string | null;
  unit: string;
  quantity_requested: number;
  quantity_committed: number;
  quantity_pending: number;
};

// Agrupa las filas planas de `need_help_options` en la necesidad y sus artículos pendientes.
function toNeedHelpTarget(rows: NeedHelpRow[]): NeedHelpTarget | undefined {
  const first = rows[0];
  if (!first) return undefined;
  return {
    needCaseId: first.need_case_id,
    trackingCode: first.tracking_code,
    summary: first.summary,
    locationLabel: first.location_label,
    items: rows.map((row) => ({
      needItemId: row.need_item_id,
      category: row.category,
      description: row.description ?? row.category,
      unit: row.unit,
      quantityRequested: Number(row.quantity_requested),
      quantityCommitted: Number(row.quantity_committed),
      quantityPending: Number(row.quantity_pending),
    })),
  };
}

export default async function DonatePage({
  searchParams,
}: {
  searchParams: Promise<{ centro?: string | string[]; necesidad?: string | string[] }>;
}) {
  const supabase = await createClient();
  const query = await searchParams;
  const initialCenterId = typeof query.centro === "string" ? query.centro : undefined;
  const needProjectionId = typeof query.necesidad === "string" ? query.necesidad : undefined;
  const [userResult, catalogsResult] = await Promise.all([
    supabase.auth.getUser(),
    supabase.rpc("donation_flow_catalogs"),
  ]);
  assertSupabaseSuccess("flujo_aportes", [catalogsResult]);
  const { data: { user } } = userResult;
  const catalogs = toDonationFlowCatalogs((catalogsResult.data ?? []) as DonationCatalogRow[]);
  let partner: Partner | null = null;
  let centers = [] as ReturnType<typeof toPublicCollectionCenter>[];
  let need: NeedHelpTarget | undefined;
  if (user) {
    // G-055: la habilitación ya no se filtra en la consulta. Antes `verified` era parte del
    // `where`, así que un aliado sin habilitar era indistinguible de alguien que no es
    // aliado: veía «inicia sesión como aliado» estando ya dentro. Ahora se lee y se explica.
    // El corte es de 5 y es deliberado: son las membresías de una persona en un evento.
    const membershipResult = await supabase
      .from("memberships")
      .select("organization_id, organizations!inner(name, verified, status)")
      .eq("user_id", user.id)
      .eq("event_id", EVENT_ID)
      .in("role", ["partner_reporter", "event_admin"])
      .eq("active", true)
      .eq("organizations.status", "active")
      .limit(5);
    assertSupabaseSuccess("membresia_aliado", [membershipResult]);
    const memberships = (membershipResult.data ?? []) as unknown as Partner[];
    // Con varias membresías gana la que ya puede operar: mostrar la pendiente teniendo otra
    // habilitada sería un bloqueo inventado.
    partner = memberships.find((row) => row.organizations?.verified) ?? memberships[0] ?? null;
    if (partner?.organizations?.verified) {
      const centersResult = await supabase.rpc("organization_delivery_points", {
        p_event_id: EVENT_ID,
        p_organization_id: partner.organization_id,
      });
      assertSupabaseSuccess("puntos_entrega_organizacion", [centersResult]);
      centers = ((centersResult.data ?? []) as PublicCollectionCenterRow[]).map(toPublicCollectionCenter);
    }
    if (needProjectionId) {
      const needResult = await supabase.rpc("need_help_options", { p_projection_id: needProjectionId });
      assertSupabaseSuccess("necesidad_ayudar", [needResult]);
      need = toNeedHelpTarget((needResult.data ?? []) as NeedHelpRow[]);
    }
  }

  return <>
    <section className="page-hero donate-hero"><div className="shell page-hero-grid"><div><p className="eyebrow">Tu ayuda, paso a paso</p><h1>Donar puede ser<br />mucho más sencillo.</h1><p className="lead">Elige qué aportar, dónde entregarlo y recibe un código para seguirlo. Nada cuenta como impacto antes de ser verificado.</p></div>{servesNonProductionData && <aside className="page-aside"><strong>Instancia de práctica</strong>No ingreses información real, tarjetas, claves ni cuentas bancarias.</aside>}</div></section>
    <section className="form-section"><div className="shell form-shell">{partner?.organizations?.verified
      ? <DonationIntakeForm organizationId={partner.organization_id} organizationName={partner.organizations?.name ?? "Aliado autorizado"} centers={centers} initialCenterId={initialCenterId} catalogs={catalogs} need={need} />
      : partner
        // G-055: quien ya es aliado pero cuya organización todavía no está habilitada tiene
        // que saber exactamente en qué paso está. Decirle «inicia sesión» sería mentirle.
        ? <div className="form-card"><div className="form-body"><Hourglass size={34} color="var(--forest-2)" /><h2 style={{ marginTop: 18 }}>Tu organización está en revisión</h2><p><strong>{partner.organizations?.name}</strong> quedó registrada con tu cuenta, pero todavía no está habilitada para registrar aportes. Confirmar tu correo comprueba que el buzón es tuyo; habilitar a la organización es una decisión que toma el equipo de verificación.</p><p className="form-notice" style={{ marginTop: 14 }}>Mientras tanto tu punto de acopio no aparece en el mapa público: no queremos enviar a nadie a entregar donde aún no hemos comprobado que se recibe.</p><Link className="button button-dark" href="/">Volver al inicio</Link></div></div>
        : <div className="form-card"><div className="form-body"><LockKeyhole size={34} color="var(--forest-2)" /><h2 style={{ marginTop: 18 }}>Inicia sesión como aliado</h2><p>Registrar un aporte requiere una membresía vigente en una organización habilitada.</p><Link className="button button-dark" href={`/ingresar?next=${encodeURIComponent(needProjectionId ? `/donar?necesidad=${needProjectionId}` : "/donar")}`}>Ingresar para registrar</Link><p className="form-notice" style={{ marginTop: 14 }}>¿Todavía no eres aliado? <Link href="/registro">Regístrate y confirma tu correo</Link>.</p></div></div>}<aside className="privacy-panel"><h2>Qué sucede después</h2><ul><li><ScanLine size={18} /><span>Recibes un código para seguir tu aporte.</span></li><li><BadgeCheck size={18} /><span>Un equipo autorizado revisa los datos.</span></li><li><Boxes size={18} /><span>Solo lo recibido y aceptado crea inventario.</span></li><li><LockKeyhole size={18} /><span>Contacto y soportes permanecen privados.</span></li></ul></aside></div></section>
  </>;
}
