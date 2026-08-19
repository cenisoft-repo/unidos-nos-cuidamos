const MAP_STYLE_URL = process.env.NEXT_PUBLIC_MAP_STYLE_URL || "https://tiles.openfreemap.org/styles/liberty";
const RASTER_TILE_URL = process.env.NEXT_PUBLIC_RASTER_TILE_URL || "https://tile.openstreetmap.org/{z}/{x}/{y}.png";
// Geocodificador para el asistente de dirección de los puntos de entrega (búsqueda por
// texto). Configurable; por defecto Nominatim de OpenStreetMap.
const GEOCODER_URL = process.env.NEXT_PUBLIC_GEOCODER_URL || "https://nominatim.openstreetmap.org/search";

/** Devuelve el origen de una URL configurada, o nada si no es utilizable. */
function origin(value: string | undefined) {
  if (!value) return null;
  try {
    return new URL(value.replace(/\{[a-z]\}/gi, "0")).origin;
  } catch {
    return null;
  }
}

function unique(values: Array<string | null>) {
  return Array.from(new Set(values.filter((value): value is string => Boolean(value))));
}

/**
 * Política de seguridad de contenido. Los orígenes se derivan de la
 * configuración, de modo que un cambio de proveedor de mapas o de Supabase no
 * exige editar la política a mano.
 */
export function contentSecurityPolicy(nonce: string, { development = false } = {}) {
  const supabase = origin(process.env.NEXT_PUBLIC_SUPABASE_URL);
  const supabaseSocket = supabase ? supabase.replace(/^http/, "ws") : null;
  const mapStyle = origin(MAP_STYLE_URL);
  const rasterTiles = origin(RASTER_TILE_URL);
  const geocoder = origin(GEOCODER_URL);

  const script = ["'self'", `'nonce-${nonce}'`, "'strict-dynamic'"];
  // El servidor de desarrollo evalúa código para recargar en caliente.
  if (development) script.push("'unsafe-eval'");

  return [
    "default-src 'self'",
    "base-uri 'self'",
    "object-src 'none'",
    "frame-ancestors 'none'",
    "form-action 'self'",
    `script-src ${script.join(" ")}`,
    // React y las librerías de mapas escriben estilos en línea.
    "style-src 'self' 'unsafe-inline'",
    // La evidencia fotográfica se sirve con una URL firmada del almacenamiento de
    // Supabase, así que ese origen tiene que estar aquí: sin él la política bloquea la
    // imagen en silencio y quien verifica ve un hueco donde debería estar el soporte.
    `img-src ${unique(["'self'", "data:", "blob:", supabase, mapStyle, rasterTiles]).join(" ")}`,
    `font-src ${unique(["'self'", "data:", mapStyle]).join(" ")}`,
    `connect-src ${unique(["'self'", supabase, supabaseSocket, mapStyle, rasterTiles, geocoder]).join(" ")}`,
    // MapLibre crea sus trabajadores desde blobs.
    "worker-src 'self' blob:",
    "manifest-src 'self'",
    // Fuera de desarrollo no debe quedar ninguna carga en texto plano.
    ...(development ? [] : ["upgrade-insecure-requests"]),
  ].join("; ");
}
