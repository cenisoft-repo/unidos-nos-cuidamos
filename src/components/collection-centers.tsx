import Link from "next/link";
import { ArrowRight, CheckCircle2, Clock3, MapPin, Snowflake } from "lucide-react";
import type { PublicCollectionCenter } from "@/lib/public-types";

export function CollectionCenters({ centers }: { centers: PublicCollectionCenter[] }) {
  return (
    <div className="centers-grid">
      {centers.length ? centers.map((center) => (
        <article className="center-card" key={center.id}>
          <div className="center-card-top">
            <span className="center-map-icon" aria-hidden="true"><MapPin size={22} /></span>
            <div>
              <p>{center.locationLabel}</p>
              <h3>{center.name}</h3>
            </div>
          </div>
          <div className="center-service"><Clock3 size={15} /> Atención con coordinación previa</div>
          <div className="center-tags" aria-label="Categorías que recibe">
            {center.accepts.map((category) => <span key={category}><CheckCircle2 size={12} /> {category}</span>)}
            {center.coldChainCapable && <span><Snowflake size={12} /> Cadena de frío</span>}
          </div>
          <p className="center-privacy">Dirección pública del punto de acopio. Confirma el horario con la coordinación autorizada.</p>
          <Link className="button button-outline button-block" href={`/donar?centro=${center.id}`}>Elegir este centro <ArrowRight size={15} /></Link>
        </article>
      )) : (
        <p className="ops-empty">Todavía no hay centros públicos disponibles. Puedes revisar de nuevo más tarde.</p>
      )}
    </div>
  );
}
