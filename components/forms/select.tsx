/**
 * Select primitive (`docs/design-system/02_COMPONENTS.md` "Select"). Native `<select>`,
 * server-safe -- matches every existing form's own raw `<select className="...">`
 * pattern exactly (border-neutral-300, rounded-md, px-3 py-2). `Combobox`
 * (searchable, RLS-aware reference picker) is a distinct, richer primitive for large
 * option sets -- this component is for a small, known, static option list only.
 */

import { forwardRef, type SelectHTMLAttributes } from "react";

export interface SelectProps extends SelectHTMLAttributes<HTMLSelectElement> {
  readonly invalid?: boolean;
}

export const Select = forwardRef<HTMLSelectElement, SelectProps>(function Select(
  { invalid = false, className, children, ...rest },
  ref,
) {
  const classes = [
    "w-full rounded-md border bg-surface px-3 py-2 text-sm text-text-primary",
    "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-primary",
    invalid ? "border-danger" : "border-neutral-300",
    "disabled:cursor-not-allowed disabled:bg-neutral-100 disabled:text-neutral-400",
    className,
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <select ref={ref} aria-invalid={invalid || undefined} className={classes} {...rest}>
      {children}
    </select>
  );
});
