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
 *
 * CG-AUDIT-2026-09-02 F2: each `<li role="option">` used to have `onMouseDown` as its
 * only handler -- no key handler, no way to reach an option at all from the keyboard
 * (WCAG 2.1.1 Level A). Fixed by adopting `Combobox`'s own already-correct WAI-ARIA
 * combobox pattern verbatim rather than inventing a second one: real keyboard focus
 * stays on the text input the whole time; `role="combobox"`/`aria-expanded`/
 * `aria-controls`/`aria-activedescendant` on the input plus Up/Down/Enter/Escape tell an
 * assistive-technology user which option is virtually focused and let them act on it
 * without ever moving focus onto an `<li>` (the reason neither this fix nor `Combobox`
 * puts `tabIndex` on the options themselves -- that would be a second, competing
 * keyboard model, not a stricter one). Enter here adds the active option and clears the
 * query rather than committing-and-closing, mirroring this component's own multi-value
 * `add()` precisely as `onMouseDown` already did.
 */

import { useId, useMemo, useState, type KeyboardEvent } from "react";
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
  const listboxId = `${baseId}-listbox`;
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState(0);

  const selectedOptions = options.filter((option) => values.includes(option.value));
  const available = useMemo(
    () => options.filter((option) => !values.includes(option.value) && option.label.toLowerCase().includes(query.toLowerCase())),
    [options, values, query],
  );

  function add(value: string) {
    onChange([...values, value]);
    setQuery("");
    setActiveIndex(0);
  }

  function remove(value: string) {
    onChange(values.filter((v) => v !== value));
  }

  function handleKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      setOpen(true);
      setActiveIndex((index) => Math.min(index + 1, available.length - 1));
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      setActiveIndex((index) => Math.max(index - 1, 0));
    } else if (event.key === "Enter") {
      event.preventDefault();
      const option = available[activeIndex];
      if (option) {
        add(option.value);
      }
    } else if (event.key === "Escape") {
      setOpen(false);
    }
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
        role="combobox"
        aria-expanded={open}
        aria-controls={listboxId}
        aria-activedescendant={open && available[activeIndex] ? `${listboxId}-${available[activeIndex].value}` : undefined}
        aria-label={label}
        autoComplete="off"
        disabled={disabled}
        value={query}
        placeholder="Search…"
        onFocus={() => setOpen(true)}
        onChange={(event) => {
          setQuery(event.target.value);
          setOpen(true);
          setActiveIndex(0);
        }}
        onKeyDown={handleKeyDown}
        onBlur={() => setOpen(false)}
        aria-invalid={invalid || undefined}
        aria-required={required || undefined}
        className={`w-full min-h-11 rounded-md border px-3 py-2 text-sm text-text-primary ${invalid ? "border-danger" : "border-neutral-300"} disabled:cursor-not-allowed disabled:bg-neutral-100`}
        {...rest}
      />
      {name ? values.map((value) => <input key={value} type="hidden" name={name} value={value} />) : null}
      {open && available.length > 0 ? (
        <ul id={listboxId} role="listbox" aria-label={label} className="absolute z-10 mt-1 max-h-56 w-full overflow-auto rounded-md border border-neutral-200 bg-surface py-1 shadow-md">
          {available.map((option, index) => (
            <li
              key={option.value}
              id={`${listboxId}-${option.value}`}
              role="option"
              aria-selected={false}
              // onMouseDown (not onClick) fires before the input's onBlur closes the list -- matching Combobox's own established reason for this exact choice.
              onMouseDown={(event) => {
                event.preventDefault();
                add(option.value);
              }}
              className={`cursor-pointer px-3 py-1.5 text-sm ${index === activeIndex ? "bg-primary/10 text-primary" : "text-text-primary hover:bg-neutral-100"}`}
            >
              {option.label}
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}
