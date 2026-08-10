"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type { LeaveTypeRow, LeaveCategory, EvidenceClassification, AccrualFrequency } from "../../../../../../server/contracts/leave/leave.ts";
import type { LeaveTypeActionState } from "./actions.ts";

type BoundAction = (prevState: LeaveTypeActionState, formData: FormData) => Promise<LeaveTypeActionState>;

const INITIAL_STATE: LeaveTypeActionState = { error: null };
const STATUS_TONE: Record<string, StatusTone> = { draft: "neutral", published: "success", archived: "neutral" };

function CreateTypeForm({ createLeaveTypeAction }: { createLeaveTypeAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createLeaveTypeAction, INITIAL_STATE);
  const [category, setCategory] = useState<LeaveCategory>("leave");
  const [requiresEvidence, setRequiresEvidence] = useState(false);

  return (
    <form action={formAction} className="grid grid-cols-1 gap-2 rounded-md border border-neutral-200 p-4 sm:grid-cols-2">
      <h2 className="text-sm font-semibold text-neutral-900 sm:col-span-2">New leave type</h2>
      <label className="text-xs text-neutral-500">
        Code
        <input name="code" required pattern="[a-z0-9_]{2,40}" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="annual_leave" />
      </label>
      <label className="text-xs text-neutral-500">
        Name
        <input name="name" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="Annual Leave" />
      </label>
      <label className="text-xs text-neutral-500">
        Category
        <select name="category" value={category} onChange={(e) => setCategory(e.target.value as LeaveCategory)} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          <option value="leave">Leave</option>
          <option value="permit">Permit</option>
          <option value="business_trip">Business trip</option>
        </select>
      </label>
      <div className="flex flex-col justify-end gap-1 text-xs text-neutral-500">
        <label className="inline-flex items-center gap-1">
          <input type="checkbox" name="requiresBalance" defaultChecked={category === "leave"} /> Requires balance
        </label>
        <label className="inline-flex items-center gap-1">
          <input type="checkbox" name="requiresEvidence" checked={requiresEvidence} onChange={(e) => setRequiresEvidence(e.target.checked)} /> Requires evidence
        </label>
      </div>
      {requiresEvidence ? (
        <label className="text-xs text-neutral-500 sm:col-span-2">
          Evidence classification
          <select name="evidenceClassification" defaultValue={"personal" as EvidenceClassification} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
            <option value="personal">Personal</option>
            <option value="medical">Medical</option>
          </select>
        </label>
      ) : (
        <input type="hidden" name="evidenceClassification" value="none" />
      )}
      <div className="sm:col-span-2">
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating…">
          Create leave type
        </Button>
      </div>
      {state.error ? <p role="alert" className="text-xs text-danger sm:col-span-2">{state.error}</p> : null}
    </form>
  );
}

function PublishTypeButton({ leaveTypeId, expectedVersion, publishLeaveTypeAction }: { leaveTypeId: string; expectedVersion: number; publishLeaveTypeAction: (id: string, v: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(publishLeaveTypeAction(leaveTypeId, expectedVersion), INITIAL_STATE);
  return (
    <form action={formAction}>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Publishing…">
        Publish
      </Button>
      {state.error ? <p role="alert" className="text-xs text-danger">{state.error}</p> : null}
    </form>
  );
}

function CreateVersionForm({ leaveTypeId, createAndPublishPolicyVersionAction }: { leaveTypeId: string; createAndPublishPolicyVersionAction: (id: string) => BoundAction }) {
  const [state, formAction, pending] = useActionState(createAndPublishPolicyVersionAction(leaveTypeId), INITIAL_STATE);
  const [accrualFrequency, setAccrualFrequency] = useState<AccrualFrequency>("none");

  return (
    <form action={formAction} className="mt-2 grid grid-cols-1 gap-2 rounded-md bg-neutral-50 p-3 sm:grid-cols-2">
      <label className="text-xs text-neutral-500">
        Effective from
        <input type="date" name="effectiveFrom" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Accrual frequency
        <select name="accrualFrequency" value={accrualFrequency} onChange={(e) => setAccrualFrequency(e.target.value as AccrualFrequency)} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          <option value="none">None</option>
          <option value="monthly">Monthly</option>
          <option value="annual">Annual</option>
        </select>
      </label>
      {accrualFrequency !== "none" ? (
        <label className="text-xs text-neutral-500">
          Accrual amount per period
          <input type="number" step="any" min="0" name="accrualAmountPerPeriod" defaultValue="1" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
      ) : null}
      <label className="text-xs text-neutral-500">
        Carry-forward max units (0 = use-it-or-lose-it)
        <input type="number" step="any" min="0" name="carryForwardMaxUnits" defaultValue="0" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Min notice days
        <input type="number" min="0" max="365" name="minNoticeDays" defaultValue="0" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Eligibility (min tenure days)
        <input type="number" min="0" name="eligibilityMinTenureDays" defaultValue="0" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="flex items-center gap-1 text-xs text-neutral-500">
        <input type="checkbox" name="negativeBalanceAllowed" /> Allow negative balance
      </label>
      <div className="sm:col-span-2">
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating and publishing…">
          Create and publish version
        </Button>
      </div>
      {state.error ? <p role="alert" className="text-xs text-danger sm:col-span-2">{state.error}</p> : null}
    </form>
  );
}

export function LeaveTypePanel({
  leaveTypes,
  createLeaveTypeAction,
  publishLeaveTypeAction,
  createAndPublishPolicyVersionAction,
}: {
  leaveTypes: LeaveTypeRow[];
  createLeaveTypeAction: BoundAction;
  publishLeaveTypeAction: (id: string, v: number) => BoundAction;
  createAndPublishPolicyVersionAction: (id: string) => BoundAction;
}) {
  const [expanded, setExpanded] = useState<string | null>(null);

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-xl font-semibold text-neutral-900">Leave types</h1>
      <CreateTypeForm createLeaveTypeAction={createLeaveTypeAction} />

      {leaveTypes.length === 0 ? (
        <EmptyState title="No leave types yet" description="Create one above -- no employee can request leave until a published type/policy applies to them." />
      ) : (
        <ul className="flex flex-col gap-2">
          {leaveTypes.map((t) => (
            <li key={t.id} className="rounded-md border border-neutral-200 p-3">
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium">
                  {t.name} <span className="text-xs text-neutral-500">({t.category.replace(/_/g, " ")})</span>
                </span>
                <StatusBadge tone={STATUS_TONE[t.status] ?? "neutral"} label={t.status} />
              </div>
              <p className="text-xs text-neutral-500">
                {t.requiresBalance ? "Balance-tracked" : "No balance"} · {t.requiresEvidence ? `Requires ${t.evidenceClassification} evidence` : "No evidence required"}
              </p>
              <div className="mt-2 flex flex-wrap gap-2">
                {t.status === "draft" ? <PublishTypeButton leaveTypeId={t.id} expectedVersion={t.recordVersion} publishLeaveTypeAction={publishLeaveTypeAction} /> : null}
                <Button type="button" variant="secondary" onClick={() => setExpanded(expanded === t.id ? null : t.id)}>
                  {expanded === t.id ? "Cancel" : "Add policy version"}
                </Button>
              </div>
              {expanded === t.id ? <CreateVersionForm leaveTypeId={t.id} createAndPublishPolicyVersionAction={createAndPublishPolicyVersionAction} /> : null}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
