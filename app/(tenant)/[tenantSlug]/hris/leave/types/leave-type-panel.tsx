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
import type { LeaveTypeRow, LeaveCategory, EvidenceClassification, AccrualFrequency } from "../../../../../../server/contracts/leave/leave.ts";
import type { LeaveTypeActionState } from "./actions.ts";

type BoundAction = (prevState: LeaveTypeActionState, formData: FormData) => Promise<LeaveTypeActionState>;

const INITIAL_STATE: LeaveTypeActionState = { error: null };
const STATUS_TONE: Record<string, StatusTone> = { draft: "neutral", published: "success", archived: "neutral" };

function CreateTypeForm({ createLeaveTypeAction }: { createLeaveTypeAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createLeaveTypeAction, INITIAL_STATE);
  const [category, setCategory] = useState<LeaveCategory>("leave");
  const [requiresEvidence, setRequiresEvidence] = useState(false);

  const describedBy = state.error ? "create-leave-type-error" : undefined;
  return (
    <form action={formAction} className="grid grid-cols-1 gap-2 rounded-md border border-neutral-200 p-4 sm:grid-cols-2" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900 sm:col-span-2">New leave type</h2>
      <FormField id="leave-type-code" label="Code">
        <Input id="leave-type-code" name="code" required pattern="[a-z0-9_]{2,40}" placeholder="annual_leave" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="leave-type-name" label="Name">
        <Input id="leave-type-name" name="name" required placeholder="Annual Leave" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="leave-type-category" label="Category">
        <Select id="leave-type-category" name="category" value={category} onChange={(e) => setCategory(e.target.value as LeaveCategory)} invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="leave">Leave</option>
          <option value="permit">Permit</option>
          <option value="business_trip">Business trip</option>
        </Select>
      </FormField>
      <div className="flex flex-col justify-end gap-1">
        <Checkbox name="requiresBalance" defaultChecked={category === "leave"} label="Requires balance" aria-describedby={describedBy} />
        <Checkbox name="requiresEvidence" checked={requiresEvidence} onChange={(e) => setRequiresEvidence(e.target.checked)} label="Requires evidence" aria-describedby={describedBy} />
      </div>
      {requiresEvidence ? (
        <div className="sm:col-span-2">
          <FormField id="leave-type-evidence-classification" label="Evidence classification">
            <Select id="leave-type-evidence-classification" name="evidenceClassification" defaultValue={"personal" as EvidenceClassification} invalid={Boolean(state.error)} aria-describedby={describedBy}>
              <option value="personal">Personal</option>
              <option value="medical">Medical</option>
            </Select>
          </FormField>
        </div>
      ) : (
        <input type="hidden" name="evidenceClassification" value="none" />
      )}
      <div className="sm:col-span-2">
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating…">
          Create leave type
        </Button>
      </div>
      {state.error ? (
        <div className="sm:col-span-2">
          <ValidationMessage id="create-leave-type-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
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
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function CreateVersionForm({ leaveTypeId, createAndPublishPolicyVersionAction }: { leaveTypeId: string; createAndPublishPolicyVersionAction: (id: string) => BoundAction }) {
  const [state, formAction, pending] = useActionState(createAndPublishPolicyVersionAction(leaveTypeId), INITIAL_STATE);
  const [accrualFrequency, setAccrualFrequency] = useState<AccrualFrequency>("none");

  const describedBy = state.error ? `create-leave-version-${leaveTypeId}-error` : undefined;
  return (
    <form action={formAction} className="mt-2 grid grid-cols-1 gap-2 rounded-md bg-neutral-50 p-3 sm:grid-cols-2" noValidate>
      <FormField id={`lv-effective-from-${leaveTypeId}`} label="Effective from">
        <Input id={`lv-effective-from-${leaveTypeId}`} type="date" name="effectiveFrom" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`lv-accrual-frequency-${leaveTypeId}`} label="Accrual frequency">
        <Select id={`lv-accrual-frequency-${leaveTypeId}`} name="accrualFrequency" value={accrualFrequency} onChange={(e) => setAccrualFrequency(e.target.value as AccrualFrequency)} invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="none">None</option>
          <option value="monthly">Monthly</option>
          <option value="annual">Annual</option>
        </Select>
      </FormField>
      {accrualFrequency !== "none" ? (
        <FormField id={`lv-accrual-amount-${leaveTypeId}`} label="Accrual amount per period">
          <Input id={`lv-accrual-amount-${leaveTypeId}`} type="number" step="any" min="0" name="accrualAmountPerPeriod" defaultValue="1" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      ) : null}
      <FormField id={`lv-carry-forward-${leaveTypeId}`} label="Carry-forward max units (0 = use-it-or-lose-it)">
        <Input id={`lv-carry-forward-${leaveTypeId}`} type="number" step="any" min="0" name="carryForwardMaxUnits" defaultValue="0" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`lv-min-notice-${leaveTypeId}`} label="Min notice days">
        <Input id={`lv-min-notice-${leaveTypeId}`} type="number" min="0" max="365" name="minNoticeDays" defaultValue="0" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`lv-min-tenure-${leaveTypeId}`} label="Eligibility (min tenure days)">
        <Input id={`lv-min-tenure-${leaveTypeId}`} type="number" min="0" name="eligibilityMinTenureDays" defaultValue="0" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Checkbox id={`lv-negative-balance-${leaveTypeId}`} name="negativeBalanceAllowed" label="Allow negative balance" aria-describedby={describedBy} />
      <div className="sm:col-span-2">
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating and publishing…">
          Create and publish version
        </Button>
      </div>
      {state.error ? (
        <div className="sm:col-span-2">
          <ValidationMessage id={`create-leave-version-${leaveTypeId}-error`}>{state.error}</ValidationMessage>
        </div>
      ) : null}
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
