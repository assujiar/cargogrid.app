"use client";

/**
 * Toast primitive (`docs/design-system/02_COMPONENTS.md` "Toast") -- transient,
 * non-blocking confirmation. Built on Radix's `Toast` primitive (`ADR-0005`'s copy-in
 * mechanism, already a `radix-ui` dependency -- no new package added). `ToastProvider`
 * must wrap the portion of the tree that can trigger a toast (a client-component
 * boundary, e.g. a tenant route-group layout); `useToast()` is the imperative trigger.
 */

import { Toast as RadixToast } from "radix-ui";
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";

export type ToastTone = "info" | "success" | "warning" | "danger";

const TONE_CLASSES: Record<ToastTone, string> = {
  info: "border-info/30 bg-surface",
  success: "border-success/30 bg-surface",
  warning: "border-warning/30 bg-surface",
  danger: "border-danger/30 bg-surface",
};

export interface ToastOptions {
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
        {/* HDN-381 (Browser and Device Compatibility): a bare `w-80` (320px) plus the 16px
            `right-4` offset needs 336px of viewport width -- live-measured to overflow past
            the left edge on any viewport <=336px wide. `max-w-[calc(100vw-2rem)]` caps the
            viewport at the available width (viewport minus the 1rem left + 1rem right margin
            this component's own `bottom-4`/`right-4` offsets imply), so it shrinks on a
            narrow phone instead of clipping. */}
        <RadixToast.Viewport className="fixed bottom-4 right-4 z-50 flex w-80 max-w-[calc(100vw-2rem)] flex-col gap-2 outline-none" />
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

/**
 * `ISS-2026-246`: the shape every `useActionState` caller in this repository needs to raise a
 * toast, extracted once rather than copied into each of them.
 *
 * WHY THE `pending` EDGE AND NOT THE STATE VALUE
 *
 * The obvious trigger -- "fire whenever the success message is non-null" -- is wrong twice over.
 * It re-fires on any unrelated re-render while the message is still set, and it silently drops
 * the second of two identical submissions whenever the action returns a shared constant rather
 * than a fresh object (`hris/my/profile/actions.ts` returns one module-level `OK` constant on
 * every success, so two successful submissions are `Object.is`-equal and an identity check sees
 * no change).
 *
 * The `pending` true -> false transition has neither problem: it happens exactly once per
 * completed submission regardless of what the action returns, and never on first render
 * (`wasPendingRef` starts `false`). It is the same edge-detection
 * `components/forms/use-unsaved-change-guard.ts` already uses to re-take its saved baseline.
 *
 * Pass `null` for `options` when the settled state is not a success -- an errored submission
 * still crosses the edge, and its own `ValidationMessage` stays the place that reports it.
 */
export function useToastOnSettled(pending: boolean, options: ToastOptions | null): void {
  const { toast } = useToast();
  const optionsRef = useRef(options);
  const wasPendingRef = useRef(false);

  // Declared before the edge effect so it has already stored this commit's options by the time
  // the edge fires -- effects in one component run in declaration order.
  useEffect(() => {
    optionsRef.current = options;
  });

  useEffect(() => {
    if (wasPendingRef.current && !pending && optionsRef.current) {
      toast(optionsRef.current);
    }
    wasPendingRef.current = pending;
  }, [pending, toast]);
}
