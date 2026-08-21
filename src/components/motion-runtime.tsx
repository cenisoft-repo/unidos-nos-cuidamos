"use client";

import { useEffect } from "react";

/**
 * Runtime de movimiento.
 *
 * Hace dos cosas y ninguna más: declara si la interfaz puede animarse y avisa a los
 * bloques marcados cuando entran en pantalla.
 *
 * La regla que lo gobierna es que **el contenido nunca depende de esto para verse**. El
 * estado oculto del CSS vive detrás de `[data-motion="on"]`, un atributo que solo se pone
 * aquí; si el sistema operativo pide menos movimiento, si JavaScript falla o si nunca
 * llega a ejecutarse, el atributo no existe y la página se ve entera y quieta. Una
 * animación de entrada mal hecha esconde información para siempre, y esa es la clase de
 * fallo que no se nota en la máquina de quien la escribió.
 */
export function MotionRuntime() {
  useEffect(() => {
    const raiz = document.documentElement;
    const menosMovimiento = window.matchMedia("(prefers-reduced-motion: reduce)");

    let observador: IntersectionObserver | null = null;

    function apagar() {
      observador?.disconnect();
      observador = null;
      raiz.removeAttribute("data-motion");
      for (const bloque of document.querySelectorAll("[data-reveal], [data-reveal-stagger]")) {
        bloque.classList.add("is-visible");
      }
    }

    function encender() {
      raiz.dataset.motion = "on";
      observador = new IntersectionObserver(
        (entradas) => {
          for (const entrada of entradas) {
            if (!entrada.isIntersecting) continue;
            entrada.target.classList.add("is-visible");
            // Una sola vez: reaparecer al volver a subir sería movimiento sin información.
            observador?.unobserve(entrada.target);
          }
        },
        { rootMargin: "0px 0px -12% 0px", threshold: 0.08 },
      );
      for (const bloque of document.querySelectorAll("[data-reveal], [data-reveal-stagger]")) {
        observador.observe(bloque);
      }
    }

    if (menosMovimiento.matches) apagar();
    else encender();

    const alCambiarPreferencia = () => (menosMovimiento.matches ? apagar() : encender());
    menosMovimiento.addEventListener("change", alCambiarPreferencia);

    // La cabecera se despega al dejar de estar arriba del todo.
    const alHacerScroll = () => {
      const desplazada = window.scrollY > 8;
      if (desplazada) raiz.dataset.scrolled = "true";
      else raiz.removeAttribute("data-scrolled");
    };
    alHacerScroll();
    window.addEventListener("scroll", alHacerScroll, { passive: true });

    return () => {
      menosMovimiento.removeEventListener("change", alCambiarPreferencia);
      window.removeEventListener("scroll", alHacerScroll);
      observador?.disconnect();
    };
  }, []);

  return null;
}
