"use client";

/**
 * Debounced container-resize hook (CargoGrid Chart System). `Chart` (chart.tsx) uses
 * this instead of a bare `window.addEventListener("resize", ...)` -- a chart embedded
 * in a card/drawer/tab resizes when its own container changes (sidebar collapse, tab
 * switch, viewport-preview toggle in the showcase), not only on a window resize.
 */

import { useEffect, useRef, type RefObject } from "react";

const RESIZE_DEBOUNCE_MS = 100;

export function useChartResize(containerRef: RefObject<HTMLDivElement | null>, onResize: () => void): void {
  const onResizeRef = useRef(onResize);

  // Ref writes must happen in an effect, never during render (react-hooks/refs).
  useEffect(() => {
    onResizeRef.current = onResize;
  });

  useEffect(() => {
    const container = containerRef.current;
    if (!container) {
      return;
    }

    let timeoutId: ReturnType<typeof setTimeout> | null = null;
    const observer = new ResizeObserver(() => {
      if (timeoutId !== null) {
        clearTimeout(timeoutId);
      }
      timeoutId = setTimeout(() => onResizeRef.current(), RESIZE_DEBOUNCE_MS);
    });

    observer.observe(container);
    return () => {
      if (timeoutId !== null) {
        clearTimeout(timeoutId);
      }
      observer.disconnect();
    };
  }, [containerRef]);
}
