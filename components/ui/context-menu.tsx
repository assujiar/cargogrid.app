"use client";

/** Context menu primitive (`docs/design-system/02_COMPONENTS.md` "Context menu") -- right-click action list. Built on Radix `ContextMenu`, same item shape as `DropdownMenu`. */

import { ContextMenu as RadixContextMenu } from "radix-ui";
import type { ReactNode } from "react";
import type { DropdownMenuItem } from "./dropdown-menu.tsx";

export interface ContextMenuProps {
  readonly children: ReactNode;
  readonly items: readonly DropdownMenuItem[];
}

export function ContextMenu({ children, items }: ContextMenuProps) {
  return (
    <RadixContextMenu.Root>
      <RadixContextMenu.Trigger asChild>{children}</RadixContextMenu.Trigger>
      <RadixContextMenu.Portal>
        <RadixContextMenu.Content className="z-50 min-w-40 rounded-md border border-neutral-200 bg-surface p-1 shadow-md focus:outline-none">
          {items.map((item) => (
            <RadixContextMenu.Item
              key={item.label}
              disabled={item.disabled}
              onSelect={item.onSelect}
              className={`cursor-pointer rounded px-2 py-1.5 text-sm outline-none data-[highlighted]:bg-neutral-100 data-[disabled]:cursor-not-allowed data-[disabled]:text-neutral-400 ${
                item.destructive ? "text-danger" : "text-text-primary"
              }`}
            >
              {item.label}
            </RadixContextMenu.Item>
          ))}
        </RadixContextMenu.Content>
      </RadixContextMenu.Portal>
    </RadixContextMenu.Root>
  );
}
