"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type { OvertimePolicyRow } from "../../../../../../server/contracts/overtime-timesheet/overtime-timesheet.ts";
import type { OvertimePolicyActionState } from "./actions.ts";

type BoundAction = (prevState: OvertimePolicyActionState, formData: FormData) => Promise<OvertimePolicyActionState>;

const INITIAL_STATE: OvertimePolicyActionState = { error: null };
const STATUS_TONE: Record<string, StatusTone> = { draft: "neutral", published: "success", archived: "neutral" };

function CreatePolicyForm({ createOvertimePolicyAction }: { createOvertimePolicyAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createOvertimePolicyAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-4">
      <label className="text-xs text-neutral-500">
        Policy name
        <input name="name" required className="mt-1 rounded border border-neutral-300 p-2 text-sm" placeholder="e.g. Jakarta Warehouse Overtime" />
      </label>
      <label className="text-xs text-neutral-500">
        Org unit id (optional -- blank = tenant-wide)
        <input name="orgUnitId" className="mt-1 rounded border border-neutral-300 p-2 text-sm" placeholder="org_unit UUID" />
      </label>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating…">
        Create policy
      </Button>
      {state.error ? <p role="alert" className="text-xs text-danger">{state.error}</p> : null}
    </form>
  );
}

function CreateVersionForm({ policyId, createAndPublishVersionAction }: { policyId: string; createAndPublishVersionAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createAndPublishVersionAction, INITIAL_STATE);

  return (
    <form action={formAction} className="mt-2 grid grid-cols-1 gap-2 rounded-md bg-neutral-50 p-3 sm:grid-cols-2">
      <label className="text-xs text-neutral-500">
        Effective from
        <input type="date" name="effectiveFrom" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Rounding increment (minutes)
        <input type="number" name="roundingIncrementMinutes" min="1" max="60" defaultValue="15" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Rounding mode
        <select name="roundingMode" defaultValue="nearest" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          <option value="nearest">Nearest</option>
          <option value="up">Up</option>
          <option value="down">Down</option>
        </select>
      </label>
      <label className="text-xs text-neutral-500">
        Minimum overtime threshold (minutes)
        <input type="number" name="minOvertimeMinutes" min="0" defaultValue="30" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Daily overtime cap (minutes, blank = no cap)
        <input type="number" name="dailyOvertimeCapMinutes" min="1" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="e.g. 180" />
      </label>
      <label className="text-xs text-neutral-500">
        Weekly overtime cap (minutes, blank = no cap)
        <input type="number" name="weeklyOvertimeCapMinutes" min="1" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="e.g. 600" />
      </label>
      <label className="text-xs text-neutral-500">
        Standard workday baseline (minutes)
        <input type="number" name="standardWorkdayMinutes" min="1" max="1440" defaultValue="480" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Default break deduction (minutes)
        <input type="number" name="defaultBreakDeductionMinutes" min="0" defaultValue="0" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="inline-flex items-center gap-1 text-xs text-neutral-500 sm:col-span-2">
        <input type="checkbox" name="requiresPreApproval" defaultChecked /> Requires pre-approval for planned overtime
      </label>
      <input type="hidden" name="policyId" value={policyId} />
      <div className="sm:col-span-2">
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating and publishing…">
          Create and publish version
        </Button>
      </div>
      {state.error ? <p role="alert" className="text-xs text-danger sm:col-span-2">{state.error}</p> : null}
    </form>
  );
}

export function OvertimePolicyPanel({
  policies,
  createOvertimePolicyAction,
  createAndPublishVersionAction,
}: {
  policies: OvertimePolicyRow[];
  createOvertimePolicyAction: BoundAction;
  createAndPublishVersionAction: (policyId: string) => BoundAction;
}) {
  const [expanded, setExpanded] = useState<string | null>(null);

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-xl font-semibold text-neutral-900">Overtime and timesheet policies</h1>
      <p className="text-xs text-neutral-500">Rounding, minimum threshold, and daily/weekly caps apply to overtime eligibility; rounding also governs ordinary timesheet-entry eligibility (one shared config surface).</p>
      <CreatePolicyForm createOvertimePolicyAction={createOvertimePolicyAction} />

      {policies.length === 0 ? (
        <EmptyState title="No overtime policies yet" description="Create one above -- no overtime request or timesheet entry can be decided until a published policy applies." />
      ) : (
        <ul className="flex flex-col gap-2">
          {policies.map((p) => (
            <li key={p.id} className="rounded-md border border-neutral-200 p-3">
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium">{p.name}</span>
                <StatusBadge tone={STATUS_TONE[p.status] ?? "neutral"} label={p.status} />
              </div>
              <p className="text-xs text-neutral-500">{p.orgUnitId ? `Scoped to org unit ${p.orgUnitId}` : "Tenant-wide"} — published version: {p.publishedVersionNumber ?? "none yet"}</p>
              <Button type="button" variant="secondary" onClick={() => setExpanded(expanded === p.id ? null : p.id)} className="mt-2">
                {expanded === p.id ? "Cancel" : "Add version"}
              </Button>
              {expanded === p.id ? <CreateVersionForm policyId={p.id} createAndPublishVersionAction={createAndPublishVersionAction(p.id)} /> : null}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
