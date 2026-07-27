/**
 * Mock chart data for `/internal/design-system/charts` (CargoGrid Chart System
 * showcase). Literal, invented values -- never fetched, never connected to a live
 * query, consistent with `lib/design-system/mock-business-data.ts`'s own discipline.
 */

export const MOCK_REVENUE_TREND = {
  categories: ["Feb", "Mar", "Apr", "May", "Jun", "Jul"],
  actual: [3_200_000_000, 3_650_000_000, 3_400_000_000, 4_100_000_000, 4_820_000_000, null],
  // Overlaps the last actual point (Jun) so the dashed forecast line visually connects, then projects one month ahead.
  forecast: [null, null, null, null, 4_820_000_000, 5_100_000_000],
};

export const MOCK_PIPELINE_BY_STAGE = {
  categories: ["Qualifying", "Requirements gathering", "Ready for costing"],
  values: [12, 8, 5],
};

export const MOCK_WIN_LOSS = [
  { name: "Won", value: 18, tone: "positive" as const },
  { name: "Lost", value: 7, tone: "negative" as const },
];
