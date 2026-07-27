"use client";

/**
 * Alert primitive (`docs/design-system/02_COMPONENTS.md` "Alert / Callout") -- inline,
 * non-persistent emphasis block, distinct from `Banner`'s page-level persistence: this
 * one is dismissible (local state) and typically appears near the content it comments
 * on, not pinned to the top of a page/portal shell.
 */

import { useState, type ReactNode } from "react";

const TONE_CLASSES = {
  info: "border-info/30 bg-info/10 text-info",
  warning: "border-warning/30 bg-warning/10 text-warning",
  success: "border-success/30 bg-success/10 text-success",
  danger: "border-danger/30 bg-danger/10 text-danger",
} as const;

export type AlertTone = keyof typeof TONE_CLASSES;

export interface AlertProps {
  readonly tone?: AlertTone;
  readonly dismissible?: boolean;
  readonly children: ReactNode;
}

export function Alert({ tone = "info", dismissible = false, children }: AlertProps) {
  const [dismissed, setDismissed] = useState(false);

  if (dismissed) {
    return null;
  }

  return (
    <div role="note" className={`flex items-start justify-between gap-3 rounded-md border p-3 text-sm ${TONE_CLASSES[tone]}`}>
      <div className="text-text-primary">{children}</div>
      {dismissible ? (
        <button type="button" onClick={() => setDismissed(true)} aria-label="Dismiss" className="text-xs font-medium">
          ×
        </button>
      ) : null}
    </div>
  );
}
