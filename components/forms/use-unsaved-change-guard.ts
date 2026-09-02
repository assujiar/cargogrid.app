"use client";

import { useEffect, useRef, useState } from "react";

/**
 * ISS-2026-070 item 5: shared unsaved-change protection for multi-field forms.
 *
 * This is not a new mechanism. `app/(tenant)/[tenantSlug]/finance/config/
 * finance-config-forms.tsx` established the pattern, and
 * `hris/employees/[masterRecordId]/positions/employee-position-panel.tsx` and
 * `hris/positions/[positionId]/position-detail-panel.tsx` each grew a
 * byte-identical private `useUnsavedChangeGuard<T>` copy of it. ISS-2026-070's
 * own item 5 asks for the same guard on the onboarding case-start and
 * template-authoring forms, which would have been a fourth and fifth copy --
 * so the two identical copies were lifted here verbatim instead, and the new
 * call sites import them.
 *
 * `useUnsavedChangeGuard` is that lifted implementation, unchanged in
 * behaviour. `useUnsavedFormGuard` is its sibling for the uncontrolled forms
 * this repository also writes (a `<form action={…}>` whose fields carry
 * `defaultValue` and are read out of `FormData` rather than React state):
 * converting those to controlled state purely to detect dirtiness would be a
 * far larger and riskier change than the guard is worth, and would quietly
 * alter how every one of their fields behaves.
 */

/** The one `beforeunload` registration both hooks share. Kept private: a caller
 * that wants the browser prompt wants one of the two hooks below, never this. */
function useBeforeUnloadWhileDirty(dirty: boolean): void {
  useEffect(() => {
    if (!dirty) return;
    const handler = (event: BeforeUnloadEvent) => {
      event.preventDefault();
    };
    window.addEventListener("beforeunload", handler);
    return () => window.removeEventListener("beforeunload", handler);
  }, [dirty]);
}

/**
 * Controlled-form guard. `values` is the current field-value object, `initial`
 * the last-saved baseline. A browser-native "leave site?" prompt is armed while
 * the two differ, and the baseline is re-taken once a submission completes
 * without error. Returns whether the form is currently dirty.
 *
 * Behaviourally identical to the private copies it replaces, including the
 * deliberate `JSON.stringify` comparison (these value objects are flat records
 * of strings) and the `wasPendingRef` edge-detection that re-takes the baseline
 * only on a pending -> not-pending transition, never on first render.
 */
export function useUnsavedChangeGuard<T>(values: T, pending: boolean, error: string | null, initial: T): boolean {
  const [savedValues, setSavedValues] = useState(initial);
  const dirty = JSON.stringify(values) !== JSON.stringify(savedValues);
  const valuesRef = useRef(values);
  const wasPendingRef = useRef(false);

  useEffect(() => {
    valuesRef.current = values;
  }, [values]);

  useBeforeUnloadWhileDirty(dirty);

  useEffect(() => {
    if (wasPendingRef.current && !pending && error === null) {
      setSavedValues(valuesRef.current);
    }
    wasPendingRef.current = pending;
  }, [pending, error]);

  return dirty;
}

/**
 * Uncontrolled-form guard. Spread the returned `formProps` onto the `<form>`:
 * any real user input inside it marks the form dirty (React's `onInput` is a
 * delegated listener, so it fires for every descendant field without each field
 * needing its own handler or a controlled value), and the flag clears once a
 * submission completes without error -- the same "saved, so no longer dirty"
 * rule the controlled guard applies.
 *
 * Deliberately coarser than the controlled guard: it cannot tell that a user
 * typed a value and then typed the original back, so it will warn about a form
 * that is technically unchanged. That is the safe direction to err in for a
 * data-loss prompt, and it costs nothing but an occasional extra confirmation.
 */
export function useUnsavedFormGuard(
  pending: boolean,
  error: string | null,
): { dirty: boolean; formProps: { onInput: () => void } } {
  const [dirty, setDirty] = useState(false);
  const wasPendingRef = useRef(false);

  useBeforeUnloadWhileDirty(dirty);

  useEffect(() => {
    if (wasPendingRef.current && !pending && error === null) {
      setDirty(false);
    }
    wasPendingRef.current = pending;
  }, [pending, error]);

  return {
    dirty,
    formProps: {
      onInput: () => setDirty(true),
    },
  };
}
