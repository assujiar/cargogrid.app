"use client";

/**
 * Multi-select primitive (`docs/design-system/02_COMPONENTS.md` "Multi-select") --
 * multiple-choice with chip display. Built on the same filtered-list pattern as
 * `Combobox`, minus single-value commit-and-close (selecting an option here removes it
 * from the remaining list and adds a chip instead).
 *
 * `ISS-2026-246` (first real consumer, the n8n connector scope picker): three additions,
 * all made so that migrating a multi-value field OFF a comma-separated `Input` drops
 * nothing it had.
 *   - `invalid` and `aria-describedby`, matching `Input`/`Select`/`Combobox` -- the
 *     `ISS-2026-242` wiring that points every control at its own error message, which
 *     this primitive could not express. `required` is surfaced as `aria-required` on the
 *     search box rather than as the native attribute: the search box is not the value
 *     holder (the hidden inputs are), so a native `required` there would fire on typed
 *     text rather than on a chosen value.
 *   - `min-h-11`, HDN-381's 44px touch-target floor, which `Input` already carries.
 */

import { useId, useMemo, useState } from "react";
import { Badge } from "../ui/badge.tsx";

export interface MultiSelectOption {
  readonly value: string;
  readonly label: string;
}

export interface MultiSelectProps {
  readonly id?: string;
  readonly name?: string;
  readonly label: string;
  readonly options: readonly MultiSelectOption[];
  readonly values: readonly string[];
  readonly onChange: (values: readonly string[]) => void;
  readonly disabled?: boolean;
  readonly invalid?: boolean;
  readonly required?: boolean;
  readonly "aria-describedby"?: string;
}

export function MultiSelect({ id, name, label, options, values, onChange, disabled, invalid, required, ...rest }: MultiSelectProps) {
  const generatedId = useId();
  const baseId = id ?? generatedId;
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState(false);

  const selectedOptions = options.filter((option) => values.includes(option.value));
  const available = useMemo(
    () => options.filter((option) => !values.includes(option.value) && option.label.toLowerCase().includes(query.toLowerCase())),
    [options, values, query],
  );

  function add(value: string) {
    onChange([...values, value]);
    setQuery("");
  }

  function remove(value: string) {
    onChange(values.filter((v) => v !== value));
  }

  return (
    <div className="relative">
      {selectedOptions.length > 0 ? (
        <div className="mb-1 flex flex-wrap gap-1">
          {selectedOptions.map((option) => (
            <span key={option.value} className="inline-flex items-center gap-1">
              <Badge tone="neutral">{option.label}</Badge>
              <button
                type="button"
                onClick={() => remove(option.value)}
                aria-label={`Remove ${option.label}`}
                disabled={disabled}
                className="text-xs text-text-secondary"
              >
                ×
              </button>
            </span>
          ))}
        </div>
      ) : null}
      <input
        id={baseId}
        aria-label={label}
        disabled={disabled}
        value={query}
        placeholder="Search…"
        onFocus={() => setOpen(true)}
        onChange={(event) => {
          setQuery(event.target.value);
          setOpen(true);
        }}
        onBlur={() => setOpen(false)}
        aria-invalid={invalid || undefined}
        aria-required={required || undefined}
        className={`w-full min-h-11 rounded-md border px-3 py-2 text-sm text-text-primary ${invalid ? "border-danger" : "border-neutral-300"} disabled:cursor-not-allowed disabled:bg-neutral-100`}
        {...rest}
      />
      {name ? values.map((value) => <input key={value} type="hidden" name={name} value={value} />) : null}
      {open && available.length > 0 ? (
        <ul role="listbox" aria-label={label} className="absolute z-10 mt-1 max-h-56 w-full overflow-auto rounded-md border border-neutral-200 bg-surface py-1 shadow-md">
          {available.map((option) => (
            <li
              key={option.value}
              role="option"
              aria-selected={false}
              onMouseDown={(event) => {
                event.preventDefault();
                add(option.value);
              }}
              className="cursor-pointer px-3 py-1.5 text-sm text-text-primary hover:bg-neutral-100"
            >
              {option.label}
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}
