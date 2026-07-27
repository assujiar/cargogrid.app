"use client";

/**
 * Donut Chart preset (CargoGrid Chart System) -- small part-to-whole comparisons only
 * (this checkpoint's own Chart Selection Rules: no more than ~5 meaningful categories,
 * exact ranking not the main objective; prefer `ComparisonBarChart` when ranking
 * matters). Each slice's own data label is the non-color signal (never color alone
 * distinguishing e.g. Won vs. Lost).
 */

import { useState } from "react";
import { Chart } from "../chart.tsx";
import { ChartAccessibleTable } from "../chart-accessible-table.tsx";
import { ChartSkeleton } from "../chart-skeleton.tsx";
import { useResolvedChartColors } from "../use-chart-colors.ts";
import { buildTooltipHtml } from "../../../lib/charts/chart-tooltip.ts";
import type { ChartOption } from "../../../lib/charts/chart-types.ts";
import type { DataTableColumn } from "../../tables/data-table.tsx";
import type { ResolvedChartColors } from "../../../lib/charts/chart-colors.ts";

export type DonutSliceTone = "positive" | "negative" | "neutral" | "warning" | "categorical";

export interface DonutSlice {
  readonly name: string;
  readonly value: number;
  readonly tone?: DonutSliceTone;
}

export interface DonutChartProps {
  readonly ariaLabel: string;
  readonly slices: readonly DonutSlice[];
  readonly valueFormatter?: (value: number) => string;
  readonly height?: number;
  readonly loading?: boolean;
  readonly empty?: boolean;
  readonly error?: Error | null;
  readonly onRetry?: () => void;
}

function toneColor(colors: ResolvedChartColors, tone: DonutSliceTone | undefined, categoricalIndex: number): string {
  const categoricalPalette = [colors.primary, colors.secondary, colors.tertiary, colors.quaternary];
  switch (tone) {
    case "positive":
      return colors.positive;
    case "negative":
      return colors.negative;
    case "warning":
      return colors.warning;
    case "neutral":
      return colors.neutral;
    default:
      return categoricalPalette[categoricalIndex % categoricalPalette.length] ?? colors.primary;
  }
}

export function DonutChart({ ariaLabel, slices, valueFormatter = String, height = 280, loading = false, empty = false, error = null, onRetry }: DonutChartProps) {
  const [showTable, setShowTable] = useState(false);
  const colors = useResolvedChartColors();

  if (!colors) {
    return <ChartSkeleton height={height} />;
  }

  const total = slices.reduce((sum, slice) => sum + slice.value, 0);

  const option: ChartOption = {
    tooltip: {
      formatter: (params: unknown) => {
        const typed = params as { name: string; value: number; percent: number };
        return buildTooltipHtml({
          heading: typed.name,
          rows: [
            { label: "Value", value: valueFormatter(typed.value) },
            { label: "Share", value: `${typed.percent}%` },
          ],
        });
      },
    },
    series: [
      {
        type: "pie",
        radius: ["55%", "80%"],
        avoidLabelOverlap: true,
        label: { formatter: "{b}\n{d}%", fontSize: 11, color: colors.axis },
        labelLine: { length: 8, length2: 8 },
        data: slices.map((slice, index) => ({ name: slice.name, value: slice.value, itemStyle: { color: toneColor(colors, slice.tone, index) } })),
      },
    ],
  };

  const columns: readonly DataTableColumn<DonutSlice>[] = [
    { key: "name", header: "Category", render: (row) => row.name },
    { key: "value", header: "Value", align: "right", render: (row) => valueFormatter(row.value) },
    { key: "share", header: "Share", align: "right", render: (row) => (total === 0 ? "0%" : `${((row.value / total) * 100).toFixed(1)}%`) },
  ];

  return (
    <div className="flex flex-col gap-2">
      <Chart option={option} height={height} ariaLabel={ariaLabel} loading={loading} empty={empty || slices.length === 0} error={error} onRetry={onRetry} />
      <button type="button" onClick={() => setShowTable((current) => !current)} className="w-fit text-xs font-medium text-primary underline">
        {showTable ? "Hide data table" : "View as table"}
      </button>
      {showTable ? <ChartAccessibleTable caption={ariaLabel} columns={columns} rows={slices} rowKey={(row) => row.name} /> : null}
    </div>
  );
}
