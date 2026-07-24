/**
 * StatusBadge primitive (CargoGrid Design System Expansion, docs/design-system/
 * 02_COMPONENTS.md). Renders one of the platform's fixed semantic tones -- never a
 * tenant/brand color, `tone` is a closed union over `--color-success/warning/danger/
 * info` -- plus a mandatory text label. This is the presentational half of
 * docs/standards/DESIGN_SYSTEM.md §6's binding rule that a status badge always renders
 * from `canonical_ref`, never a tenant label alone: this component does not fetch or
 * resolve `canonical_ref` itself (that binding is a `components/domain/` composition
 * concern, not yet built) -- it only guarantees the rendered badge can never silently
 * become a color-only or brand-colored signal once a caller wires it to canonical data.
 */

import type { ReactNode } from "react";

const TONE_CLASSES = {
  success: "bg-success/10 text-success",
  warning: "bg-warning/10 text-warning",
  danger: "bg-danger/10 text-danger",
  info: "bg-info/10 text-info",
  neutral: "bg-neutral-100 text-neutral-700",
} as const;

export type StatusTone = keyof typeof TONE_CLASSES;

export interface StatusBadgeProps {
  readonly tone: StatusTone;
  /** Required, never optional -- the label is the non-color-alone signal (docs/standards/DESIGN_SYSTEM.md §2.1's "non-color status rule"). */
  readonly label: string;
  /** Optional, in addition to (never instead of) `label`. */
  readonly icon?: ReactNode;
}

export function StatusBadge({ tone, label, icon }: StatusBadgeProps) {
  return (
    <span className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium ${TONE_CLASSES[tone]}`}>
      {icon}
      {label}
    </span>
  );
}
