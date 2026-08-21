import { describe, expect, it } from "vitest";
import { DESTINO_POR_OMISION, resolveSafeNext } from "./safe-redirect";

// G-062 - La comprobacion anterior aceptaba formas que sacaban del sitio. Cada una queda
// fijada aqui: si alguien vuelve a escribir la validacion "a mano", estas fallan.
//
// La barra invertida se escribe como escape unicode y no como caracter: al pasar por
// editores, heredocs y consolas se colapsa con una facilidad notable, y una prueba cuyo dato
// de entrada se colapsa deja de probar el ataque sin que nadie lo note. Paso exactamente eso
// dos veces al escribir este archivo, y por eso la ultima comprobacion del bloque verifica
// que el dato de entrada sigue siendo el que se pretende.

const BARRA = "\u005c";

describe("destino seguro tras el ingreso", () => {
  it("el dato de entrada del ataque no se ha colapsado al escribir el archivo", () => {
    expect(BARRA).toHaveLength(1);
    expect(BARRA.charCodeAt(0)).toBe(92);
    expect(`/${BARRA}evil.example`).toHaveLength(14);
  });

  it("conserva las rutas internas legitimas, con su consulta y su fragmento", () => {
    expect(resolveSafeNext("/operaciones")).toBe("/operaciones");
    expect(resolveSafeNext("/operaciones/bodega")).toBe("/operaciones/bodega");
    expect(resolveSafeNext("/donar?necesidad=abc")).toBe("/donar?necesidad=abc");
    expect(resolveSafeNext("/operaciones#coordinacion")).toBe("/operaciones#coordinacion");
  });

  it("y de verdad se iba fuera: el mismo analizador del navegador lo confirma", () => {
    expect(new URL(`/${BARRA}evil.example`, "https://ruta.example").origin).toBe("https://evil.example");
  });

  it("rechaza la barra invertida, que el navegador lee como doble barra", () => {
    expect(resolveSafeNext(`/${BARRA}evil.example`)).toBe(DESTINO_POR_OMISION);
    expect(resolveSafeNext(`/${BARRA}/evil.example`)).toBe(DESTINO_POR_OMISION);
    expect(resolveSafeNext(`/${BARRA}${BARRA}evil.example`)).toBe(DESTINO_POR_OMISION);
    expect(resolveSafeNext(`/${BARRA}${BARRA}evil.example/algo`)).toBe(DESTINO_POR_OMISION);
  });

  it("rechaza la ruta relativa al protocolo y la URL absoluta", () => {
    expect(resolveSafeNext("//evil.example")).toBe(DESTINO_POR_OMISION);
    expect(resolveSafeNext("///evil.example")).toBe(DESTINO_POR_OMISION);
    expect(resolveSafeNext("https://evil.example")).toBe(DESTINO_POR_OMISION);
    expect(resolveSafeNext("http://evil.example/operaciones")).toBe(DESTINO_POR_OMISION);
    expect(resolveSafeNext("javascript:alert(1)")).toBe(DESTINO_POR_OMISION);
    expect(resolveSafeNext("data:text/html,x")).toBe(DESTINO_POR_OMISION);
  });

  it("rechaza los caracteres de control, que el navegador elimina antes de resolver", () => {
    expect(resolveSafeNext("/\u0009/evil.example")).toBe(DESTINO_POR_OMISION);
    expect(resolveSafeNext("/\u000a/evil.example")).toBe(DESTINO_POR_OMISION);
    expect(resolveSafeNext("/\u000d/evil.example")).toBe(DESTINO_POR_OMISION);
    expect(resolveSafeNext("/oper\u0000aciones")).toBe(DESTINO_POR_OMISION);
  });

  it("normaliza en vez de devolver lo que llego, para que no haya hueco entre validar y ejecutar", () => {
    expect(resolveSafeNext("/..//evil.example")).toBe(DESTINO_POR_OMISION);
    expect(resolveSafeNext("/operaciones/../donar")).toBe("/donar");
  });

  it("cae al destino por omision ante lo que no es una ruta", () => {
    expect(resolveSafeNext(undefined)).toBe(DESTINO_POR_OMISION);
    expect(resolveSafeNext(null)).toBe(DESTINO_POR_OMISION);
    expect(resolveSafeNext(42)).toBe(DESTINO_POR_OMISION);
    expect(resolveSafeNext("")).toBe(DESTINO_POR_OMISION);
    expect(resolveSafeNext("   ")).toBe(DESTINO_POR_OMISION);
    expect(resolveSafeNext("operaciones")).toBe(DESTINO_POR_OMISION);
  });

  it("nunca devuelve algo que salga del sitio, sea cual sea la entrada", () => {
    const intentos = [
      `/${BARRA}evil.example`, "//evil.example", `/${BARRA}/evil.example`, "https://evil.example",
      "/..//evil.example", `${BARRA}${BARRA}evil.example`, "/%2f%2fevil.example",
      `/\u0009//evil.example`, "///evil.example", `/${BARRA}//evil.example`, "/%5cevil.example",
    ];
    for (const intento of intentos) {
      const destino = resolveSafeNext(intento);
      expect(destino.startsWith("/")).toBe(true);
      expect(destino.startsWith("//")).toBe(false);
      expect(new URL(destino, "https://ruta.example").origin).toBe("https://ruta.example");
    }
  });
});
