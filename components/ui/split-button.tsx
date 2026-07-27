"use client";

/**
 * Split Button (this checkpoint's own instruction named it; not previously scoped by
 * any CargoGrid design-system document -- `docs/design-system/08_COMPONENT_INVENTORY.md`
 * disclosed this gap. Built now as a reasonable, real implementation: a primary action
 * button plus an adjacent caret trigger opening a `DropdownMenu` of secondary actions,
 * composed from `Button`/`ButtonGroup`/`DropdownMenu` -- no new primitive mechanism.
 */

import { Button, type ButtonVariant } from "./button.tsx";
import { ButtonGroup } from "./button-group.tsx";
import { DropdownMenu, type DropdownMenuItem } from "./dropdown-menu.tsx";

export interface SplitButtonProps {
  readonly label: string;
  readonly onClick: () => void;
  readonly variant?: ButtonVariant;
  readonly disabled?: boolean;
  readonly secondaryActions: readonly DropdownMenuItem[];
}

export function SplitButton({ label, onClick, variant = "primary", disabled, secondaryActions }: SplitButtonProps) {
  return (
    <ButtonGroup label={label}>
      <Button variant={variant} onClick={onClick} disabled={disabled}>
        {label}
      </Button>
      <DropdownMenu
        align="end"
        items={secondaryActions}
        trigger={
          <Button variant={variant} disabled={disabled} aria-label={`More ${label} actions`} className="px-2">
            ▾
          </Button>
        }
      />
    </ButtonGroup>
  );
}
