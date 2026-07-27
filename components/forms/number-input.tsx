/**
 * Number input primitive (`docs/design-system/02_COMPONENTS.md` "Number input"). A thin
 * `type="number"` specialization of Input -- locale-aware formatting is deliberately
 * NOT built here: this repository's own money rule (`AGENTS.md` "Data and finance
 * rules" -- numeric, never float) means any money field must use `CurrencyInput`
 * instead, never this component with a currency value.
 */

import { forwardRef } from "react";
import { Input, type InputProps } from "./input.tsx";

export type NumberInputProps = Omit<InputProps, "type">;

export const NumberInput = forwardRef<HTMLInputElement, NumberInputProps>(function NumberInput(props, ref) {
  return <Input ref={ref} type="number" inputMode="decimal" {...props} />;
});
