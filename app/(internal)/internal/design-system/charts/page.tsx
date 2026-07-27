"use client";

/**
 * Charts and Analytics showcase (CargoGrid Chart System, checkpoint 5). Real
 * components, mock data only. Every preset here is genuinely interactive (real
 * ECharts instances) -- not a screenshot.
 */

import { useState } from "react";
import { TrendChart } from "../../../../../components/charts/presets/trend-chart.tsx";
import { ComparisonBarChart } from "../../../../../components/charts/presets/comparison-bar-chart.tsx";
import { DonutChart } from "../../../../../components/charts/presets/donut-chart.tsx";
import { ChartCard } from "../../../../../components/charts/chart-card.tsx";
import { Chart } from "../../../../../components/charts/chart.tsx";
import { formatCurrency, formatPercent } from "../../../../../lib/charts/chart-formatters.ts";
import { MOCK_REVENUE_TREND, MOCK_PIPELINE_BY_STAGE, MOCK_WIN_LOSS } from "../../../../../lib/design-system/mock-chart-data.ts";

export default function ChartsPage() {
  const [demoState, setDemoState] = useState<"success" | "loading" | "empty" | "error">("success");

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-xl font-semibold">Charts and Analytics</h1>
        <p className="mt-1 text-sm text-[var(--ds-text-secondary)]">
          Apache ECharts (v6, Apache License 2.0) is the only approved chart engine (
          <code>docs/design-system/09_CHARTS.md</code>). Every chart below renders through the real{" "}
          <code>components/charts/</code> layer — never a chart instantiated directly on this page.
        </p>
      </div>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">ChartCard — Revenue Trend (with forecast)</h2>
        <ChartCard
          title="Revenue Trend"
          kpiValue={formatCurrency(4_820_000_000, "IDR")}
          trendLabel={`${formatPercent(8.4, { signed: true })} vs last month`}
          trendDirection="positive"
          footerInsight="Forecast projects continued growth into July."
          onRefresh={() => alert("Demo only — would refetch")}
          onExportPng={() => alert("Demo only — would export PNG")}
          onExportCsv={() => alert("Demo only — would export CSV")}
          periods={[
            { value: "6m", label: "Last 6 months" },
            { value: "12m", label: "Last 12 months" },
          ]}
          period="6m"
        >
          <TrendChart
            ariaLabel="Revenue trend, last 6 months, with July forecast"
            categories={MOCK_REVENUE_TREND.categories}
            series={[
              { name: "Actual", data: MOCK_REVENUE_TREND.actual },
              { name: "Forecast", data: MOCK_REVENUE_TREND.forecast, isForecast: true },
            ]}
            valueFormatter={(value) => formatCurrency(value, "IDR")}
          />
        </ChartCard>
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">Comparison Bar Chart — Pipeline by stage</h2>
        <ChartCard title="Pipeline by Stage">
          <ComparisonBarChart
            ariaLabel="Open opportunities by pipeline stage"
            categories={MOCK_PIPELINE_BY_STAGE.categories}
            series={[{ name: "Opportunities", data: MOCK_PIPELINE_BY_STAGE.values }]}
            valueFormatter={(value) => `${value} opportunities`}
          />
        </ChartCard>
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">Donut Chart — Win/Loss ratio</h2>
        <p className="text-xs text-[var(--ds-text-secondary)]">Tone is semantic (positive/negative), not an arbitrary categorical color — Won is never accidentally red.</p>
        <ChartCard title="Win / Loss">
          <DonutChart ariaLabel="Won vs. lost opportunities this quarter" slices={MOCK_WIN_LOSS} valueFormatter={(value) => `${value} opportunities`} />
        </ChartCard>
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">States</h2>
        <div className="flex gap-2">
          {(["success", "loading", "empty", "error"] as const).map((state) => (
            <button
              key={state}
              type="button"
              onClick={() => setDemoState(state)}
              className={`rounded-md border px-2 py-1 text-xs capitalize ${demoState === state ? "border-primary bg-primary text-neutral-50" : "border-[var(--ds-border)]"}`}
            >
              {state}
            </button>
          ))}
        </div>
        <Chart
          ariaLabel="Demo chart state"
          height={220}
          loading={demoState === "loading"}
          empty={demoState === "empty"}
          emptyMessage="No shipments in the selected date range"
          error={demoState === "error" ? new Error("DemoError") : null}
          onRetry={() => setDemoState("success")}
          option={{
            xAxis: { type: "category", data: ["Mon", "Tue", "Wed"] },
            yAxis: { type: "value" },
            series: [{ type: "bar", data: [12, 19, 7] }],
          }}
        />
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">Not built this checkpoint</h2>
        <ul className="list-disc pl-5 text-sm text-[var(--ds-text-secondary)]">
          <li>Stacked bar, funnel, waterfall, gauge, calendar heatmap, Sankey, map, scatter/distribution presets — no real consumer/data model exists yet for any of them.</li>
          <li>Drill-down wired to real routes/permissions — no real chart consumer exists in the app yet to wire it to.</li>
          <li>A dedicated print flow (a bare page print is not a real print experience) — PNG/CSV export are real and working.</li>
          <li>Full e2e matrix across every state × viewport × theme combination — verified live via Playwright for the states above instead.</li>
        </ul>
      </section>
    </div>
  );
}
