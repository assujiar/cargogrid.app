/**
 * Date input primitive (`docs/design-system/02_COMPONENTS.md` "Date picker",
 * implemented as a native calendar-backed `<input type="date">` -- not a custom popover
 * calendar grid). Server-safe, zero JS, uses the platform's native date picker UI
 * (correct locale/keyboard/screen-reader behavior for free). A richer custom calendar
 * popover remains `DOCUMENTED_ONLY` if a future screen needs range selection beyond
 * what `DateRangeInput` (two paired `DateInput`s) covers.
 */

import { forwardRef } from "react";
import { Input, type InputProps } from "./input.tsx";

export type DateInputProps = Omit<InputProps, "type">;

export const DateInput = forwardRef<HTMLInputElement, DateInputProps>(function DateInput(props, ref) {
  return <Input ref={ref} type="date" {...props} />;
});

/** Date-range picker (`docs/design-system/02_COMPONENTS.md` "Date-range picker") -- paired start/end DateInputs, the simplest correct implementation without a custom calendar dependency. */
export interface DateRangeInputProps {
  readonly startId?: string;
  readonly startName?: string;
  readonly startValue?: string;
  readonly endId?: string;
  readonly endName?: string;
  readonly endValue?: string;
  readonly onStartChange?: (value: string) => void;
  readonly onEndChange?: (value: string) => void;
  readonly disabled?: boolean;
}

export function DateRangeInput({
  startId,
  startName,
  startValue,
  endId,
  endName,
  endValue,
  onStartChange,
  onEndChange,
  disabled,
}: DateRangeInputProps) {
  return (
    <div className="flex items-center gap-2">
      <DateInput
        id={startId}
        name={startName}
        value={startValue}
        max={endValue}
        disabled={disabled}
        onChange={(event) => onStartChange?.(event.target.value)}
        aria-label="Start date"
      />
      <span className="text-sm text-text-secondary">to</span>
      <DateInput
        id={endId}
        name={endName}
        value={endValue}
        min={startValue}
        disabled={disabled}
        onChange={(event) => onEndChange?.(event.target.value)}
        aria-label="End date"
      />
    </div>
  );
}
