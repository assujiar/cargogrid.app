/** Textarea primitive (`docs/design-system/02_COMPONENTS.md` "Textarea"). Same states/styling contract as Input, native `<textarea>`, server-safe. */

import { forwardRef, type TextareaHTMLAttributes } from "react";

export interface TextareaProps extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  readonly invalid?: boolean;
}

export const Textarea = forwardRef<HTMLTextAreaElement, TextareaProps>(function Textarea(
  { invalid = false, className, rows = 4, ...rest },
  ref,
) {
  const classes = [
    "w-full rounded-md border px-3 py-2 text-sm text-text-primary placeholder:text-neutral-400",
    "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-primary",
    invalid ? "border-danger" : "border-neutral-300",
    "disabled:cursor-not-allowed disabled:bg-neutral-100 disabled:text-neutral-400",
    "read-only:bg-neutral-50",
    className,
  ]
    .filter(Boolean)
    .join(" ");

  return <textarea ref={ref} rows={rows} aria-invalid={invalid || undefined} className={classes} {...rest} />;
});
