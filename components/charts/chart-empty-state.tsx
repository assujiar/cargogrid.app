/**
 * Chart empty state (CargoGrid Chart System) -- a thin, chart-flavored wrapper over
 * the real `EmptyState` primitive (never a second implementation). `activeFilters`,
 * when given, is rendered so the viewer understands *why* there's no data, per the
 * mission's own "explain which filters are active" requirement.
 */

import { EmptyState } from "../ui/empty-state.tsx";

export interface ChartEmptyStateProps {
  readonly title?: string;
  readonly activeFilters?: string;
  readonly height?: number | string;
}

export function ChartEmptyState({ title = "No data for this view", activeFilters, height = 280 }: ChartEmptyStateProps) {
  return (
    <div style={{ height }} className="flex items-center justify-center">
      <EmptyState
        title={title}
        description={activeFilters ? `Active filters: ${activeFilters}` : "Try widening the date range or clearing filters."}
      />
    </div>
  );
}
