// G-062 · A donde puede llevar el ingreso.
//
// El parametro `next` de `/ingresar` lo pone quien construye el enlace, asi que lo pone
// cualquiera. Un enlace de ingreso que despues de autenticar lleva a otro dominio, con la
// apariencia de la plataforma hasta el ultimo instante, es el vehiculo clasico de robo de
// credenciales: la persona ya escribio su contrasena cuando descubre donde esta.
//
// La comprobacion anterior era `next.startsWith("/") && !next.startsWith("//")`, y se le
// escapaban al menos dos formas, comprobadas y no supuestas:
//
//   "/\evil.example"   -> el navegador lo resuelve a https://evil.example/
//   "/\/evil.example"  -> lo mismo
//
// La barra invertida cuenta como separador de autoridad en la especificacion de URL, asi que
// `/\` es `//` para el navegador y no lo es para `startsWith("//")`.
//
// Ir tapando formas una a una es perder la carrera: siempre queda una. Lo que hace esto es
// **resolver la ruta con el mismo analizador que usa el navegador**, contra un origen
// centinela, y exigir que el resultado siga en ese origen. Si al resolverla se ha ido a otro
// sitio, se descarta entera. Asi la regla no depende de enumerar ataques.

/** Origen centinela: no existe y no se puede resolver, solo sirve de referencia al analizar. */
const CENTINELA = "https://centinela.invalid";

/** A donde se va cuando lo pedido no es de fiar. */
export const DESTINO_POR_OMISION = "/operaciones";

/**
 * Devuelve una ruta interna segura, o el destino por omision si lo pedido intenta salir del
 * sitio, no es una ruta, o trae caracteres de control.
 */
export function resolveSafeNext(candidato: unknown): string {
  if (typeof candidato !== "string") return DESTINO_POR_OMISION;
  const bruto = candidato.trim();
  if (!bruto) return DESTINO_POR_OMISION;

  // Los caracteres de control se descartan antes de analizar: tabuladores y saltos de linea
  // los elimina el navegador al construir la URL, asi que dos cadenas distintas pueden acabar
  // en el mismo sitio. Lo que no se puede leer literalmente, no se acepta.
  if (/[\u0000-\u001f\u007f]/.test(bruto)) return DESTINO_POR_OMISION;

  // Tiene que ser una ruta absoluta del propio sitio. Una que empiece por `//` o por `/\` es
  // relativa al protocolo y apunta fuera; el analizador lo confirmara, pero se rechaza aqui
  // tambien para que la intencion quede escrita.
  if (!bruto.startsWith("/")) return DESTINO_POR_OMISION;
  if (bruto.startsWith("//") || bruto.startsWith("/\\")) return DESTINO_POR_OMISION;

  let resuelta: URL;
  try {
    resuelta = new URL(bruto, CENTINELA);
  } catch {
    return DESTINO_POR_OMISION;
  }

  // La comprobacion que de verdad decide: si al resolverla cambio de origen, se iba fuera.
  if (resuelta.origin !== CENTINELA) return DESTINO_POR_OMISION;

  // Se devuelve lo **normalizado**, no lo que llego: asi lo que viaja en la cabecera de
  // redireccion es exactamente lo que el analizador entendio, y no queda hueco entre lo que
  // se valido y lo que se ejecuta.
  const destino = `${resuelta.pathname}${resuelta.search}${resuelta.hash}`;
  if (!destino.startsWith("/") || destino.startsWith("//")) return DESTINO_POR_OMISION;
  return destino;
}
