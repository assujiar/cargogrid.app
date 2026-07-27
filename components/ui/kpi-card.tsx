/**
 * KPI Card primitive (`docs/design-system/02_COMPONENTS.md` "Metric card / KPI
 * widget") -- single-number dashboard tile. No real dashboard uses this yet
 * (`commercial/dashboard/page.tsx` renders buckets/lists today,
 * `docs/design-system/08_COMPONENT_INVENTORY.md` §2) -- built now as a real,
 * production-ready primitive for whichever future dashboard slice adopts it.
 */

import type { ReactNode } from "react";

export interface KpiCardProps {
  readonly label: string;
  readonly value: ReactNode;
  readonly trend?: ReactNode;
  readonly tone?: "neutral" | "success" | "warning" | "danger";
}

const TONE_TEXT = {
  neutral: "text-text-primary",
  success: "text-success",
  warning: "text-warning",
  danger: "text-danger",
} as const;

export function KpiCard({ label, value, trend, tone = "neutral" }: KpiCardProps) {
  return (
    <div className="flex flex-col gap-1 rounded-md border border-neutral-200 bg-surface p-4">
      <span className="text-xs font-medium text-text-secondary">{label}</span>
      <span className={`text-2xl font-semibold ${TONE_TEXT[tone]}`}>{value}</span>
      {trend ? <span className="text-xs text-text-secondary">{trend}</span> : null}
    </div>
  );
}
