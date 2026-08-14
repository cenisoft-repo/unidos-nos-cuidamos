import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Ruta Solidaria",
    short_name: "Ruta Solidaria",
    description: "Trazabilidad humanitaria segura y verificable.",
    start_url: "/",
    display: "standalone",
    background_color: "#f5f3ed",
    theme_color: "#153d37",
    lang: "es-CO",
    icons: [
      { src: "/icon.svg", sizes: "any", type: "image/svg+xml", purpose: "any" },
    ],
  };
}
