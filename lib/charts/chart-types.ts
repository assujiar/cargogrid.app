/**
 * Shared chart types (CargoGrid Chart System, Apache ECharts). Every preset and the
 * low-level `Chart` component share this vocabulary so a consumer never has to import
 * `echarts` types directly.
 */

import type { ComposeOption, ECharts } from "echarts/core";
import type { BarSeriesOption, LineSeriesOption, PieSeriesOption } from "echarts/charts";
import type {
  GridComponentOption,
  TooltipComponentOption,
  LegendComponentOption,
  TitleComponentOption,
  DatasetComponentOption,
  DataZoomComponentOption,
  AriaComponentOption,
} from "echarts/components";

/**
 * A narrow, modular-import-honest option type -- composed only from the series/
 * component options `components/charts/chart.tsx` actually registers (Bar/Line/Pie +
 * Grid/Tooltip/Legend/Title/Dataset/DataZoom). Using the full `echarts` package's
 * `EChartsOption` instead would type-check against series this build never registers,
 * silently masking a real "this series type isn't actually installed" bug.
 */
export type ChartOption = ComposeOption<
  | BarSeriesOption
  | LineSeriesOption
  | PieSeriesOption
  | GridComponentOption
  | TooltipComponentOption
  | LegendComponentOption
  | TitleComponentOption
  | DatasetComponentOption
  | DataZoomComponentOption
  | AriaComponentOption
>;

export type ChartRenderer = "canvas" | "svg";

export interface ChartEventHandlers {
  readonly click?: (params: unknown) => void;
  readonly legendselectchanged?: (params: unknown) => void;
}

export interface ChartProps {
  readonly option: ChartOption;
  readonly height?: number | string;
  readonly renderer?: ChartRenderer;
  readonly loading?: boolean;
  readonly empty?: boolean;
  readonly emptyMessage?: string;
  readonly error?: Error | null;
  readonly onRetry?: () => void;
  /** Required, not optional -- a chart with no accessible name has no meaning to a screen-reader user (docs/design-system/06_ACCESSIBILITY_PERFORMANCE.md). */
  readonly ariaLabel: string;
  readonly className?: string;
  readonly onChartReady?: (instance: ECharts) => void;
  readonly onEvents?: ChartEventHandlers;
}

export type ChartTrendDirection = "positive" | "negative" | "neutral";
