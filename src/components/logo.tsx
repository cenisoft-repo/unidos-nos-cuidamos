import Link from "next/link";

export function Logo() {
  return (
    <Link href="/" className="brand" aria-label="Ruta Solidaria, inicio">
      <span className="brand-mark" aria-hidden="true">
        <span />
        <span />
        <span />
      </span>
      <span>
        <strong>Ruta Solidaria</strong>
        <small>Trazabilidad humanitaria</small>
      </span>
    </Link>
  );
}
