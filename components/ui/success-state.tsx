/**
 * Success state primitive (`docs/design-system/02_COMPONENTS.md` §2, listed under this
 * checkpoint's own instruction as "Success State" -- not previously a distinct named
 * component in this repository's catalogue; `StatusBadge`'s `success` tone and
 * `Banner`'s `success` variant cover the inline case, this is the whole-page/whole-
 * section confirmation shape neither of those owns).
 */

import type { ReactNode } from "react";

export interface SuccessStateProps {
  readonly title: string;
  readonly description?: string;
  readonly primaryAction?: ReactNode;
}

export function SuccessState({ title, description, primaryAction }: SuccessStateProps) {
  return (
    <div role="status" className="flex flex-col items-center gap-2 rounded-md border border-success/30 bg-success/10 p-8 text-center">
      <p className="text-sm font-semibold text-success">{title}</p>
      {description ? <p className="max-w-sm text-sm text-text-secondary">{description}</p> : null}
      {primaryAction ? <div className="mt-2">{primaryAction}</div> : null}
    </div>
  );
}
