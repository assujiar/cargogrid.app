/**
 * CargoGrid ECharts theme adapter (CargoGrid Chart System). Translates resolved
 * `--chart-*` tokens (`chart-colors.ts`) into the shared grid/axis/tooltip/legend
 * option fragment every preset spreads into its own `option` -- this is the one place
 * grid-line weight, axis color, and tooltip surface styling are decided, so no preset
 * hardcodes a color or reinvents its own tooltip box.
 *
 * Never a second, competing "echarts-light"/"echarts-dark" theme registered via
 * `echarts.registerTheme` -- CargoGrid has no tenant-facing dark theme token set
 * decided anywhere yet (`docs/design-system/00_INDEX.md`'s own disclosed gap), so this
 * adapter reads whichever tokens are resolved at call time (light today) rather than
 * inventing a second palette to switch to.
 */

import type { ResolvedChartColors } from "./chart-colors.ts";
import type { ChartOption } from "./chart-types.ts";

export interface ChartThemeOptions {
  readonly reducedMotion: boolean;
}

/** The shared grid/axis/legend/animation baseline every preset's own `buildOption()` spreads underneath its series-specific fields. */
export function buildChartThemeOption(colors: ResolvedChartColors, options: ChartThemeOptions): ChartOption {
  return {
    aria: { enabled: true },
    animation: !options.reducedMotion,
    animationDuration: options.reducedMotion ? 0 : 300,
    textStyle: {
      fontFamily: "Inter, ui-sans-serif, system-ui, -apple-system, 'Segoe UI', sans-serif",
      color: colors.axis,
    },
    grid: {
      left: 8,
      right: 16,
      top: 32,
      // Room for both the category-axis labels and the legend below them without
      // overlapping (found for real: long category labels like "Requirements
      // gathering" collided with the legend at bottom: 8).
      bottom: 40,
      containLabel: true,
    },
    legend: {
      type: "scroll",
      bottom: 0,
      icon: "circle",
      itemWidth: 8,
      itemHeight: 8,
      textStyle: { color: colors.axis, fontSize: 12 },
    },
    tooltip: {
      trigger: "axis",
      backgroundColor: colors.tooltipBackground,
      borderColor: colors.tooltipBorder,
      borderWidth: 1,
      textStyle: { color: colors.tooltipForeground, fontSize: 12 },
      extraCssText: "box-shadow: 0 2px 8px rgba(15, 23, 42, 0.1); border-radius: 6px;",
    },
  };
}

/** Shared category-axis styling (light grid, no heavy border) every preset's x/y-axis option merges with. */
export function buildChartAxisOption(colors: ResolvedChartColors) {
  return {
    axisLine: { lineStyle: { color: colors.axisMuted } },
    axisTick: { show: false },
    axisLabel: { color: colors.axis, fontSize: 11 },
    splitLine: { lineStyle: { color: colors.grid, type: "dashed" as const } },
  };
}
