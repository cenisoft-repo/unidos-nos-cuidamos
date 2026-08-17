import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { AlertTriangle, MapPinned } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { assertSupabaseSuccess } from "@/lib/supabase/results";
import { EVENT_ID } from "@/lib/constants";
import { servesNonProductionData } from "@/lib/environment";
import { toDonationFlowCatalogs, type DonationCatalogRow } from "@/lib/donation-catalogs";
import { DeliveryPointsManager, type DeliveryPointAdmin } from "@/components/delivery-points-manager";

export const metadata: Metadata = { title: "Puntos de entrega" };
export const dynamic = "force-dynamic";

type AdminMembership = {
  organization_id: string;
  organizations: { name: string } | { name: string }[] | null;
};

function organizationName(membership: AdminMembership) {
  if (Array.isArray(membership.organizations)) return membership.organizations[0]?.name ?? "Organización";
  return membership.organizations?.name ?? "Organización";
}

export default async function DeliveryPointsPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/ingresar?next=/operaciones/centros");

  const [membershipsResult, pointsResult, catalogsResult] = await Promise.all([
    supabase.from("memberships").select("organization_id,organizations(name)").eq("user_id", user.id).eq("event_id", EVENT_ID).eq("role", "event_admin").eq("active", true),
    supabase.rpc("delivery_points_admin", { p_event_id: EVENT_ID }),
    supabase.rpc("donation_flow_catalogs"),
  ]);
  assertSupabaseSuccess("parametrizacion_puntos_entrega", [membershipsResult, pointsResult, catalogsResult]);

  const memberships = (membershipsResult.data ?? []) as unknown as AdminMembership[];
  if (!memberships.length) redirect("/operaciones");
  const organizations = memberships
    .map((membership) => ({ id: membership.organization_id, name: organizationName(membership) }))
    .filter((organization, index, all) => all.findIndex((candidate) => candidate.id === organization.id) === index)
    .sort((left, right) => left.name.localeCompare(right.name, "es"));
  const catalogs = toDonationFlowCatalogs((catalogsResult.data ?? []) as DonationCatalogRow[]);
  const categories = [...new Set(catalogs.donationCategories
    .filter((category) => category.kind === "in_kind" && category.parentCategory)
    .map((category) => category.parentCategory as string))].sort((left, right) => left.localeCompare(right, "es"));

  return <div className="ops-shell">
    <div className="ops-header"><div><p className="eyebrow">Administración segura</p><h1>Parametrizar puntos de entrega</h1><p>Define dónde se reciben bienes, qué acepta cada punto y qué información puede mostrarse.</p></div><MapPinned size={36} color="var(--forest-2)" /></div>
    {servesNonProductionData && <div className="ops-alert"><AlertTriangle size={17} /><strong>Instancia de práctica:</strong> usa únicamente ubicaciones y datos sintéticos.</div>}
    <nav className="ops-subnav" aria-label="Módulos operativos"><Link href="/operaciones">Mando</Link><Link aria-current="page" href="/operaciones/centros">Puntos de entrega</Link><Link href="/operaciones/bodega">Bodega y logística</Link><Link href="/operaciones/tesoreria">Tesorería</Link></nav>
    <DeliveryPointsManager organizations={organizations} points={(pointsResult.data ?? []) as DeliveryPointAdmin[]} categories={categories} />
  </div>;
}
