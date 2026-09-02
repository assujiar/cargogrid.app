"use client";

/**
 * Combobox primitive (`docs/design-system/02_COMPONENTS.md` "Combobox") -- searchable
 * single-choice picker. Implements the WAI-ARIA combobox pattern by hand (no Radix
 * Combobox exists) -- `role="combobox"`, `aria-expanded`, `aria-controls`,
 * `aria-activedescendant`, Up/Down/Enter/Escape keyboard support. Client-side text
 * filtering here is a UI convenience over an already-fetched, RLS-scoped `options`
 * list -- for a large/unbounded reference set, the caller is responsible for
 * server-side search (`09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §11), this component never
 * fetches on its own.
 *
 * `ISS-2026-246` (first real consumer, the HRIS employee picker): two additions, both
 * made so that migrating a picker OFF `Select` drops nothing it had.
 *   - `required` and `aria-describedby`, plain passthroughs to the visible input. Every
 *     `Select` this replaces carries them (`aria-describedby` is `ISS-2026-242`'s own
 *     "every control points at its error message" wiring), and this primitive could not
 *     express either. NOTE the honest limit of `required` here: it guards the empty
 *     field, which is exactly what the `Select`'s `required` guarded; text typed without
 *     picking an option still leaves the committed value null and is caught server-side.
 *   - `min-h-11`, HDN-381's 44px touch-target floor, which `Select` already carries and
 *     this primitive was skipped for because it had no consumer to measure.
 */

import { useId, useMemo, useRef, useState, type KeyboardEvent } from "react";

export interface ComboboxOption {
  readonly value: string;
  readonly label: string;
}

export interface ComboboxProps {
  readonly id?: string;
  readonly name?: string;
  readonly label: string;
  readonly options: readonly ComboboxOption[];
  readonly value: string | null;
  readonly onChange: (value: string | null) => void;
  readonly placeholder?: string;
  readonly disabled?: boolean;
  readonly invalid?: boolean;
  readonly required?: boolean;
  readonly "aria-describedby"?: string;
}

export function Combobox({ id, name, label, options, value, onChange, placeholder, disabled, invalid, required, ...rest }: ComboboxProps) {
  const generatedId = useId();
  const baseId = id ?? generatedId;
  const listboxId = `${baseId}-listbox`;
  const selected = options.find((option) => option.value === value) ?? null;

  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState(selected?.label ?? "");
  const [activeIndex, setActiveIndex] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);

  const filtered = useMemo(
    () => options.filter((option) => option.label.toLowerCase().includes(query.toLowerCase())),
    [options, query],
  );

  function commit(option: ComboboxOption | null) {
    onChange(option?.value ?? null);
    setQuery(option?.label ?? "");
    setOpen(false);
  }

  function handleKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      setOpen(true);
      setActiveIndex((index) => Math.min(index + 1, filtered.length - 1));
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      setActiveIndex((index) => Math.max(index - 1, 0));
    } else if (event.key === "Enter") {
      event.preventDefault();
      const option = filtered[activeIndex];
      if (option) {
        commit(option);
      }
    } else if (event.key === "Escape") {
      setOpen(false);
    }
  }

  return (
    <div className="relative">
      <input
        ref={inputRef}
        id={baseId}
        role="combobox"
        aria-expanded={open}
        aria-controls={listboxId}
        aria-activedescendant={open && filtered[activeIndex] ? `${listboxId}-${filtered[activeIndex].value}` : undefined}
        aria-label={label}
        aria-invalid={invalid || undefined}
        autoComplete="off"
        required={required}
        disabled={disabled}
        placeholder={placeholder}
        value={query}
        onFocus={() => setOpen(true)}
        onChange={(event) => {
          setQuery(event.target.value);
          setOpen(true);
          setActiveIndex(0);
          if (event.target.value === "") {
            onChange(null);
          }
        }}
        onKeyDown={handleKeyDown}
        onBlur={() => setOpen(false)}
        className={`w-full min-h-11 rounded-md border px-3 py-2 text-sm text-text-primary ${invalid ? "border-danger" : "border-neutral-300"} disabled:cursor-not-allowed disabled:bg-neutral-100`}
        {...rest}
      />
      {name ? <input type="hidden" name={name} value={value ?? ""} /> : null}
      {open && filtered.length > 0 ? (
        <ul
          id={listboxId}
          role="listbox"
          aria-label={label}
          className="absolute z-10 mt-1 max-h-56 w-full overflow-auto rounded-md border border-neutral-200 bg-surface py-1 shadow-md"
        >
          {filtered.map((option, index) => (
            <li
              key={option.value}
              id={`${listboxId}-${option.value}`}
              role="option"
              aria-selected={option.value === value}
              // onMouseDown (not onClick) fires before the input's onBlur closes the list.
              onMouseDown={(event) => {
                event.preventDefault();
                commit(option);
              }}
              className={`cursor-pointer px-3 py-1.5 text-sm ${index === activeIndex ? "bg-primary/10 text-primary" : "text-text-primary"}`}
            >
              {option.label}
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}
