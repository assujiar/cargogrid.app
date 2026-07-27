/**
 * Resolves CargoGrid's `--chart-*` CSS custom properties (`app/globals.css`) to
 * concrete color strings (CargoGrid Chart System). Canvas/SVG rendering cannot consume
 * a live `var(--x)` reference the way a Tailwind class can -- `getComputedStyle` must
 * resolve it once, client-side, at chart-init/theme-change time. Client-only by
 * construction (`getComputedStyle` doesn't exist during SSR) -- callers must only
 * invoke this after mount.
 */

const CHART_TOKEN_MAP = {
  primary: "--chart-primary",
  secondary: "--chart-secondary",
  tertiary: "--chart-tertiary",
  quaternary: "--chart-quaternary",
  positive: "--chart-positive",
  warning: "--chart-warning",
  negative: "--chart-negative",
  neutral: "--chart-neutral",
  forecast: "--chart-forecast",
  target: "--chart-target",
  comparison: "--chart-comparison",
  grid: "--chart-grid",
  axis: "--chart-axis",
  axisMuted: "--chart-axis-muted",
  tooltipBackground: "--chart-tooltip-background",
  tooltipForeground: "--chart-tooltip-foreground",
  tooltipBorder: "--chart-tooltip-border",
  selection: "--chart-selection",
} as const;

export type ResolvedChartColors = Record<keyof typeof CHART_TOKEN_MAP, string>;

/** The categorical series order every multi-series preset (Bar/Line comparisons) cycles through. */
export function categoricalPalette(colors: ResolvedChartColors): readonly string[] {
  return [colors.primary, colors.secondary, colors.tertiary, colors.quaternary];
}

export function resolveChartColors(root: HTMLElement = document.documentElement): ResolvedChartColors {
  const styles = getComputedStyle(root);
  const entries = (Object.entries(CHART_TOKEN_MAP) as [keyof typeof CHART_TOKEN_MAP, string][]).map(
    ([key, cssVar]) => [key, styles.getPropertyValue(cssVar).trim()] as const,
  );
  return Object.fromEntries(entries) as ResolvedChartColors;
}
