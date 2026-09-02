"use client";

/**
 * Onboarding/Offboarding bulk-export form (ISS-2026-070 item 3). Sibling of
 * `components/domain/recruitment-export-form.tsx` -- same `useActionState` +
 * blob-download interaction, same result-state contract, same "nothing downloaded" /
 * "N rows exported" messaging. See `lib/onboarding/onboarding-export-action.ts`'s own
 * header for why this is a sibling file rather than a shared generic import.
 */

import { useActionState, useEffect, useRef } from "react";
import { Button } from "../ui/button.tsx";

export interface OnboardingExportActionState {
  readonly error: string | null;
  readonly csv: string | null;
  readonly filename: string | null;
  readonly rowCount: number;
  readonly token: string | null;
}

export const ONBOARDING_EXPORT_INITIAL_STATE: OnboardingExportActionState = { error: null, csv: null, filename: null, rowCount: 0, token: null };

export function OnboardingExportForm({
  label,
  description,
  action,
}: {
  label: string;
  description: string;
  action: (prevState: OnboardingExportActionState, formData: FormData) => Promise<OnboardingExportActionState>;
}) {
  const [state, formAction, pending] = useActionState(action, ONBOARDING_EXPORT_INITIAL_STATE);
  const downloadedToken = useRef<string | null>(null);

  useEffect(() => {
    if (!state.csv || !state.filename || !state.token) return;
    if (downloadedToken.current === state.token) return;
    downloadedToken.current = state.token;

    const blob = new Blob([state.csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = state.filename;
    link.click();
    URL.revokeObjectURL(url);
  }, [state]);

  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <div>
        <h2 className="text-sm font-semibold text-neutral-900">{label}</h2>
        <p className="mt-1 text-xs text-neutral-500">{description}</p>
      </div>

      <form action={formAction}>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Preparing export…">
          Download CSV
        </Button>
      </form>

      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}

      {!state.error && state.token && state.rowCount === 0 ? (
        <p role="status" className="text-xs text-neutral-500">
          No rows to export. Nothing was downloaded.
        </p>
      ) : null}

      {!state.error && state.token && state.rowCount > 0 ? (
        <p role="status" className="text-xs text-neutral-500">
          {state.rowCount} row{state.rowCount === 1 ? "" : "s"} exported to {state.filename}.
        </p>
      ) : null}
    </section>
  );
}
