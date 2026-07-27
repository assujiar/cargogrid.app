"use client";

/**
 * ChartCard (CargoGrid Chart System) -- the shared dashboard-widget shell every chart
 * preset renders inside: header (title/KPI/trend), actions (period/refresh/export/
 * fullscreen), chart content, optional footer insight. Built entirely from existing
 * shared primitives (`Card`, `IconButton`, `DropdownMenu`, `Select`) -- no card styling
 * recreated here.
 */

import type { ReactNode } from "react";
import { Card } from "../ui/card.tsx";
import { ChartHeader, type ChartHeaderProps } from "./chart-header.tsx";
import { ChartActions, type ChartActionsProps } from "./chart-actions.tsx";

export interface ChartCardProps extends ChartHeaderProps, ChartActionsProps {
  readonly children: ReactNode;
  readonly footerInsight?: string;
  readonly className?: string;
}

export function ChartCard({
  title,
  description,
  kpiValue,
  trendLabel,
  trendDirection,
  periods,
  period,
  onPeriodChange,
  onRefresh,
  onExportPng,
  onExportCsv,
  onFullscreen,
  moreActions,
  children,
  footerInsight,
  className,
}: ChartCardProps) {
  return (
    <Card className={className}>
      <div className="flex items-start justify-between gap-2">
        <ChartHeader title={title} description={description} kpiValue={kpiValue} trendLabel={trendLabel} trendDirection={trendDirection} />
        <ChartActions
          periods={periods}
          period={period}
          onPeriodChange={onPeriodChange}
          onRefresh={onRefresh}
          onExportPng={onExportPng}
          onExportCsv={onExportCsv}
          onFullscreen={onFullscreen}
          moreActions={moreActions}
        />
      </div>
      <div className="mt-3">{children}</div>
      {footerInsight ? <p className="mt-2 text-xs text-text-secondary">{footerInsight}</p> : null}
    </Card>
  );
}
