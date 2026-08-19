import Image from "next/image";
import Link from "next/link";
import {
  ArrowRight,
  BadgeCheck,
  ClipboardCheck,
  Database,
  Eye,
  HeartHandshake,
  LockKeyhole,
  MapPin,
  Search,
  ShieldCheck,
  Truck,
} from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { assertSupabaseSuccess } from "@/lib/supabase/results";
import { EVENT_ID, EVENT_SLUG, NEED_CATEGORIES } from "@/lib/constants";
import { numberFormat } from "@/lib/format";
import { toPublicCollectionCenter, toPublicLogisticsPoint, type PublicCollectionCenterRow, type PublicLogisticsPointRow } from "@/lib/public-types";
import { CategoryIcon } from "@/components/category-icon";
import { CollectionCenters } from "@/components/collection-centers";
import { CoverageExplorer } from "@/components/coverage-explorer";
import { StatusPill } from "@/components/status-pill";

type NeedProjection = {
  id: string;
  category: string;
  summary: string;
  location_label: string;
  status: string;
  needed_quantity: number;
  committed_quantity: number;
  covered_quantity: number;
  unit: string;
};

type MapNeedProjection = NeedProjection & {
  latitude: number | null;
  longitude: number | null;
  updated_at: string;
};

export const dynamic = "force-dynamic";

/** Nunca sustituye una métrica ausente por un número: sin corte, no hay cifra. */
function metricValue(value: number | null | undefined) {
  return value === null || value === undefined ? "—" : numberFormat.format(Number(value));
}

export default async function HomePage() {
  const supabase = await createClient();
  const results = await Promise.all([
    supabase.from("public_event_dashboard").select("*").eq("slug", EVENT_SLUG).maybeSingle(),
    supabase.from("public_need_projections").select("id,category,summary,location_label,status,needed_quantity,committed_quantity,covered_quantity,unit").eq("event_id", EVENT_ID).eq("published", true).order("updated_at", { ascending: false }),
    supabase.rpc("public_need_map", { p_event_id: EVENT_ID }),
    supabase.rpc("public_collection_centers", { p_event_id: EVENT_ID }),
    supabase.rpc("public_logistics_map", { p_event_id: EVENT_ID }),
  ]);
  assertSupabaseSuccess("portada", results);
  const [{ data: dashboard }, { data: needs }, { data: mapNeeds }, { data: centerRows }, { data: logisticsRows }] = results;

  const visibleNeeds = (needs ?? []) as NeedProjection[];
  const territorialNeeds = (mapNeeds ?? []) as MapNeedProjection[];
  const centers = ((centerRows ?? []) as PublicCollectionCenterRow[]).map(toPublicCollectionCenter);
  const logistics = ((logisticsRows ?? []) as PublicLogisticsPointRow[]).map(toPublicLogisticsPoint);
  const mappedNeeds = territorialNeeds.map((need) => ({
    id: need.id,
    category: need.category,
    summary: need.summary,
    locationLabel: need.location_label,
    status: need.status,
    projectionId: need.id,
    neededQuantity: Number(need.needed_quantity),
    committedQuantity: Number(need.committed_quantity),
    coveredQuantity: Number(need.covered_quantity),
    unit: need.unit,
    latitude: need.latitude === null ? null : Number(need.latitude),
    longitude: need.longitude === null ? null : Number(need.longitude),
    updatedAt: need.updated_at,
  }));

  return (
    <>
      <section className="hero human-hero">
        <div className="shell hero-layout">
          <div className="hero-copy">
            <p className="eyebrow">Unidos nos cuidamos</p>
            <h1>Ayudar debe sentirse <em>simple y claro.</em></h1>
            <p className="lead">Descubre qué hace falta, elige dónde aportar y comprueba el recorrido sin exponer a nadie.</p>
            <div className="hero-actions">
              <Link className="button button-dark" href="/donar">Quiero ayudar <ArrowRight size={17} /></Link>
              <Link className="button button-outline" href="/seguimiento"><Search size={16} /> Rastrear mi ayuda</Link>
            </div>
            <Link className="hero-report-link" href="/reportar">Necesito reportar una necesidad →</Link>
            <div className="trust-line">
              <BadgeCheck size={18} />
              <span>Necesidades verificadas, ubicación aproximada y una historia auditable.</span>
            </div>
          </div>

          <figure className="human-hero-photo">
            <Image
              src="/images/volunteers-packing-donations.jpg"
              alt="Tres personas voluntarias organizan cajas y suministros para una donación"
              width={1280}
              height={854}
              sizes="(max-width: 1024px) 100vw, 46vw"
              preload
            />
            <figcaption>
              <strong>Cada caja representa una decisión.</strong>
              <span>La plataforma ayuda a que llegue con contexto y seguimiento.</span>
            </figcaption>
            <small>Fotografía: Gustavo Fring · Pexels</small>
          </figure>
        </div>
      </section>

      <nav className="category-shortcuts" aria-label="Explorar necesidades por categoría">
        <div className="shell category-shortcuts-grid">
          {NEED_CATEGORIES.map((category) => (
            <Link href="/#necesidades" key={category}>
              <span aria-hidden="true"><CategoryIcon category={category} size={21} /></span>
              {category}
            </Link>
          ))}
        </div>
      </nav>

      <section className="section section-white" id="necesidades">
        <div className="shell">
          <div className="section-heading row">
            <div>
              <p className="eyebrow">Necesidades verificadas</p>
              <h2>Hoy hace falta</h2>
              <p>Información útil y vigente, sin publicar contactos ni direcciones precisas.</p>
            </div>
            <Link className="button button-ghost" href="/transparencia">Cómo verificamos <ArrowRight size={16} /></Link>
          </div>
          <div className="needs-catalog-grid">
            {visibleNeeds.length ? visibleNeeds.map((need) => {
              const needed = Number(need.needed_quantity);
              const committed = Number(need.committed_quantity);
              const covered = Number(need.covered_quantity);
              const progress = needed > 0 ? Math.min(100, Math.round((covered / needed) * 100)) : 0;
              // Lo que un aliado puede aportar es lo que nadie ha comprometido todavía.
              const remaining = Math.max(0, needed - committed);
              return (
                <article className="need-card" key={need.id}>
                  <div className="need-card-head">
                    <span className="need-card-icon" aria-hidden="true"><CategoryIcon category={need.category} /></span>
                    <div><StatusPill status="verified">Verificada</StatusPill><p>{need.category}</p></div>
                  </div>
                  <h3>{need.summary}</h3>
                  <p className="need-card-location"><MapPin size={14} /> {need.location_label}</p>
                  <div className="need-card-coverage">
                    <div><strong>Faltan {numberFormat.format(remaining)} {need.unit}</strong><span>{progress}% cubierto</span></div>
                    <div className="progress" aria-label={`${progress}% cubierto`}><span style={{ width: `${progress}%` }} /></div>
                    <small>Solicitado {numberFormat.format(needed)} · comprometido {numberFormat.format(committed)} · entregado {numberFormat.format(covered)} {need.unit}</small>
                  </div>
                  <Link className="button button-outline button-block" href={`/donar?necesidad=${need.id}`}>Quiero ayudar <ArrowRight size={15} /></Link>
                </article>
              );
            }) : <p className="ops-empty">Ahora mismo no hay necesidades públicas vigentes. Los reportes pendientes siguen protegidos.</p>}
          </div>
        </div>
      </section>

      <section className="section map-section" id="mapa-section">
        <div className="shell">
          <div className="section-heading map-heading">
            <p className="eyebrow">Mapa territorial</p>
            <h2>Explora dónde puedes ayudar</h2>
            <p>El azul identifica centros de acopio en su dirección real; los demás colores señalan necesidades en zona aproximada.</p>
          </div>
          <CoverageExplorer eventId={EVENT_ID} needs={mappedNeeds} centers={centers} logistics={logistics} />
        </div>
      </section>

      <section className="section section-white" id="centros">
        <div className="shell">
          <div className="section-heading row">
            <div>
              <p className="eyebrow">Puntos de entrega</p>
              <h2>Centros de acopio cercanos</h2>
              <p>Revisa qué recibe cada punto y selecciónalo antes de registrar tu aporte.</p>
            </div>
            <span className="safe-data-note"><LockKeyhole size={15} /> Ubicación protegida</span>
          </div>
          <CollectionCenters centers={centers} />
        </div>
      </section>

      <section className="impact-strip" aria-label="Cifras conciliadas">
        <div className="shell live-grid">
          <div className="live-item intro"><strong>Lo comprobable hoy</strong><span>Solo cifras conciliadas contra su corte.</span></div>
          <div className="live-item"><strong>{metricValue(dashboard?.active_needs)}</strong><span>necesidades públicas vigentes</span></div>
          <div className="live-item"><strong>{metricValue(dashboard?.units_delivered)}</strong><span>unidades cubiertas por categoría</span></div>
          <div className="live-item"><strong>{metricValue(dashboard?.visible_donations)}</strong><span>aportes visibles y conciliados</span></div>
        </div>
      </section>

      <section className="section section-forest">
        <div className="shell">
          <div className="section-heading">
            <p className="eyebrow">Una ruta fácil de entender</p>
            <h2>Así viaja una ayuda</h2>
            <p>Cuatro momentos visibles y una historia que no se borra.</p>
          </div>
          <div className="steps-grid">
            <article className="step"><span className="step-num">01</span><ClipboardCheck size={23} /><h3>Se reporta</h3><p>La necesidad o el aporte entra con datos mínimos y privados.</p></article>
            <article className="step"><span className="step-num">02</span><ShieldCheck size={23} /><h3>Se verifica</h3><p>Un equipo autorizado comprueba fuente, cantidades y vigencia.</p></article>
            <article className="step"><span className="step-num">03</span><Truck size={23} /><h3>Se mueve</h3><p>La recepción, reserva y entrega quedan conectadas.</p></article>
            <article className="step"><span className="step-num">04</span><HeartHandshake size={23} /><h3>Se confirma</h3><p>Solo la evidencia conciliada alimenta las cifras públicas.</p></article>
          </div>
        </div>
      </section>

      <section className="section section-white">
        <div className="shell assurance-grid">
          <div className="section-heading">
            <p className="eyebrow">Confianza por diseño</p>
            <h2>Transparencia sin exponer a nadie.</h2>
            <p>La rendición de cuentas no exige publicar teléfonos, direcciones ni nombres sin autorización.</p>
            <Link href="/transparencia" className="button button-outline">Ver cifras y metodología</Link>
          </div>
          <div className="assurance-list">
            <article className="assurance-item"><Eye size={25} /><h3>Solo lo seguro</h3><p>Lo público se publica aparte de la operación interna.</p></article>
            <article className="assurance-item"><Database size={25} /><h3>Historia protegida</h3><p>Las correcciones compensan; nunca borran la trazabilidad.</p></article>
            <article className="assurance-item"><BadgeCheck size={25} /><h3>Cifras conciliadas</h3><p>Una promesa todavía no cuenta como recepción ni impacto.</p></article>
            <article className="assurance-item"><LockKeyhole size={25} /><h3>Acceso mínimo</h3><p>Cada persona accede solo a su organización, evento y función.</p></article>
          </div>
        </div>
      </section>
    </>
  );
}
