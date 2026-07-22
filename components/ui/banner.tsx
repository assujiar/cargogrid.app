/**
 * Banner primitive (PLT-136, CG-S6-PLT-033). Second `components/ui/` primitive this
 * repository builds (after `button.tsx`, `PLT-135`) -- reusable for any persistent,
 * page-level disclosure, not invented solely for the RPD-022 case: `docs/architecture/
 * 09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §2.4 also names a "support-mode banner" as a
 * future consumer of the same shape.
 */

import type { ReactNode } from "react";

const VARIANT_CLASSES = {
  info: "border-info bg-neutral-50 text-neutral-900",
  warning: "border-warning bg-neutral-50 text-neutral-900",
} as const;

export type BannerVariant = keyof typeof VARIANT_CLASSES;

export interface BannerProps {
  readonly variant?: BannerVariant;
  readonly children: ReactNode;
}

export function Banner({ variant = "info", children }: BannerProps) {
  return (
    <div role="note" className={`border-l-4 px-4 py-3 text-sm ${VARIANT_CLASSES[variant]}`}>
      {children}
    </div>
  );
}
