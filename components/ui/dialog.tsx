"use client";

/**
 * Dialog primitive (`docs/design-system/02_COMPONENTS.md` "Dialog") -- modal,
 * focus-trapped. Built on Radix `Dialog` (`ADR-0005` copy-in mechanism, already a
 * `radix-ui` dependency). `ConfirmationDialog` below is the destructive/override
 * variant requiring an explicit confirm action
 * (`09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §5 "Destructive confirmation" state).
 */

import { Dialog as RadixDialog } from "radix-ui";
import type { ReactNode } from "react";
import { Button, type ButtonVariant } from "./button.tsx";

export interface DialogProps {
  readonly open: boolean;
  readonly onOpenChange: (open: boolean) => void;
  readonly title: string;
  readonly description?: string;
  readonly children?: ReactNode;
  readonly trigger?: ReactNode;
}

export function Dialog({ open, onOpenChange, title, description, children, trigger }: DialogProps) {
  return (
    <RadixDialog.Root open={open} onOpenChange={onOpenChange}>
      {trigger ? <RadixDialog.Trigger asChild>{trigger}</RadixDialog.Trigger> : null}
      <RadixDialog.Portal>
        <RadixDialog.Overlay className="fixed inset-0 z-40 bg-neutral-900/40" />
        <RadixDialog.Content className="fixed left-1/2 top-1/2 z-50 w-full max-w-md -translate-x-1/2 -translate-y-1/2 rounded-md border border-neutral-200 bg-surface p-6 shadow-lg focus:outline-none">
          <RadixDialog.Title className="text-base font-semibold text-text-primary">{title}</RadixDialog.Title>
          {description ? <RadixDialog.Description className="mt-1 text-sm text-text-secondary">{description}</RadixDialog.Description> : null}
          {children ? <div className="mt-4">{children}</div> : null}
          <RadixDialog.Close aria-label="Close" className="absolute right-4 top-4 text-sm text-text-secondary">
            ×
          </RadixDialog.Close>
        </RadixDialog.Content>
      </RadixDialog.Portal>
    </RadixDialog.Root>
  );
}

export interface ConfirmationDialogProps {
  readonly open: boolean;
  readonly onOpenChange: (open: boolean) => void;
  readonly title: string;
  readonly description: string;
  readonly confirmLabel?: string;
  readonly cancelLabel?: string;
  readonly confirmVariant?: ButtonVariant;
  readonly onConfirm: () => void;
  readonly confirmLoading?: boolean;
}

/** Requires an explicit confirm click -- never closes on backdrop click alone for a destructive action (Radix's own `onInteractOutside`/`onEscapeKeyDown` are left at default, since dismissing via Escape/backdrop is equivalent to Cancel, not to committing the destructive action). */
export function ConfirmationDialog({
  open,
  onOpenChange,
  title,
  description,
  confirmLabel = "Confirm",
  cancelLabel = "Cancel",
  confirmVariant = "destructive",
  onConfirm,
  confirmLoading = false,
}: ConfirmationDialogProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange} title={title} description={description}>
      <div className="flex justify-end gap-2">
        <Button variant="secondary" onClick={() => onOpenChange(false)}>
          {cancelLabel}
        </Button>
        <Button variant={confirmVariant} onClick={onConfirm} loading={confirmLoading}>
          {confirmLabel}
        </Button>
      </div>
    </Dialog>
  );
}
