import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { AlertTriangle, MapPinned, ShieldCheck } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { assertSupabaseSuccess } from "@/lib/supabase/results";
import { EVENT_ID } from "@/lib/constants";
import { servesNonProductionData } from "@/lib/environment";
import {
  PlatformParameterization,
  type OrganizationOption,
  type PlatformAuditEntry,
  type OrganizationVerification,
  type PlatformCatalog,
  type PlatformUser,
} from "@/components/platform-parameterization";

export const metadata: Metadata = { title: "Parametrización" };
export const dynamic = "force-dynamic";

export default async function ParameterizationPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/ingresar?next=/operaciones/parametrizacion");

  /*
   * La puerta es la misma que usa la base: `is_super_admin()`. No se deduce de un rol
   * leído en el cliente ni de un claim del token, así que ocultar el módulo y negarlo
   * dicen exactamente lo mismo. Aunque alguien llegue por URL, las RPC de esta pantalla
   * vuelven a comprobarlo.
   */
  const { data: isSuperAdmin, error: gateError } = await supabase.rpc("is_super_admin");
  assertSupabaseSuccess("parametrizacion_alcance", [{ error: gateError }]);
  if (!isSuperAdmin) redirect("/operaciones");

  const [usersResult, catalogsResult, auditResult, organizationsResult, verificationsResult] = await Promise.all([
    supabase.rpc("platform_users_admin", { p_event_id: EVENT_ID }),
    supabase.rpc("parameterizable_catalogs"),
    supabase.rpc("platform_audit_admin", { p_event_id: EVENT_ID, p_limit: 60 }),
    supabase.from("organizations").select("id,name,status,verified").order("name"),
    supabase.rpc("organization_verification_status", { p_event_id: EVENT_ID }),
  ]);
  assertSupabaseSuccess("parametrizacion", [usersResult, catalogsResult, auditResult, organizationsResult, verificationsResult]);

  return <div className="ops-shell">
    <div className="ops-header">
      <div>
        <p className="eyebrow">Autoridad global</p>
        <h1>Parametrización</h1>
        <p>Estructura operativa, catálogos y alcance de cada cuenta. Lo que aquí se edita son datos; las reglas del sistema no se tocan desde una pantalla.</p>
      </div>
      <ShieldCheck size={36} color="var(--forest-2)" />
    </div>
    {servesNonProductionData && <div className="ops-alert"><AlertTriangle size={17} /><strong>Instancia de práctica:</strong> los cambios de esta vista afectan solo al entorno sintético.</div>}
    <nav className="ops-subnav" aria-label="Módulos operativos">
      <Link href="/operaciones">Mando</Link>
      <Link href="/operaciones/centros">Puntos de entrega</Link>
      <Link href="/operaciones/bodega">Bodega y logística</Link>
      <Link href="/operaciones/tesoreria">Tesorería</Link>
      <Link href="/operaciones/reportes">Reportes</Link>
      <Link aria-current="page" href="/operaciones/parametrizacion">Parametrización</Link>
    </nav>
    {/*
      La estructura territorial ya se administra en «Puntos de entrega», que valida,
      versiona las categorías aceptadas y deja rastro. La autoridad global la alcanza sin
      cambios, así que se enlaza en vez de duplicarse aquí.
    */}
    <section className="ops-panel" aria-labelledby="param-structure-title">
      <header className="ops-panel-header">
        <div>
          <h2 id="param-structure-title">Estructura operativa</h2>
          <p>Centros, bodegas y puntos de acopio, con su organización responsable, lo que acepta cada uno y si despacha.</p>
        </div>
        <Link className="button button-outline button-small" href="/operaciones/centros"><MapPinned size={15} /> Administrar puntos</Link>
      </header>
      <p className="param-note">Un punto con historial se desactiva, no se borra: lo recibido allí tiene que seguir siendo trazable.</p>
    </section>
    <PlatformParameterization
      users={(usersResult.data ?? []) as PlatformUser[]}
      catalogs={(catalogsResult.data ?? []) as PlatformCatalog[]}
      audit={(auditResult.data ?? []) as PlatformAuditEntry[]}
      organizations={(organizationsResult.data ?? []) as OrganizationOption[]}
      verifications={(verificationsResult.data ?? []) as OrganizationVerification[]}
      currentUserId={user.id}
    />
  </div>;
}
