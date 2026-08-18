"use client";

import { useActionState } from "react";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { Button } from "../../../../../components/ui/button.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { LoyaltyExpiryRun } from "../../../../../server/contracts/customer-portal-loyalty-expiry-fraud/customer-portal-loyalty-expiry-fraud.ts";
import { runLoyaltyExpirySweepAction, type LoyaltyExpiryAdminFormState } from "./actions.ts";

const INITIAL_STATE: LoyaltyExpiryAdminFormState = { error: null };

const STATUS_TONE: Record<LoyaltyExpiryRun["status"], StatusTone> = {
  pending: "neutral",
  in_progress: "info",
  cancelling: "warning",
  cancelled: "neutral",
  completed: "success",
  failed: "danger",
  dead_letter: "danger",
};

export function RunLoyaltyExpirySweepForm({ tenantSlug }: { tenantSlug: string }) {
  const [state, formAction, pending] = useActionState(runLoyaltyExpirySweepAction.bind(null, tenantSlug), INITIAL_STATE);
  return (
    <form action={formAction} noValidate className="flex flex-col items-start gap-2 rounded-md border border-neutral-200 p-4">
      <p className="text-sm text-text-secondary">
        Composes the point-lot and benefit-entitlement expiry scans tenant-wide. Idempotent per calendar day -- running it again today is a safe no-op. No live scheduler exists yet (disclosed, ISS-2026-133); this is the real,
        callable entry point a future scheduler would invoke.
      </p>
      <div className="flex flex-wrap items-end gap-3">
        <div>
          <label htmlFor="expiry-run-label" className="block text-xs font-medium text-text-secondary">
            Run label (optional)
          </label>
          <input id="expiry-run-label" name="runLabel" type="text" placeholder="defaults to today's date" className="w-56 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
        </div>
        <Button type="submit" loading={pending} loadingLabel="Running sweep…" className="w-fit">
          Run expiry sweep
        </Button>
      </div>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

export function LoyaltyExpiryRunHistoryTable({ runs }: { runs: readonly LoyaltyExpiryRun[] }) {
  if (runs.length === 0) {
    return <EmptyState title="No expiry sweep runs yet" description="Run a sweep above and it will appear here." />;
  }
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[720px] text-left text-sm">
        <thead>
          <tr className="border-b border-neutral-200 text-xs text-text-secondary">
            <th className="py-2 pr-3">Run label</th>
            <th className="py-2 pr-3">Status</th>
            <th className="py-2 pr-3">Lots expired</th>
            <th className="py-2 pr-3">Entitlements expired</th>
            <th className="py-2 pr-3">As of</th>
            <th className="py-2 pr-3">Completed</th>
          </tr>
        </thead>
        <tbody>
          {runs.map((run) => (
            <tr key={run.jobId} className="border-b border-neutral-100">
              <td className="py-2 pr-3">{run.runLabel ?? "—"}</td>
              <td className="py-2 pr-3">
                <StatusBadge tone={STATUS_TONE[run.status]} label={run.status} />
              </td>
              <td className="py-2 pr-3">{run.lotsExpiredCount}</td>
              <td className="py-2 pr-3">{run.entitlementsExpiredCount}</td>
              <td className="py-2 pr-3">{run.asOf ? new Date(run.asOf).toLocaleString() : "—"}</td>
              <td className="py-2 pr-3">{run.completedAt ? new Date(run.completedAt).toLocaleString() : "—"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
