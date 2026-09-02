"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { Checkbox } from "../../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type { OvertimePolicyRow } from "../../../../../../server/contracts/overtime-timesheet/overtime-timesheet.ts";
import type { OvertimePolicyActionState } from "./actions.ts";

type BoundAction = (prevState: OvertimePolicyActionState, formData: FormData) => Promise<OvertimePolicyActionState>;

const INITIAL_STATE: OvertimePolicyActionState = { error: null };
const STATUS_TONE: Record<string, StatusTone> = { draft: "neutral", published: "success", archived: "neutral" };

function CreatePolicyForm({ createOvertimePolicyAction }: { createOvertimePolicyAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createOvertimePolicyAction, INITIAL_STATE);
  const describedBy = state.error ? "create-policy-error" : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <FormField id="overtime-policy-name" label="Policy name">
        <Input id="overtime-policy-name" name="name" required placeholder="e.g. Jakarta Warehouse Overtime" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="overtime-policy-org-unit" label="Org unit id (optional -- blank = tenant-wide)">
        <Input id="overtime-policy-org-unit" name="orgUnitId" placeholder="org_unit UUID" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating…">
        Create policy
      </Button>
      {state.error ? <ValidationMessage id="create-policy-error">{state.error}</ValidationMessage> : null}
    </form>
  );
}

function CreateVersionForm({ policyId, createAndPublishVersionAction }: { policyId: string; createAndPublishVersionAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createAndPublishVersionAction, INITIAL_STATE);
  const describedBy = state.error ? `create-version-${policyId}-error` : undefined;

  return (
    <form action={formAction} className="mt-2 grid grid-cols-1 gap-2 rounded-md bg-neutral-50 p-3 sm:grid-cols-2" noValidate>
      <FormField id={`version-effective-from-${policyId}`} label="Effective from">
        <Input id={`version-effective-from-${policyId}`} type="date" name="effectiveFrom" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`version-rounding-increment-${policyId}`} label="Rounding increment (minutes)">
        <Input id={`version-rounding-increment-${policyId}`} type="number" name="roundingIncrementMinutes" min="1" max="60" defaultValue="15" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`version-rounding-mode-${policyId}`} label="Rounding mode">
        <Select id={`version-rounding-mode-${policyId}`} name="roundingMode" defaultValue="nearest" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="nearest">Nearest</option>
          <option value="up">Up</option>
          <option value="down">Down</option>
        </Select>
      </FormField>
      <FormField id={`version-min-overtime-${policyId}`} label="Minimum overtime threshold (minutes)">
        <Input id={`version-min-overtime-${policyId}`} type="number" name="minOvertimeMinutes" min="0" defaultValue="30" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`version-daily-cap-${policyId}`} label="Daily overtime cap (minutes, blank = no cap)">
        <Input id={`version-daily-cap-${policyId}`} type="number" name="dailyOvertimeCapMinutes" min="1" placeholder="e.g. 180" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`version-weekly-cap-${policyId}`} label="Weekly overtime cap (minutes, blank = no cap)">
        <Input id={`version-weekly-cap-${policyId}`} type="number" name="weeklyOvertimeCapMinutes" min="1" placeholder="e.g. 600" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`version-standard-workday-${policyId}`} label="Standard workday baseline (minutes)">
        <Input id={`version-standard-workday-${policyId}`} type="number" name="standardWorkdayMinutes" min="1" max="1440" defaultValue="480" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`version-break-deduction-${policyId}`} label="Default break deduction (minutes)">
        <Input id={`version-break-deduction-${policyId}`} type="number" name="defaultBreakDeductionMinutes" min="0" defaultValue="0" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <div className="sm:col-span-2">
        <Checkbox id={`version-pre-approval-${policyId}`} name="requiresPreApproval" defaultChecked label="Requires pre-approval for planned overtime" aria-describedby={describedBy} />
      </div>
      <input type="hidden" name="policyId" value={policyId} />
      <div className="sm:col-span-2">
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating and publishing…">
          Create and publish version
        </Button>
      </div>
      {state.error ? (
        <div className="sm:col-span-2">
          <ValidationMessage id={`create-version-${policyId}-error`}>{state.error}</ValidationMessage>
        </div>
      ) : null}
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
