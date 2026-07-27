"use client";

/**
 * Password input primitive (`docs/design-system/02_COMPONENTS.md` "Password input").
 * Masked entry with a reveal toggle -- built as a plain local-state toggle rather than
 * Radix's own `unstable_PasswordToggleField` (already a transitive dependency via
 * `radix-ui`, but explicitly marked unstable upstream -- not built against for a
 * primitive this checkpoint calls production-ready).
 */

import { forwardRef, useState } from "react";
import { Input, type InputProps } from "./input.tsx";

export type PasswordInputProps = Omit<InputProps, "type">;

export const PasswordInput = forwardRef<HTMLInputElement, PasswordInputProps>(function PasswordInput(
  { className, ...rest },
  ref,
) {
  const [visible, setVisible] = useState(false);

  return (
    <div className="relative">
      <Input ref={ref} type={visible ? "text" : "password"} className={`pr-16 ${className ?? ""}`} {...rest} />
      <button
        type="button"
        onClick={() => setVisible((current) => !current)}
        aria-pressed={visible}
        className="absolute inset-y-0 right-2 text-xs font-medium text-primary"
      >
        {visible ? "Hide" : "Show"}
      </button>
    </div>
  );
});
