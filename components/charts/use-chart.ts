"use client";

/**
 * ECharts instance lifecycle hook (CargoGrid Chart System) -- the only place in this
 * repository that calls `echarts.init`/`dispose` (governance: `eslint.config.js` bans
 * `echarts.init(` outside `components/charts/`). Registers exactly the modules this
 * build uses (Bar/Line/Pie + Grid/Tooltip/Legend/Title/Dataset/DataZoom +
 * Canvas/SVG renderers) once at module load -- a future preset needing a series type
 * not registered here will fail loudly (a real "unregistered series" ECharts error),
 * which is the intended signal to add it here rather than to a feature page.
 */

import * as echarts from "echarts/core";
import { BarChart, LineChart, PieChart } from "echarts/charts";
import {
  GridComponent,
  TooltipComponent,
  LegendComponent,
  TitleComponent,
  DatasetComponent,
  DataZoomComponent,
  AriaComponent,
} from "echarts/components";
import { CanvasRenderer, SVGRenderer } from "echarts/renderers";
import { useEffect, useRef, type RefObject } from "react";
import type { ECharts } from "echarts/core";
import type { ChartOption, ChartRenderer, ChartEventHandlers } from "../../lib/charts/chart-types.ts";

echarts.use([
  BarChart,
  LineChart,
  PieChart,
  GridComponent,
  TooltipComponent,
  LegendComponent,
  TitleComponent,
  DatasetComponent,
  DataZoomComponent,
  AriaComponent,
  CanvasRenderer,
  SVGRenderer,
]);

export interface UseChartArgs {
  readonly containerRef: RefObject<HTMLDivElement | null>;
  readonly option: ChartOption | null;
  readonly renderer: ChartRenderer;
  readonly onChartReady?: (instance: ECharts) => void;
  readonly onEvents?: ChartEventHandlers;
}

export function useChart({ containerRef, option, renderer, onChartReady, onEvents }: UseChartArgs): RefObject<ECharts | null> {
  const instanceRef = useRef<ECharts | null>(null);
  const onChartReadyRef = useRef(onChartReady);
  const onEventsRef = useRef(onEvents);

  // Keeps the latest callback available to the init effect below without listing it as
  // a dependency (which would tear down/re-init the whole chart on every new inline
  // function) -- writing a ref's `.current` must happen in an effect, never during
  // render (react-hooks/refs).
  useEffect(() => {
    onChartReadyRef.current = onChartReady;
    onEventsRef.current = onEvents;
  });

  // Init once per container/renderer -- a renderer change requires a fresh instance (ECharts cannot swap renderer on a live instance).
  useEffect(() => {
    const container = containerRef.current;
    if (!container) {
      return;
    }

    const instance = echarts.init(container, undefined, { renderer });
    instanceRef.current = instance;
    onChartReadyRef.current?.(instance);

    const handlers = onEventsRef.current;
    if (handlers?.click) {
      instance.on("click", handlers.click);
    }
    if (handlers?.legendselectchanged) {
      instance.on("legendselectchanged", handlers.legendselectchanged);
    }

    return () => {
      instance.dispose();
      instanceRef.current = null;
    };
  }, [containerRef, renderer]);

  // Update options on an existing instance -- never re-init just to change data (the mission's own "do not repeatedly initialize a new chart instance on each render" rule).
  useEffect(() => {
    if (instanceRef.current && option) {
      instanceRef.current.setOption(option, { notMerge: false });
    }
  }, [option]);

  return instanceRef;
}
