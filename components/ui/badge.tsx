/**
 * Badge primitive (CargoGrid Design System Expansion, docs/design-system/02_COMPONENTS.md).
 * Small inline label for counts, tags, and non-status metadata (e.g. a record count or a
 * free-form tag). For canonical business-entity status, use `StatusBadge`
 * (`components/ui/status-badge.tsx`) instead -- it binds the visual treatment to a fixed
 * semantic tone and requires a text label, never color alone.
 */

import type { ReactNode } from "react";

const TONE_CLASSES = {
  neutral: "bg-neutral-100 text-neutral-700",
  primary: "bg-primary/10 text-primary",
} as const;

export type BadgeTone = keyof typeof TONE_CLASSES;

export interface BadgeProps {
  readonly tone?: BadgeTone;
  readonly children: ReactNode;
}

export function Badge({ tone = "neutral", children }: BadgeProps) {
  return (
    <span className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ${TONE_CLASSES[tone]}`}>
      {children}
    </span>
  );
}
