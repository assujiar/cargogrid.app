/**
 * Input primitive (`docs/design-system/02_COMPONENTS.md` "Input", flips
 * `DOCUMENTED_ONLY` -> `IMPLEMENTED`). Native `<input>`, server-safe (no client JS
 * required) -- matches every existing form's own raw `<input className="...">` pattern
 * exactly (border-neutral-300, rounded-md, px-3 py-2), so migrating a real form onto
 * this component changes zero visual behavior.
 *
 * States: default, focus (native `:focus-visible`), disabled, read-only, invalid
 * (`aria-invalid` + red border, never color alone -- pair with `ValidationMessage`).
 */

import { forwardRef, type InputHTMLAttributes } from "react";

export interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  /** Pairs with a visible `ValidationMessage` -- never rely on the red border alone. */
  readonly invalid?: boolean;
}

export const Input = forwardRef<HTMLInputElement, InputProps>(function Input(
  { invalid = false, className, ...rest },
  ref,
) {
  const classes = [
    // HDN-381 (Browser and Device Compatibility) Tier C: min-h-11 (44px) touch-target
    // floor added -- live-measured at ~36px before this fix (same `py-2`+`text-sm`
    // shape already fixed on `Button`), and this primitive has 49 real importers
    // (`date-input.tsx`/`number-input.tsx`/`password-input.tsx`/`search-input.tsx` all
    // compose it, so the floor cascades to all four automatically).
    "w-full min-h-11 rounded-md border px-3 py-2 text-sm text-text-primary placeholder:text-neutral-400",
    "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-primary",
    invalid ? "border-danger" : "border-neutral-300",
    "disabled:cursor-not-allowed disabled:bg-neutral-100 disabled:text-neutral-400",
    "read-only:bg-neutral-50",
    className,
  ]
    .filter(Boolean)
    .join(" ");

  return <input ref={ref} aria-invalid={invalid || undefined} className={classes} {...rest} />;
});
