# CargoGrid Chart System (Apache ECharts)

**Added by:** CargoGrid UI Modernization checkpoint 5 (2026-07-26, out-of-band — not a numbered `CG-S*-*` Commercial-phase prompt). Continues the same out-of-band design-system track as checkpoints 1–4 (`docs/design-system/07_GAP_ANALYSIS_AND_ROADMAP.md`). Full narrative: `07_GAP_ANALYSIS_AND_ROADMAP.md` §11.

## 1. Why Apache ECharts, and its license

Chosen by explicit user decision (this session), not unilaterally: free/open-source, Apache License 2.0 (no subscription/royalty, commercial use permitted), Canvas and SVG rendering, high-volume dataset support, and a broader chart-type vocabulary than typical dashboard libraries (line/bar/pie/scatter/funnel/heatmap/map/Sankey/treemap/sunburst/gauge/graph/boxplot/custom series) — most of which this checkpoint does not yet use, disclosed in §9.

**Third-party notice:** `THIRD_PARTY_NOTICES.md` (repo root) records Apache ECharts' copyright/license per the Apache Software Foundation's own NOTICE requirement.

## 2. Architecture

```
lib/charts/                      -- pure, testable logic (this repo's own convention: pure logic in lib/, not components/ — see lib/tables/pagination-range.ts precedent)
  chart-types.ts                 -- ChartOption (a narrow ComposeOption over only the registered series/components), ChartProps
  chart-colors.ts                -- resolves --chart-* CSS custom properties to concrete color strings (client-only)
  chart-theme.ts                 -- shared grid/axis/legend/tooltip/aria option fragment every preset merges under
  chart-formatters.ts            -- id-ID currency/number/percent/duration formatters (unit-tested)
  chart-tooltip.ts               -- shared, HTML-escaped tooltip content builder (unit-tested)

components/charts/                -- presentational/interactive layer
  chart.tsx                      -- the ONE low-level component that calls echarts.init/dispose (via use-chart.ts)
  use-chart.ts                   -- ECharts instance lifecycle hook; registers exactly the modules this build uses
  use-chart-colors.ts            -- useSyncExternalStore wrapper around chart-colors.ts (SSR-safe)
  use-chart-resize.ts            -- debounced ResizeObserver hook
  chart-card.tsx / chart-header.tsx / chart-actions.tsx -- the shared dashboard-widget shell
  chart-legend.tsx               -- optional keyboard-focusable legend (opt-in; ECharts' own canvas legend is the default)
  chart-skeleton.tsx / chart-empty-state.tsx / chart-error-state.tsx -- thin wrappers over the real Skeleton/EmptyState/ErrorState primitives
  chart-accessible-table.tsx     -- renders the same series data through the real DataTable
  chart-export.ts                -- PNG (ECharts getDataURL) and CSV (server/policies/csv-export-sanitize.ts, reused not duplicated) export
  presets/
    trend-chart.tsx               -- line, time-series (IMPLEMENTED)
    comparison-bar-chart.tsx      -- bar, category comparison (IMPLEMENTED)
    donut-chart.tsx               -- pie, small part-to-whole (IMPLEMENTED)
```

**Data flow** (the mission's own requested shape): `Raw data → typed props (categories/series/slices) → preset builds ChartOption → Chart merges the shared theme → ECharts renders`. No preset receives an unprocessed database row — every preset's props are already-shaped view models the caller builds.

## 3. Installation

```
pnpm add echarts
```

Modular imports only, from `echarts/core` (`use-chart.ts`) — `BarChart`/`LineChart`/`PieChart`, `GridComponent`/`TooltipComponent`/`LegendComponent`/`TitleComponent`/`DatasetComponent`/`DataZoomComponent`/`AriaComponent`, `CanvasRenderer`/`SVGRenderer`. Adding a new series type requires registering it there first — an unregistered series type fails loudly at runtime (the intended signal, not a silent no-op).

## 4. Next.js integration

Every file under `components/charts/` that touches ECharts is `"use client"`. `Chart` never calls `echarts.init` during a server-rendered pass — it renders a bare `<div>` server-side; the real instance is created in a `useEffect` (`use-chart.ts`), guaranteed client-only. Instances are disposed on unmount. Colors (`use-chart-colors.ts`) are resolved via `useSyncExternalStore`, not `useEffect`+`useState` — the SSR-safe, no-hydration-mismatch primitive for a value that only exists client-side. Resize is handled by a debounced `ResizeObserver` (`use-chart-resize.ts`), not a bare `window.resize` listener, since a chart inside a card/drawer/tab resizes when its own container changes.

**A real bug found and fixed during authoring:** the first draft resolved colors inline during render (not in an effect/store), which works during a client-only re-render but computes an empty result during Next's server-rendered pass of the "use client" boundary and — critically — never self-corrects afterward, since nothing forces a re-render. Fixed by extracting `use-chart-colors.ts` as a `useSyncExternalStore` hook.

## 5. Theme integration

`lib/charts/chart-theme.ts` translates resolved `--chart-*` tokens (`app/globals.css`) into the shared grid/axis/legend/tooltip/aria option every preset's own option is merged under (`chart.tsx`'s `mergeWithTheme`, a one-level-deep merge so a preset can override e.g. `tooltip.formatter` without clobbering `tooltip.backgroundColor`). **No second `echarts.registerTheme('light'|'dark', ...)` exists** — CargoGrid has no tenant-facing dark theme token set decided anywhere (`docs/design-system/00_INDEX.md`'s own disclosed gap), so there is nothing for a chart theme to switch to yet; when one is decided, this adapter reads whichever tokens are resolved at call time, unchanged.

## 6. Adding a chart

1. Check `lib/design-system/component-registry.ts`'s `ChartsAndAnalytics` category — does an existing preset already fit?
2. If yes, use it directly (`TrendChart`/`ComparisonBarChart`/`DonutChart` today).
3. If a preset needs a small, generally-reusable extension, extend it.
4. If the visualization is genuinely unique, use the low-level `Chart` directly with a hand-built `ChartOption` (see `/internal/design-system/charts`'s "States" demo).
5. If it's reusable, add it as a new preset under `components/charts/presets/`, register the series type in `use-chart.ts` if new, add it to `component-registry.ts`, add it to the showcase, document it here.
6. Never call `echarts.init(...)` directly in a feature page — `eslint.config.js`'s `no-restricted-syntax` rule bans it outside `components/charts/` and fires as a real lint error (verified during authoring: a deliberate violation in a throwaway file was caught).

## 7. Chart selection rules

| Question | Chart |
|---|---|
| Time-series trend (revenue, cost, margin, SLA, forecast vs. actual) | `TrendChart` |
| Category comparison (business unit, salesperson, customer ranking, win/loss reasons) | `ComparisonBarChart` (horizontal for long labels/many categories) |
| Small part-to-whole, ≤~5 categories, ranking not the point | `DonutChart` |
| Status/revenue composition over time | Stacked bar — `DOCUMENTED_ONLY` |
| Lead-to-win/opportunity/approval funnel | Funnel — `DOCUMENTED_ONLY` |
| Margin bridge / cost variance decomposition | Waterfall — `DOCUMENTED_ONLY` |
| SLA/capacity/target attainment | Gauge — `DOCUMENTED_ONLY`; prefer `KpiCard`+`Progress` unless a gauge adds real analytical value |
| Activity density by day/hour | Calendar heatmap — `DOCUMENTED_ONLY` |
| Flow (lead→conversion, shipment O–D, job handoff) | Sankey — `DOCUMENTED_ONLY` |
| Geographic lanes/coverage | Map — `DOCUMENTED_ONLY`, no geo data source exists yet |
| Correlation (margin vs. revenue, cost vs. distance) | Scatter/distribution — `DOCUMENTED_ONLY` |

Avoid: 3D charts, decorative gradients, rainbow palettes, pie charts with many categories, gauges for a value a plain number/progress bar communicates better.

## 8. Accessibility

- ECharts' own `aria: { enabled: true }` is set in the shared theme (`AriaComponent` registered in `use-chart.ts`).
- Every `Chart` render requires `ariaLabel` (a TypeScript-required prop, not optional) and wraps its container in `role="img"`.
- Every preset renders a real "View as table" toggle to a `ChartAccessibleTable` (the real `DataTable`, not a second implementation) — a genuine accessible alternative, not a decorative sr-only stub.
- Non-color signal: `DonutChart` slices always carry a text label (`{b}\n{d}%`); `TrendChart`'s forecast series is dashed, never distinguished by color alone; `ChartHeader`'s trend indicator uses a ▲/▼/– glyph, color is additive.
- Reduced motion: `Chart` reads `prefers-reduced-motion` via `useSyncExternalStore` (live-reactive to an OS-level toggle) and disables ECharts' animation entirely when set.
- Tooltip content is built through `buildTooltipHtml` (`lib/charts/chart-tooltip.ts`), which HTML-escapes every interpolated value — verified by a dedicated unit test injecting `<script>`/`<img onerror>` payloads.
- `ChartLegend` (opt-in, `components/charts/chart-legend.tsx`) provides a real keyboard-focusable `<button>`-based legend for a preset that needs full keyboard parity beyond ECharts' own canvas legend (not wired into any preset by default, to avoid showing two legends at once).

## 9. Responsive behavior

`useChartResize` (`ResizeObserver`, 100ms debounce) calls `instance.resize()` whenever the chart's own container changes size — verified live in the showcase's desktop/tablet/mobile viewport control against a real chart. No per-preset breakpoint logic exists beyond ECharts' own `containLabel: true` (keeps axis labels from being clipped) — legend wrapping, axis label density adjustments, and touch-target sizing for dense mobile layouts remain `DOCUMENTED_ONLY` refinements, not built this checkpoint.

## 10. Export

`chart-export.ts`: `exportChartAsPng` (ECharts' own `getDataURL()`, real and working) and `exportChartDataAsCsv` (reuses `server/policies/csv-export-sanitize.ts`'s `rowsToSafeCsv` — the same OWASP formula-injection guard Commercial Reports already uses, not a duplicate). **Not built:** a dedicated print flow (a bare `window.print()` of the whole page is not a real print experience) and SVG export (the renderer must be set to `"svg"` at init time for `getSvgDataURL()` to apply — not wired into `ChartActions` this checkpoint).

## 11. Performance

Modular imports (§3) keep unused series/components out of the bundle. `Chart` never re-initializes an instance to update data — `use-chart.ts`'s second effect calls `setOption` on the existing instance. Colors are resolved once and cached module-level (`use-chart-colors.ts`). **Not built/verified this checkpoint:** progressive rendering, sampling, and "large mode" for datasets beyond what the 3 real presets' mock data exercises (≤200 points) — no real consumer yet pushes volume high enough to need them, and building that tuning speculatively risks guessing the wrong knobs.

## 12. Testing

Unit-tested (pure functions, `node:test`): `lib/charts/chart-formatters.test.ts` (14 cases — compact-number/currency/count/percent/duration formatting), `lib/charts/chart-tooltip.test.ts` (2 cases — HTML escaping, conditional comparison row). **Live-verified via Playwright, not a formal e2e suite entry:** all 3 presets render real `<canvas>` elements; Loading/Empty/Error states render the correct component and Retry recovers; "View as table" renders the real accessible table with `null` values shown as `—`, never a fabricated `0`; the bar-chart label/legend overlap found during this verification pass was fixed (`chart-theme.ts` grid spacing) before this checkpoint closed. **Not built:** a dedicated `test:e2e` fixture entry (the repository's Playwright/axe-core suite targets real business screens, same disclosed condition as checkpoints 1–4's own showcase work).

## 13. Migration of existing visualizations

Audited every file under `app/` before writing any chart code: **zero existing charts or visualizations exist anywhere in this repository.** `commercial/dashboard/page.tsx` (COM-158) renders every metric as a bucket list/table. Full migration-map entry: `lib/design-system/migration-map.ts` / `/internal/design-system/duplicates`. The dashboard is the natural first real consumer for `TrendChart`/`DonutChart` (its Pipeline/Win-Loss sections map cleanly) — deliberately not wired this checkpoint, since the dashboard's multi-currency grouping and permission-masked (`valueMasked`) values need careful, correctness-focused handling to convert safely, judged a distinct follow-up rather than rushed into this diff.

## 14. Examples

See `/internal/design-system/charts` (gated the same as the rest of the showcase) for live, real, mock-data examples of `ChartCard`+`TrendChart` (with forecast), `ComparisonBarChart`, `DonutChart`, and the low-level `Chart`'s loading/empty/error states with an interactive state switcher.

## 15. Governance

Apache ECharts is the only approved chart engine. `eslint.config.js`'s `no-restricted-syntax` rule bans `echarts.init(...)` outside `components/charts/**` (verified firing against a deliberate violation during authoring). No page-specific ECharts theme, hardcoded chart color, duplicate tooltip/currency formatter, duplicate loading state, or duplicate export utility should ever be written — this document and `lib/charts/`/`components/charts/` are the one shared home for all of it.
