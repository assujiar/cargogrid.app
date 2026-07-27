/**
 * Empty state primitive (`docs/design-system/02_COMPONENTS.md` "Empty state") --
 * no-data explanation + gated next action. `primaryAction`/`secondaryAction` are
 * caller-rendered nodes (typically a `Button`/`asChild` link) so this component never
 * decides permission gating itself -- the caller passes `undefined` when the viewer
 * cannot perform the action, per `09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §5's "an empty
 * state never reveals a create action the viewer cannot use."
 */

import type { ReactNode } from "react";

export interface EmptyStateProps {
  readonly icon?: ReactNode;
  readonly title: string;
  readonly description?: string;
  readonly primaryAction?: ReactNode;
  readonly secondaryAction?: ReactNode;
}

export function EmptyState({ icon, title, description, primaryAction, secondaryAction }: EmptyStateProps) {
  return (
    <div className="flex flex-col items-center gap-2 rounded-md border border-dashed border-neutral-300 p-8 text-center">
      {icon ? (
        <div aria-hidden="true" className="text-3xl">
          {icon}
        </div>
      ) : null}
      <p className="text-sm font-medium text-text-primary">{title}</p>
      {description ? <p className="max-w-sm text-sm text-text-secondary">{description}</p> : null}
      {primaryAction || secondaryAction ? (
        <div className="mt-2 flex gap-2">
          {primaryAction}
          {secondaryAction}
        </div>
      ) : null}
    </div>
  );
}
