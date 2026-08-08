"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { ProcurementReportExportActionState } from "./actions.ts";

const INITIAL_STATE: ProcurementReportExportActionState = { error: null, success: false };

/** Client Component wrapper (PRC-266) -- same useActionState/bound-action split app/(tenant)/[tenantSlug]/finance/reports/export-report-form.tsx (FIN-213) already established. No parameter inputs in this bounded slice -- an export always covers the caller's own full accessible scope, the same disclosed choice the Finance/Operations dashboards already make. */
export function ExportProcurementReportForm({ action, label }: { action: (prevState: ProcurementReportExportActionState, formData: FormData) => Promise<ProcurementReportExportActionState>; label: string }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-1">
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Requesting…" className="w-fit text-xs">
        {label}
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
      {state.success ? (
        <p role="status" className="text-xs text-neutral-500">
          Export queued. No live worker processes it in this environment yet (disclosed) -- it will remain &quot;queued&quot; in the run history below.
        </p>
      ) : null}
    </form>
  );
}
