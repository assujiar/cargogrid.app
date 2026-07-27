"use client";

/**
 * Toast primitive (`docs/design-system/02_COMPONENTS.md` "Toast") -- transient,
 * non-blocking confirmation. Built on Radix's `Toast` primitive (`ADR-0005`'s copy-in
 * mechanism, already a `radix-ui` dependency -- no new package added). `ToastProvider`
 * must wrap the portion of the tree that can trigger a toast (a client-component
 * boundary, e.g. a tenant route-group layout); `useToast()` is the imperative trigger.
 */

import { Toast as RadixToast } from "radix-ui";
import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from "react";

export type ToastTone = "info" | "success" | "warning" | "danger";

const TONE_CLASSES: Record<ToastTone, string> = {
  info: "border-info/30 bg-surface",
  success: "border-success/30 bg-surface",
  warning: "border-warning/30 bg-surface",
  danger: "border-danger/30 bg-surface",
};

interface ToastOptions {
  readonly title: string;
  readonly description?: string;
  readonly tone?: ToastTone;
}

interface ActiveToast extends ToastOptions {
  readonly id: number;
}

interface ToastContextValue {
  readonly toast: (options: ToastOptions) => void;
}

const ToastContext = createContext<ToastContextValue | null>(null);

let nextToastId = 0;

export function ToastProvider({ children }: { readonly children: ReactNode }) {
  const [toasts, setToasts] = useState<readonly ActiveToast[]>([]);

  const toast = useCallback((options: ToastOptions) => {
    const id = nextToastId++;
    setToasts((current) => [...current, { id, ...options }]);
  }, []);

  const removeToast = useCallback((id: number) => {
    setToasts((current) => current.filter((item) => item.id !== id));
  }, []);

  const value = useMemo(() => ({ toast }), [toast]);

  return (
    <ToastContext.Provider value={value}>
      <RadixToast.Provider swipeDirection="right">
        {children}
        {toasts.map((item) => (
          <RadixToast.Root
            key={item.id}
            duration={4000}
            onOpenChange={(open) => {
              if (!open) {
                removeToast(item.id);
              }
            }}
            className={`relative rounded-md border p-3 shadow-md ${TONE_CLASSES[item.tone ?? "info"]}`}
          >
            <RadixToast.Title className="text-sm font-semibold text-text-primary">{item.title}</RadixToast.Title>
            {item.description ? (
              <RadixToast.Description className="mt-0.5 text-sm text-text-secondary">{item.description}</RadixToast.Description>
            ) : null}
            <RadixToast.Close aria-label="Close" className="absolute right-2 top-2 text-xs text-text-secondary">
              ×
            </RadixToast.Close>
          </RadixToast.Root>
        ))}
        <RadixToast.Viewport className="fixed bottom-4 right-4 z-50 flex w-80 flex-col gap-2 outline-none" />
      </RadixToast.Provider>
    </ToastContext.Provider>
  );
}

export function useToast(): ToastContextValue {
  const context = useContext(ToastContext);
  if (!context) {
    throw new Error("useToast must be used within a ToastProvider");
  }
  return context;
}
