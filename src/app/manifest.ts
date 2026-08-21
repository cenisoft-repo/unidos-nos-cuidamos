import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Ruta Solidaria",
    short_name: "Ruta Solidaria",
    description: "Trazabilidad humanitaria segura y verificable.",
    start_url: "/",
    display: "standalone",
    background_color: "#f0f4f8",
    theme_color: "#0d2343",
    lang: "es-CO",
    icons: [
      { src: "/icon-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
      { src: "/icon-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
      { src: "/icon-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
    ],
  };
}
