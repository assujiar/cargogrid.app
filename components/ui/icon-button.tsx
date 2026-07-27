/**
 * Icon button primitive (`docs/design-system/02_COMPONENTS.md` "Icon button") --
 * icon-only action (row action, toolbar). Same variants/states as `Button`; `label`
 * (mandatory, not optional) becomes `aria-label` since there is no visible text to
 * derive an accessible name from.
 */

import { forwardRef, type ButtonHTMLAttributes, type ReactNode } from "react";
import { VARIANT_CLASSES, type ButtonVariant } from "./button.tsx";

export interface IconButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  readonly variant?: ButtonVariant;
  readonly label: string;
  readonly icon: ReactNode;
}

export const IconButton = forwardRef<HTMLButtonElement, IconButtonProps>(function IconButton(
  { variant = "secondary", label, icon, className, disabled, ...rest },
  ref,
) {
  const classes = [
    "inline-flex h-9 w-9 items-center justify-center rounded-md transition-opacity",
    "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2",
    "disabled:cursor-not-allowed disabled:opacity-60",
    VARIANT_CLASSES[variant],
    className,
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <button ref={ref} type="button" aria-label={label} disabled={disabled} className={classes} {...rest}>
      {icon}
    </button>
  );
});
