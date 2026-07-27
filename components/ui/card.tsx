/**
 * Card primitive (`docs/design-system/02_COMPONENTS.md` "Card") -- bounded content
 * block. Used sparingly by design (`ADR-0017` §1: "avoid turning every section into a
 * card") -- `elevated` defaults to false (flat, bordered) since the 85/10/5 flat/
 * elevated/tactile balance reserves `--shadow-*` for drawers/dialogs/dropdowns, not
 * ordinary content cards.
 */

import type { ReactNode } from "react";

export interface CardProps {
  readonly title?: ReactNode;
  readonly children: ReactNode;
  readonly elevated?: boolean;
  readonly className?: string;
}

export function Card({ title, children, elevated = false, className }: CardProps) {
  return (
    <div className={`rounded-md border border-neutral-200 bg-surface p-4 ${elevated ? "shadow-sm" : ""} ${className ?? ""}`}>
      {title ? <h3 className="mb-2 text-sm font-semibold text-text-primary">{title}</h3> : null}
      {children}
    </div>
  );
}
