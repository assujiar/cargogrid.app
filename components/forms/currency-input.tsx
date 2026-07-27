"use client";

/**
 * Currency input primitive (`docs/design-system/02_COMPONENTS.md` "Currency input").
 * Bound to a `numeric`-shaped **string** value, never a JS `number` -- this repository's
 * own money rule (`AGENTS.md` "Data and finance rules": money stays `numeric` end to
 * end, never binary float). A controlled component: the caller owns the string state
 * (e.g. from a form field), this component only sanitizes keystrokes to a valid
 * up-to-2-decimal numeric string and renders the paired currency code.
 */

import { forwardRef, type ChangeEvent } from "react";

const VALID_PARTIAL_AMOUNT = /^\d*\.?\d{0,2}$/;

export interface CurrencyInputProps {
  readonly id?: string;
  readonly name?: string;
  readonly value: string;
  readonly onValueChange: (value: string) => void;
  readonly currencyCode: string;
  readonly invalid?: boolean;
  readonly disabled?: boolean;
  readonly required?: boolean;
  readonly "aria-describedby"?: string;
}

export const CurrencyInput = forwardRef<HTMLInputElement, CurrencyInputProps>(function CurrencyInput(
  { id, name, value, onValueChange, currencyCode, invalid = false, disabled = false, required = false, ...rest },
  ref,
) {
  function handleChange(event: ChangeEvent<HTMLInputElement>) {
    const raw = event.target.value;
    if (raw === "" || VALID_PARTIAL_AMOUNT.test(raw)) {
      onValueChange(raw);
    }
  }

  return (
    <div
      className={`flex items-stretch overflow-hidden rounded-md border ${invalid ? "border-danger" : "border-neutral-300"} ${
        disabled ? "bg-neutral-100" : "bg-surface"
      }`}
    >
      <span className="flex items-center bg-neutral-50 px-2 text-xs font-medium text-text-secondary">{currencyCode}</span>
      <input
        ref={ref}
        id={id}
        name={name}
        type="text"
        inputMode="decimal"
        value={value}
        onChange={handleChange}
        disabled={disabled}
        required={required}
        aria-invalid={invalid || undefined}
        className="w-full border-0 bg-transparent px-2 py-2 text-sm text-text-primary focus-visible:outline-none disabled:cursor-not-allowed disabled:text-neutral-400"
        {...rest}
      />
    </div>
  );
});
