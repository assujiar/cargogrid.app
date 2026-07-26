/**
 * Button primitive (PLT-135, CG-S6-PLT-032). Radix UI copy-in pattern (`ADR-0005`,
 * `docs/standards/DESIGN_SYSTEM.md` §1) -- owned and versioned in this repository, not
 * consumed as a black-box runtime dependency. The first `components/ui/` primitive this
 * repository builds (`docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §4.1's own
 * "one component owner, many consumers" rule) -- every future consumer imports this
 * file, never re-implements its own button.
 *
 * States (`docs/standards/DESIGN_SYSTEM.md` §4's 11-state contract, the subset
 * applicable to a button itself): disabled and loading are real, distinct visual/aria
 * states, not merely a CSS class name.
 */

import { forwardRef, type ButtonHTMLAttributes } from "react";
import { Slot } from "radix-ui";

const VARIANT_CLASSES = {
  primary: "bg-primary text-neutral-50 hover:bg-primary-hover focus-visible:outline-primary",
  secondary: "bg-neutral-100 text-neutral-900 hover:bg-neutral-200 focus-visible:outline-neutral-400",
  destructive: "bg-danger text-neutral-50 hover:opacity-90 focus-visible:outline-danger",
} as const;

export type ButtonVariant = keyof typeof VARIANT_CLASSES;

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  readonly variant?: ButtonVariant;
  /** Renders this component's props onto its single child instead of a `<button>` (Radix `Slot` composition) -- e.g. wrapping a `next/link` `<a>` that should look like a button. */
  readonly asChild?: boolean;
  /** A real, distinct state (`docs/standards/DESIGN_SYSTEM.md` §4) -- disables the control and swaps its accessible name, never just a spinner icon with no semantic change. */
  readonly loading?: boolean;
  readonly loadingLabel?: string;
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { variant = "primary", asChild = false, loading = false, loadingLabel = "Loading", disabled, className, children, ...rest },
  ref,
) {
  const Component = asChild ? Slot.Root : "button";
  const classes = [
    "inline-flex items-center justify-center rounded-md px-4 py-2 text-sm font-medium transition-opacity",
    "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2",
    "disabled:cursor-not-allowed disabled:opacity-60",
    VARIANT_CLASSES[variant],
    className,
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <Component ref={ref} className={classes} disabled={disabled || loading} aria-busy={loading || undefined} {...rest}>
      {loading ? loadingLabel : children}
    </Component>
  );
});
