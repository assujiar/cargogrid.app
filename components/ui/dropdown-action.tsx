"use client";

/**
 * Dropdown Action (this checkpoint's own instruction named it; not previously scoped
 * by any CargoGrid design-system document, same disclosed gap as `SplitButton`).
 * A thin, named preset over the existing `DropdownMenu` for the common "single button
 * that opens an action list" shape, saving the caller from repeating the caret-button
 * trigger markup every time.
 */

import { Button, type ButtonVariant } from "./button.tsx";
import { DropdownMenu, type DropdownMenuItem } from "./dropdown-menu.tsx";

export interface DropdownActionProps {
  readonly label: string;
  readonly variant?: ButtonVariant;
  readonly disabled?: boolean;
  readonly items: readonly DropdownMenuItem[];
}

export function DropdownAction({ label, variant = "secondary", disabled, items }: DropdownActionProps) {
  return (
    <DropdownMenu
      items={items}
      trigger={
        <Button variant={variant} disabled={disabled}>
          {label} ▾
        </Button>
      }
    />
  );
}
