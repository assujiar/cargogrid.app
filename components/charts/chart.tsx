"use client";

/**
 * Low-level Chart component (CargoGrid Chart System) -- ECharts init/dispose, option
 * updates, renderer selection, theme application, responsive resizing, loading state,
 * event registration, accessibility, reduced-motion, and error handling. Deliberately
 * contains no CargoGrid business logic: a preset (`presets/*.tsx`) builds the
 * series-specific `option`, this component only merges it under the shared theme and
 * renders it.
 *
 * Governance: this file (via `use-chart.ts`) is the only place `echarts.init` runs in
 * this repository -- `eslint.config.js`'s `no-restricted-syntax` bans
 * `echarts.init(`/`.init(` calls matching that shape anywhere else, so a future page
 * that tries to instantiate ECharts directly gets a real lint error, not a style
 * suggestion.
 */

import { useMemo, useRef, useSyncExternalStore } from "react";
import { useChart } from "./use-chart.ts";
import { useChartResize } from "./use-chart-resize.ts";
import { useResolvedChartColors } from "./use-chart-colors.ts";
import { buildChartThemeOption } from "../../lib/charts/chart-theme.ts";
import { ChartSkeleton } from "./chart-skeleton.tsx";
import { ChartEmptyState } from "./chart-empty-state.tsx";
import { ChartErrorState } from "./chart-error-state.tsx";
import type { ChartOption, ChartProps } from "../../lib/charts/chart-types.ts";

function subscribeReducedMotion(callback: () => void): () => void {
  const query = window.matchMedia("(prefers-reduced-motion: reduce)");
  query.addEventListener("change", callback);
  return () => query.removeEventListener("change", callback);
}

function getReducedMotionSnapshot(): boolean {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

function getReducedMotionServerSnapshot(): boolean {
  return false;
}

/** `useSyncExternalStore`, not `useEffect`+`useState` -- a boolean primitive snapshot compares correctly via `Object.is` on every call, and this is a real "subscribe to an external system" case (matchMedia's own `change` event), the case that hook exists for. */
function usePrefersReducedMotion(): boolean {
  return useSyncExternalStore(subscribeReducedMotion, getReducedMotionSnapshot, getReducedMotionServerSnapshot);
}

/** One level of merge on the shared theme keys a preset commonly overrides in part (e.g. a preset's own `tooltip.formatter` while keeping the theme's `tooltip.backgroundColor`). A full shallow spread would let a preset's partial `tooltip` object silently clobber the rest of the theme's tooltip styling. */
function mergeWithTheme(theme: ChartOption, option: ChartOption): ChartOption {
  return {
    ...theme,
    ...option,
    tooltip: { ...(theme.tooltip as object), ...(option.tooltip as object) },
    legend: { ...(theme.legend as object), ...(option.legend as object) },
    grid: { ...(theme.grid as object), ...(option.grid as object) },
    textStyle: { ...(theme.textStyle as object), ...(option.textStyle as object) },
  };
}

export function Chart({
  option,
  height = 280,
  renderer = "canvas",
  loading = false,
  empty = false,
  emptyMessage,
  error = null,
  onRetry,
  ariaLabel,
  className,
  onChartReady,
  onEvents,
}: ChartProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const reducedMotion = usePrefersReducedMotion();
  const colors = useResolvedChartColors();

  // A derived value, not effect+state -- "you might not need an effect" (react.dev):
  // themedOption is a pure function of colors/reducedMotion/option, computed during render.
  const themedOption = useMemo(() => {
    if (!colors) {
      return null;
    }
    const theme = buildChartThemeOption(colors, { reducedMotion });
    return mergeWithTheme(theme, option);
  }, [colors, reducedMotion, option]);

  const instanceRef = useChart({
    containerRef,
    option: loading || empty || error ? null : themedOption,
    renderer,
    onChartReady,
    onEvents,
  });

  useChartResize(containerRef, () => instanceRef.current?.resize());

  if (loading) {
    return <ChartSkeleton height={height} />;
  }
  if (error) {
    return <ChartErrorState error={error} onRetry={onRetry} height={height} />;
  }
  if (empty) {
    return <ChartEmptyState height={height} title={emptyMessage} />;
  }

  return <div ref={containerRef} role="img" aria-label={ariaLabel} style={{ height }} className={className} />;
}
