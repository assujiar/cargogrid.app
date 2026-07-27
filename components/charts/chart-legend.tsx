"use client";

/**
 * Accessible, keyboard-focusable legend (CargoGrid Chart System) -- real `<button>`
 * elements toggling series visibility via `chart.dispatchAction`, for the cases where
 * ECharts' own canvas-rendered legend (the default, configured in `chart-theme.ts`,
 * fine for mouse/hover users) isn't enough on its own. A preset that renders this
 * should set `legend: { show: false }` in its own option to avoid showing two legends
 * at once -- not done automatically by this component, since some presets are fine
 * with the canvas legend alone and this component is opt-in.
 */

import type { ECharts } from "echarts/core";

export interface ChartLegendItem {
  readonly name: string;
  readonly color: string;
  readonly selected: boolean;
}

export function ChartLegend({ items, instance }: { readonly items: readonly ChartLegendItem[]; readonly instance: ECharts | null }) {
  return (
    <div role="group" aria-label="Series visibility" className="flex flex-wrap gap-3 px-2 text-xs">
      {items.map((item) => (
        <button
          key={item.name}
          type="button"
          aria-pressed={item.selected}
          onClick={() => instance?.dispatchAction({ type: "legendToggleSelect", name: item.name })}
          className={`flex items-center gap-1.5 rounded px-1.5 py-0.5 ${item.selected ? "text-text-primary" : "text-neutral-400 line-through"}`}
        >
          <span aria-hidden="true" className="h-2 w-2 rounded-full" style={{ backgroundColor: item.selected ? item.color : "var(--color-neutral-300)" }} />
          {item.name}
        </button>
      ))}
    </div>
  );
}
