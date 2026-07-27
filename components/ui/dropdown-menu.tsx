"use client";

/**
 * Dropdown menu primitive (`docs/design-system/02_COMPONENTS.md` "Dropdown menu") --
 * click-triggered action list. Built on Radix `DropdownMenu`. `items` is a flat list
 * (no submenu support yet -- no current consumer needs one); a `destructive` item is
 * styled danger-red but still requires its own confirmation step upstream if the action
 * itself is destructive (this menu is not a substitute for `ConfirmationDialog`).
 */

import { DropdownMenu as RadixDropdownMenu } from "radix-ui";
import type { ReactNode } from "react";

export interface DropdownMenuItem {
  readonly label: string;
  readonly onSelect: () => void;
  readonly disabled?: boolean;
  readonly destructive?: boolean;
}

export interface DropdownMenuProps {
  readonly trigger: ReactNode;
  readonly items: readonly DropdownMenuItem[];
  readonly align?: "start" | "center" | "end";
}

export function DropdownMenu({ trigger, items, align = "start" }: DropdownMenuProps) {
  return (
    <RadixDropdownMenu.Root>
      <RadixDropdownMenu.Trigger asChild>{trigger}</RadixDropdownMenu.Trigger>
      <RadixDropdownMenu.Portal>
        <RadixDropdownMenu.Content
          align={align}
          sideOffset={4}
          className="z-50 min-w-40 rounded-md border border-neutral-200 bg-surface p-1 shadow-md focus:outline-none"
        >
          {items.map((item) => (
            <RadixDropdownMenu.Item
              key={item.label}
              disabled={item.disabled}
              onSelect={item.onSelect}
              className={`cursor-pointer rounded px-2 py-1.5 text-sm outline-none data-[highlighted]:bg-neutral-100 data-[disabled]:cursor-not-allowed data-[disabled]:text-neutral-400 ${
                item.destructive ? "text-danger" : "text-text-primary"
              }`}
            >
              {item.label}
            </RadixDropdownMenu.Item>
          ))}
        </RadixDropdownMenu.Content>
      </RadixDropdownMenu.Portal>
    </RadixDropdownMenu.Root>
  );
}
