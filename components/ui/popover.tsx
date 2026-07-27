"use client";

/** Popover primitive (`docs/design-system/02_COMPONENTS.md` "Popover") -- click-triggered floating content. Built on Radix `Popover`. */

import { Popover as RadixPopover } from "radix-ui";
import type { ReactNode } from "react";

export interface PopoverProps {
  readonly trigger: ReactNode;
  readonly children: ReactNode;
  readonly open?: boolean;
  readonly onOpenChange?: (open: boolean) => void;
}

export function Popover({ trigger, children, open, onOpenChange }: PopoverProps) {
  return (
    <RadixPopover.Root open={open} onOpenChange={onOpenChange}>
      <RadixPopover.Trigger asChild>{trigger}</RadixPopover.Trigger>
      <RadixPopover.Portal>
        <RadixPopover.Content
          sideOffset={4}
          className="z-50 max-w-xs rounded-md border border-neutral-200 bg-surface p-3 text-sm text-text-primary shadow-md focus:outline-none"
        >
          {children}
          <RadixPopover.Arrow className="fill-surface" />
        </RadixPopover.Content>
      </RadixPopover.Portal>
    </RadixPopover.Root>
  );
}
