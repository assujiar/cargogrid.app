"use client";

import type { ReactNode } from "react";
import { useShowcaseChrome, type ShowcaseViewport } from "./chrome-context.tsx";

const VIEWPORT_WIDTHS: Record<ShowcaseViewport, string> = {
  desktop: "100%",
  tablet: "768px",
  mobile: "375px",
};

const VIEWPORT_SIZES: readonly ShowcaseViewport[] = ["desktop", "tablet", "mobile"];

export function ViewportControl() {
  const { viewport, setViewport } = useShowcaseChrome();

  return (
    <div className="flex flex-col gap-1">
      <span className="text-xs font-medium text-[var(--ds-text-secondary)]">Responsive preview width</span>
      <div role="group" aria-label="Viewport size" className="flex gap-1">
        {VIEWPORT_SIZES.map((size) => (
          <button
            key={size}
            type="button"
            aria-pressed={viewport === size}
            onClick={() => setViewport(size)}
            className={`flex-1 rounded-md border px-2 py-1 text-xs capitalize ${
              viewport === size ? "border-primary bg-primary text-neutral-50" : "border-[var(--ds-border)] text-[var(--ds-text)]"
            }`}
          >
            {size}
          </button>
        ))}
      </div>
    </div>
  );
}

/** Wraps a section's live real-component demos so the "desktop/tablet/mobile" control above actually resizes them. Real components render inside at real size — never a screenshot. */
export function ViewportFrame({ children }: { children: ReactNode }) {
  const { viewport } = useShowcaseChrome();

  return (
    <div
      style={{ maxWidth: VIEWPORT_WIDTHS[viewport] }}
      className="mx-auto overflow-x-auto rounded-md border border-[var(--ds-border)] bg-[var(--ds-surface)] p-4 transition-[max-width] duration-200 motion-reduce:transition-none"
    >
      {children}
    </div>
  );
}
