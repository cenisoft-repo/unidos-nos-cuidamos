import type { Metadata, Viewport } from "next";
import "./globals.css";
import { SiteHeader } from "@/components/site-header";
import { SiteFooter } from "@/components/site-footer";
import { PwaRegister } from "@/components/pwa-register";
import { MotionRuntime } from "@/components/motion-runtime";

export const metadata: Metadata = {
  title: { default: "Ruta Solidaria", template: "%s · Ruta Solidaria" },
  description: "Trazabilidad segura de necesidades y donaciones durante emergencias.",
  applicationName: "Ruta Solidaria",
  manifest: "/manifest.webmanifest",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#0d2343",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="es" data-scroll-behavior="smooth">
      <body>
        <PwaRegister />
        <MotionRuntime />
        <a className="skip-link" href="#contenido">Saltar al contenido</a>
        <SiteHeader />
        <main id="contenido">{children}</main>
        <SiteFooter />
      </body>
    </html>
  );
}
