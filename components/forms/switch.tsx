/**
 * Switch primitive (`docs/design-system/02_COMPONENTS.md` "Switch") -- an
 * immediate-effect boolean toggle, distinct from Checkbox's form-submit-pending
 * boolean. Built as a native `<input type="checkbox" role="switch">` with the track/thumb
 * drawn in pure CSS via the `peer` pattern -- zero client JS, works in a server-rendered
 * form. `label` is required (never optional), same non-color-alone discipline as
 * Checkbox.
 */

import { forwardRef, type InputHTMLAttributes, type ReactNode } from "react";

export interface SwitchProps extends Omit<InputHTMLAttributes<HTMLInputElement>, "type" | "role"> {
  readonly label: ReactNode;
}

export const Switch = forwardRef<HTMLInputElement, SwitchProps>(function Switch({ label, id, className, ...rest }, ref) {
  return (
    <label htmlFor={id} className="flex items-center gap-2 text-sm text-text-primary">
      <span className="relative inline-flex h-5 w-9 flex-shrink-0 items-center">
        <input
          ref={ref}
          id={id}
          type="checkbox"
          role="switch"
          className={`peer absolute inset-0 h-full w-full cursor-pointer appearance-none rounded-full bg-neutral-300 transition-colors checked:bg-primary focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-primary disabled:cursor-not-allowed disabled:opacity-60 ${className ?? ""}`}
          {...rest}
        />
        <span className="pointer-events-none absolute left-0.5 h-4 w-4 rounded-full bg-white shadow-sm transition-transform peer-checked:translate-x-4" />
      </span>
      {label}
    </label>
  );
});
