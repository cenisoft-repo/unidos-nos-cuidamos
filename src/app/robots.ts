import type { MetadataRoute } from "next";
import { servesNonProductionData } from "@/lib/environment";

/*
 * G-067: el sitio no declaraba nada a los rastreadores, así que quedaba abierto a indexación
 * por omisión.
 *
 * Y aquí la decisión no es de higiene: mientras la instancia sirva datos sintéticos, indexarla
 * pondría una plataforma humanitaria **de práctica** en los resultados de búsqueda de alguien
 * que está buscando ayuda de verdad. `G-006` dice además que ni la marca ni las fuentes están
 * autorizadas. Así que hasta que alguien declare `NEXT_PUBLIC_APP_ENV=production`, esto se
 * cierra entero; el día que se declare, se abre solo lo público y nunca la operación.
 */
export default function robots(): MetadataRoute.Robots {
  if (servesNonProductionData) {
    return { rules: [{ userAgent: "*", disallow: "/" }] };
  }
  return {
    rules: [
      {
        userAgent: "*",
        allow: ["/", "/transparencia", "/seguimiento", "/reportar", "/donar", "/registro"],
        // La operación, el ingreso y las rutas internas no se ofrecen a ningún rastreador.
        disallow: ["/operaciones", "/ingresar", "/api/", "/pagos/"],
      },
    ],
  };
}
