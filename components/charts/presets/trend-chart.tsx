"use client";

/**
 * Trend Chart preset (CargoGrid Chart System) -- time-series line chart. Use for
 * revenue/cost/margin movement, shipment volume, SLA trends, forecast vs. actual
 * (`docs/design-system/09_CHARTS.md`'s Chart Selection Rules). A series with
 * `isForecast: true` renders dashed and uses the shared `--chart-forecast` token,
 * never the same solid color/line style as an actual-value series -- distinguishing
 * forecast from actual must never rely on a legend label alone.
 */

import { useState } from "react";
import { Chart } from "../chart.tsx";
import { ChartAccessibleTable } from "../chart-accessible-table.tsx";
import { ChartSkeleton } from "../chart-skeleton.tsx";
import { useResolvedChartColors } from "../use-chart-colors.ts";
import { categoricalPalette } from "../../../lib/charts/chart-colors.ts";
import { buildChartAxisOption } from "../../../lib/charts/chart-theme.ts";
import { buildTooltipHtml } from "../../../lib/charts/chart-tooltip.ts";
import type { ChartOption } from "../../../lib/charts/chart-types.ts";
import type { DataTableColumn } from "../../tables/data-table.tsx";

export interface TrendSeries {
  readonly name: string;
  /** `null` renders a real gap (e.g. a forecast series with no value before the point it starts) -- ECharts' own native gap semantics, not a fabricated zero. */
  readonly data: readonly (number | null)[];
  readonly isForecast?: boolean;
}

export interface TrendChartProps {
  readonly ariaLabel: string;
  readonly categories: readonly string[];
  readonly series: readonly TrendSeries[];
  readonly valueFormatter?: (value: number) => string;
  readonly height?: number;
  readonly loading?: boolean;
  readonly empty?: boolean;
  readonly error?: Error | null;
  readonly onRetry?: () => void;
}

interface TableRow {
  readonly [key: string]: string | number;
}

export function TrendChart({
  ariaLabel,
  categories,
  series,
  valueFormatter = String,
  height = 280,
  loading = false,
  empty = false,
  error = null,
  onRetry,
}: TrendChartProps) {
  const [showTable, setShowTable] = useState(false);
  const colors = useResolvedChartColors();

  if (!colors) {
    return <ChartSkeleton height={height} />;
  }

  const palette = categoricalPalette(colors);
  const axis = buildChartAxisOption(colors);

  const option: ChartOption = {
    xAxis: { type: "category", data: [...categories], ...axis },
    yAxis: { type: "value", ...axis },
    tooltip: {
      formatter: (params: unknown) => {
        const items = Array.isArray(params) ? params : [params];
        const first = items[0] as { axisValue?: string } | undefined;
        return buildTooltipHtml({
          heading: first?.axisValue ?? "",
          // A real gap (null) is never displayed as "0" -- distinguishing missing from zero (the mission's own "do not silently represent missing values as zero" rule).
          rows: items
            .filter((item) => (item as { value: number | null }).value !== null)
            .map((item) => {
              const typed = item as { seriesName: string; value: number };
              return { label: typed.seriesName, value: valueFormatter(typed.value) };
            }),
        });
      },
    },
    series: series.map((entry, index) => ({
      type: "line",
      name: entry.name,
      data: [...entry.data],
      smooth: true,
      symbolSize: 6,
      showSymbol: false,
      lineStyle: entry.isForecast ? { type: "dashed", color: colors.forecast, width: 2 } : { color: palette[index % palette.length], width: 2 },
      itemStyle: { color: entry.isForecast ? colors.forecast : palette[index % palette.length] },
    })),
  };

  const columns: readonly DataTableColumn<TableRow>[] = [
    { key: "category", header: "Period", render: (row) => String(row.category) },
    ...series.map((entry) => ({
      key: entry.name,
      header: entry.name,
      render: (row: TableRow) => (row[entry.name] === "—" ? "—" : valueFormatter(Number(row[entry.name]))),
    })),
  ];
  const tableRows: TableRow[] = categories.map((category, index) => ({
    category,
    ...Object.fromEntries(series.map((entry) => [entry.name, entry.data[index] === null || entry.data[index] === undefined ? "—" : entry.data[index]])),
  }));

  return (
    <div className="flex flex-col gap-2">
      <Chart option={option} height={height} ariaLabel={ariaLabel} loading={loading} empty={empty} error={error} onRetry={onRetry} />
      <button type="button" onClick={() => setShowTable((current) => !current)} className="w-fit text-xs font-medium text-primary underline">
        {showTable ? "Hide data table" : "View as table"}
      </button>
      {showTable ? <ChartAccessibleTable caption={ariaLabel} columns={columns} rows={tableRows} rowKey={(row) => String(row.category)} /> : null}
    </div>
  );
}
