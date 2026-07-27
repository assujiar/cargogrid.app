"use client";

/**
 * Tooltip primitive (`docs/design-system/02_COMPONENTS.md` "Tooltip") --
 * hover/focus-triggered supplementary text. Built on Radix `Tooltip`, which already
 * implements the correct hover+focus (not click) trigger and Escape-to-dismiss
 * behavior. `TooltipProvider` should wrap the app/portal shell once (controls the
 * shared hover-delay); a route that hasn't wired it can still use `Tooltip` directly --
 * Radix creates an implicit provider with default delay if none is found.
 */

import { Tooltip as RadixTooltip } from "radix-ui";
import type { ReactNode } from "react";

export const TooltipProvider = RadixTooltip.Provider;

export interface TooltipProps {
  readonly content: ReactNode;
  readonly children: ReactNode;
}

export function Tooltip({ content, children }: TooltipProps) {
  return (
    <RadixTooltip.Root>
      <RadixTooltip.Trigger asChild>{children}</RadixTooltip.Trigger>
      <RadixTooltip.Portal>
        <RadixTooltip.Content
          sideOffset={4}
          className="z-50 rounded-md bg-neutral-900 px-2 py-1 text-xs text-neutral-50 shadow-md"
        >
          {content}
          <RadixTooltip.Arrow className="fill-neutral-900" />
        </RadixTooltip.Content>
      </RadixTooltip.Portal>
    </RadixTooltip.Root>
  );
}
