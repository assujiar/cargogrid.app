/**
 * Radio primitive (`docs/design-system/02_COMPONENTS.md` "Radio"). Native
 * `<input type="radio">`, server-safe. `RadioGroup` renders a labeled `fieldset` of
 * options sharing one `name` -- the always-visible set the spec calls for (vs. Select's
 * hidden-until-opened list).
 */

import type { InputHTMLAttributes, ReactNode } from "react";

export interface RadioProps extends Omit<InputHTMLAttributes<HTMLInputElement>, "type"> {
  readonly label: ReactNode;
}

export function Radio({ label, id, className, ...rest }: RadioProps) {
  return (
    <label htmlFor={id} className="flex items-center gap-2 text-sm text-text-primary">
      <input
        id={id}
        type="radio"
        className={`h-4 w-4 border-neutral-300 accent-primary focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-primary disabled:cursor-not-allowed ${className ?? ""}`}
        {...rest}
      />
      {label}
    </label>
  );
}

export interface RadioGroupOption {
  readonly value: string;
  readonly label: ReactNode;
  readonly disabled?: boolean;
}

export interface RadioGroupProps {
  readonly legend: ReactNode;
  readonly name: string;
  readonly options: readonly RadioGroupOption[];
  readonly defaultValue?: string;
  readonly value?: string;
  readonly onChange?: (value: string) => void;
  readonly disabled?: boolean;
}

export function RadioGroup({ legend, name, options, defaultValue, value, onChange, disabled }: RadioGroupProps) {
  return (
    <fieldset className="flex flex-col gap-2">
      <legend className="text-sm font-medium text-text-primary">{legend}</legend>
      {options.map((option) => (
        <Radio
          key={option.value}
          name={name}
          value={option.value}
          label={option.label}
          disabled={disabled || option.disabled}
          defaultChecked={value === undefined ? option.value === defaultValue : undefined}
          checked={value !== undefined ? option.value === value : undefined}
          onChange={onChange ? () => onChange(option.value) : undefined}
        />
      ))}
    </fieldset>
  );
}
