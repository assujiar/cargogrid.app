/**
 * Form field primitive (`docs/design-system/02_COMPONENTS.md` "Form field") -- label +
 * control + help text + error message as one accessible unit. Wraps a single control
 * (`Input`/`Select`/`Textarea`/etc., passed as `children`, expected to accept `id` and
 * `aria-describedby`); this component does not clone/inject props into `children`
 * (avoids the fragile `cloneElement` pattern) -- the caller wires `id`/`aria-describedby`
 * explicitly, matching the ids this component renders for help/error text.
 */

import type { ReactNode } from "react";
import { ValidationMessage } from "./validation-message.tsx";

export interface FormFieldProps {
  readonly id: string;
  readonly label: ReactNode;
  readonly required?: boolean;
  readonly helpText?: ReactNode;
  readonly error?: string;
  readonly children: ReactNode;
}

/** Builds the `aria-describedby` value a field's control should pass -- help text id, error id, or both. */
export function formFieldDescribedBy(id: string, { hasHelpText, hasError }: { hasHelpText: boolean; hasError: boolean }): string | undefined {
  const ids = [hasHelpText ? `${id}-help` : null, hasError ? `${id}-error` : null].filter((value): value is string => value !== null);
  return ids.length > 0 ? ids.join(" ") : undefined;
}

export function FormField({ id, label, required = false, helpText, error, children }: FormFieldProps) {
  return (
    <div className="flex flex-col gap-1">
      <label htmlFor={id} className="text-sm font-medium text-text-primary">
        {label}
        {required ? (
          <span aria-hidden="true" className="ml-0.5 text-danger">
            *
          </span>
        ) : null}
      </label>
      {children}
      {helpText ? (
        <p id={`${id}-help`} className="text-xs text-text-secondary">
          {helpText}
        </p>
      ) : null}
      {error ? <ValidationMessage id={`${id}-error`}>{error}</ValidationMessage> : null}
    </div>
  );
}
