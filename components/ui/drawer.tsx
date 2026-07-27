"use client";

/**
 * Drawer/Sheet primitives (`docs/design-system/02_COMPONENTS.md` "Drawer"/"Sheet") --
 * side-anchored panel, e.g. record detail. Built on Radix `Dialog` (same focus-trap/
 * escape/backdrop behavior as `Dialog`, positioned as a side panel instead of centered)
 * -- one implementation shared by both names, since the spec itself says Sheet is "the
 * same shape as Drawer, mobile-first sizing" (`side="bottom"` on narrow viewports is the
 * caller's own responsibility via the `side` prop, not a separate component).
 */

import { Dialog as RadixDialog } from "radix-ui";
import type { ReactNode } from "react";

/** No slide-in transition is applied -- `tailwindcss-animate` (the usual source of `animate-in`/`slide-in-from-*` utilities) is not a dependency of this project, and this component does not fabricate the animation without it. */
const SIDE_CLASSES = {
  right: "inset-y-0 right-0 h-full w-full max-w-sm",
  left: "inset-y-0 left-0 h-full w-full max-w-sm",
  bottom: "inset-x-0 bottom-0 max-h-[80vh] w-full",
} as const;

export interface DrawerProps {
  readonly open: boolean;
  readonly onOpenChange: (open: boolean) => void;
  readonly title: string;
  readonly side?: keyof typeof SIDE_CLASSES;
  readonly children?: ReactNode;
  readonly trigger?: ReactNode;
}

export function Drawer({ open, onOpenChange, title, side = "right", children, trigger }: DrawerProps) {
  return (
    <RadixDialog.Root open={open} onOpenChange={onOpenChange}>
      {trigger ? <RadixDialog.Trigger asChild>{trigger}</RadixDialog.Trigger> : null}
      <RadixDialog.Portal>
        <RadixDialog.Overlay className="fixed inset-0 z-40 bg-neutral-900/40" />
        <RadixDialog.Content
          className={`fixed z-50 flex flex-col gap-4 border border-neutral-200 bg-surface p-6 shadow-lg focus:outline-none ${SIDE_CLASSES[side]}`}
        >
          <div className="flex items-center justify-between">
            <RadixDialog.Title className="text-base font-semibold text-text-primary">{title}</RadixDialog.Title>
            <RadixDialog.Close aria-label="Close" className="text-sm text-text-secondary">
              ×
            </RadixDialog.Close>
          </div>
          <div className="flex-1 overflow-y-auto">{children}</div>
        </RadixDialog.Content>
      </RadixDialog.Portal>
    </RadixDialog.Root>
  );
}
