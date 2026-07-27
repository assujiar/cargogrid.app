/**
 * Validation message primitives (`docs/design-system/02_COMPONENTS.md` "Validation
 * summary"). `ValidationMessage` is the single field-level error `FormField` renders
 * automatically; `ValidationSummary` is the form-level list with a focus target for
 * "jump to first error" (`ref`-forwarded so a submit handler can call `.focus()` on it).
 */

import { forwardRef } from "react";

export function ValidationMessage({ id, children }: { readonly id?: string; readonly children: string }) {
  return (
    <p id={id} role="alert" className="text-xs text-danger">
      {children}
    </p>
  );
}

export interface ValidationSummaryItem {
  readonly fieldId: string;
  readonly message: string;
}

export const ValidationSummary = forwardRef<HTMLDivElement, { readonly items: readonly ValidationSummaryItem[] }>(
  function ValidationSummary({ items }, ref) {
    if (items.length === 0) {
      return null;
    }

    return (
      <div ref={ref} tabIndex={-1} role="alert" className="rounded-md border border-danger/30 bg-danger/10 p-3">
        <p className="text-sm font-medium text-danger">
          {items.length} field{items.length === 1 ? "" : "s"} need attention:
        </p>
        <ul className="mt-1 list-disc pl-5 text-sm text-danger">
          {items.map((item) => (
            <li key={item.fieldId}>
              <a href={`#${item.fieldId}`} className="underline">
                {item.message}
              </a>
            </li>
          ))}
        </ul>
      </div>
    );
  },
);
