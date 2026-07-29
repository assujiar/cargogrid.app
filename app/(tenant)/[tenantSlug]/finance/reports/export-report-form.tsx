"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { ReportExportFormState } from "./actions.ts";

const INITIAL_STATE: ReportExportFormState = { error: null, success: false };

/** Client Component wrapper (FIN-213) -- same `useActionState`/bound-action split `operations/reports/export-report-form.tsx` (OPS-183) already established. No parameter inputs in this bounded slice -- an export always covers the caller's own full accessible scope, the same disclosed choice the Finance Dashboard already makes. */
export function ExportFinanceReportForm({ action }: { action: (prevState: ReportExportFormState, formData: FormData) => Promise<ReportExportFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Requesting…">
        Request export
      </Button>
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
      {state.success ? (
        <p role="status" className="text-sm text-text-secondary">
          Export queued. No live worker processes it in this environment yet (disclosed) -- it will remain &quot;queued&quot; in the run history below.
        </p>
      ) : null}
    </form>
  );
}
