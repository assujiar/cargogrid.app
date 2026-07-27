"use client";

/**
 * Comparison Bar Chart preset (CargoGrid Chart System) -- category comparison
 * (business-unit, salesperson, customer ranking, pipeline stage, win/loss reasons).
 * Renders horizontal bars when `horizontal` is set (recommended for long labels or
 * many categories, per this checkpoint's own Chart Selection Rules).
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

export interface ComparisonBarSeries {
  readonly name: string;
  readonly data: readonly number[];
}

export interface ComparisonBarChartProps {
  readonly ariaLabel: string;
  readonly categories: readonly string[];
  readonly series: readonly ComparisonBarSeries[];
  readonly horizontal?: boolean;
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

export function ComparisonBarChart({
  ariaLabel,
  categories,
  series,
  horizontal = false,
  valueFormatter = String,
  height = 280,
  loading = false,
  empty = false,
  error = null,
  onRetry,
}: ComparisonBarChartProps) {
  const [showTable, setShowTable] = useState(false);
  const colors = useResolvedChartColors();

  if (!colors) {
    return <ChartSkeleton height={height} />;
  }

  const palette = categoricalPalette(colors);
  const axis = buildChartAxisOption(colors);
  const categoryAxis = { type: "category" as const, data: [...categories], ...axis };
  const valueAxis = { type: "value" as const, ...axis };

  const option: ChartOption = {
    xAxis: horizontal ? valueAxis : categoryAxis,
    yAxis: horizontal ? categoryAxis : valueAxis,
    tooltip: {
      formatter: (params: unknown) => {
        const items = Array.isArray(params) ? params : [params];
        const first = items[0] as { axisValue?: string; name?: string } | undefined;
        return buildTooltipHtml({
          heading: first?.axisValue ?? first?.name ?? "",
          rows: items.map((item) => {
            const typed = item as { seriesName: string; value: number };
            return { label: typed.seriesName, value: valueFormatter(typed.value) };
          }),
        });
      },
    },
    series: series.map((entry, index) => ({
      type: "bar",
      name: entry.name,
      data: [...entry.data],
      itemStyle: { color: palette[index % palette.length], borderRadius: series.length > 1 ? 0 : 3 },
      barMaxWidth: 32,
    })),
  };

  const columns: readonly DataTableColumn<TableRow>[] = [
    { key: "category", header: "Category", render: (row) => String(row.category) },
    ...series.map((entry) => ({ key: entry.name, header: entry.name, render: (row: TableRow) => valueFormatter(Number(row[entry.name])) })),
  ];
  const tableRows: TableRow[] = categories.map((category, index) => ({
    category,
    ...Object.fromEntries(series.map((entry) => [entry.name, entry.data[index] ?? 0])),
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
