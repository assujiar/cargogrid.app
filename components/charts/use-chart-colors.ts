"use client";

/**
 * Resolves chart colors once, client-side (CargoGrid Chart System). Uses
 * `useSyncExternalStore` (not `useEffect`+`useState`) -- the correct primitive for a
 * value that only exists client-side and needs a real value during the client's first
 * render, without an SSR/hydration mismatch. Module-level caching keeps the snapshot
 * reference stable across calls (a fresh object every call would make
 * `useSyncExternalStore` think the value keeps changing, since CargoGrid has no live
 * chart-theme-switching mechanism to actually subscribe to, `subscribe` is a no-op).
 */

import { useSyncExternalStore } from "react";
import { resolveChartColors, type ResolvedChartColors } from "../../lib/charts/chart-colors.ts";

let cachedColors: ResolvedChartColors | null = null;

function subscribe(): () => void {
  return () => {};
}

function getSnapshot(): ResolvedChartColors {
  if (!cachedColors) {
    cachedColors = resolveChartColors();
  }
  return cachedColors;
}

function getServerSnapshot(): ResolvedChartColors | null {
  return null;
}

export function useResolvedChartColors(): ResolvedChartColors | null {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}
