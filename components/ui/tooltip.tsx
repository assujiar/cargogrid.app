"use client";

/**
 * Tooltip primitive (`docs/design-system/02_COMPONENTS.md` "Tooltip") --
 * hover/focus-triggered supplementary text. Built on Radix `Tooltip`, which already
 * implements the correct hover+focus (not click) trigger and Escape-to-dismiss
 * behavior. `TooltipProvider` controls the shared hover-delay and is **required**, not
 * optional: at the pinned `@radix-ui/react-tooltip@1.2.13` the provider context is built by
 * `createTooltipContext("TooltipProvider")` with no default value, so a bare `Tooltip` with no
 * provider above it throws "`Tooltip` must be used within `TooltipProvider`" the moment it
 * renders. (An earlier version of this comment claimed Radix falls back to an implicit
 * provider; it does not -- corrected against the installed source when `ISS-2026-246`'s
 * overlays lane wired the first real consumer, which would have crashed on that advice.)
 * Wrap the app/portal shell once, or -- as `admin/api-keys/api-keys-admin-panel.tsx` does --
 * wrap the single self-contained help affordance that needs it.
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
