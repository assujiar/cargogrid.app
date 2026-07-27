/**
 * Checkbox primitive (`docs/design-system/02_COMPONENTS.md` "Checkbox"). Native
 * `<input type="checkbox">`, styled via the browser's own `accent-color` (no custom SVG
 * check icon needed) -- server-safe, works inside a plain server-action form with no
 * client JS. `label` is required, never optional: an unlabeled checkbox has no
 * accessible name.
 */

import { forwardRef, type InputHTMLAttributes, type ReactNode } from "react";

export interface CheckboxProps extends Omit<InputHTMLAttributes<HTMLInputElement>, "type"> {
  readonly label: ReactNode;
}

export const Checkbox = forwardRef<HTMLInputElement, CheckboxProps>(function Checkbox(
  { label, id, className, ...rest },
  ref,
) {
  return (
    <label htmlFor={id} className="flex items-center gap-2 text-sm text-text-primary">
      <input
        ref={ref}
        id={id}
        type="checkbox"
        className={`h-4 w-4 rounded border-neutral-300 accent-primary focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-primary disabled:cursor-not-allowed ${className ?? ""}`}
        {...rest}
      />
      {label}
    </label>
  );
});
