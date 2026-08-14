import { cn } from "@/lib/format";
import { labelStatus } from "@/lib/constants";

export function StatusPill({ status, children }: { status: string; children?: React.ReactNode }) {
  const tone = ["published", "verified", "validated", "approved", "active"].includes(status)
    ? "good"
    : ["rejected", "disproved", "cancelled", "expired"].includes(status)
      ? "critical"
      : ["observed", "quarantined", "incident", "hold"].includes(status)
        ? "warning"
        : "neutral";
  return <span className={cn("status-pill", `status-${tone}`)}>{children ?? labelStatus(status)}</span>;
}
