import { Droplets, HeartPulse, Home, PackageCheck, ShieldCheck, Soup, Sparkles } from "lucide-react";

export function CategoryIcon({ category, size = 22 }: { category: string; size?: number }) {
  if (category === "Agua") return <Droplets size={size} />;
  if (category === "Alimentos") return <Soup size={size} />;
  if (category === "Higiene") return <Sparkles size={size} />;
  if (category === "Refugio") return <Home size={size} />;
  if (category === "Salud") return <HeartPulse size={size} />;
  if (category === "Protección") return <ShieldCheck size={size} />;
  return <PackageCheck size={size} />;
}
