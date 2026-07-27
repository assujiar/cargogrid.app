/**
 * ChartCard header (CargoGrid Chart System) -- title, description, main KPI, and a
 * trend indicator. `trendDirection` never conveys meaning through color alone: the
 * arrow glyph (▲/▼/–) is the real signal, color is additive (the mission's own
 * "do not rely solely on color... positive vs negative" rule).
 */

import type { ReactNode } from "react";
import type { ChartTrendDirection } from "../../lib/charts/chart-types.ts";

const TREND_GLYPH: Record<ChartTrendDirection, string> = { positive: "▲", negative: "▼", neutral: "–" };
const TREND_COLOR: Record<ChartTrendDirection, string> = { positive: "text-success", negative: "text-danger", neutral: "text-text-secondary" };

export interface ChartHeaderProps {
  readonly title: string;
  readonly description?: string;
  readonly kpiValue?: ReactNode;
  readonly trendLabel?: string;
  readonly trendDirection?: ChartTrendDirection;
}

export function ChartHeader({ title, description, kpiValue, trendLabel, trendDirection = "neutral" }: ChartHeaderProps) {
  return (
    <div className="flex flex-col gap-0.5">
      <h3 className="text-sm font-semibold text-text-primary">{title}</h3>
      {kpiValue !== undefined ? <p className="text-2xl font-semibold text-text-primary">{kpiValue}</p> : null}
      {trendLabel ? (
        <p className={`text-xs font-medium ${TREND_COLOR[trendDirection]}`}>
          <span aria-hidden="true">{TREND_GLYPH[trendDirection]}</span> {trendLabel}
        </p>
      ) : null}
      {description ? <p className="text-xs text-text-secondary">{description}</p> : null}
    </div>
  );
}
