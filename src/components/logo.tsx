import Image from "next/image";
import Link from "next/link";

/**
 * La marca es el activo de identidad, no una aproximación en CSS. Antes esto era un
 * cuadrado con tres puntos que imitaba un logotipo; ahora es el mosaico real de Ruta
 * Solidaria, con sus colores y sus proporciones.
 */
export function Logo() {
  return (
    <Link href="/" className="brand" aria-label="Ruta Solidaria, inicio">
      <Image
        className="brand-mark"
        src="/images/marca-ruta-solidaria.webp"
        alt=""
        width={100}
        height={81}
        priority
      />
      <span>
        <strong>Ruta Solidaria</strong>
        <small>Trazabilidad humanitaria</small>
      </span>
    </Link>
  );
}
