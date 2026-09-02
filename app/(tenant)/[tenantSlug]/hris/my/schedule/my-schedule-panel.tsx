"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type { MyScheduleRow, MySwapRequestRow } from "../../../../../../server/contracts/shift-roster/shift-roster.ts";
import type { MyScheduleActionState } from "./actions.ts";

type BoundAction = (prevState: MyScheduleActionState, formData: FormData) => Promise<MyScheduleActionState>;

const INITIAL_STATE: MyScheduleActionState = { error: null };
const SWAP_TONE: Record<string, StatusTone> = { pending_approval: "warning", approved: "success", rejected: "danger", cancelled: "neutral" };

function RequestSwapForm({ mySchedule, requestMySwapAction }: { mySchedule: MyScheduleRow[]; requestMySwapAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(requestMySwapAction, INITIAL_STATE);
  const describedBy = state.error ? "request-swap-error" : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4 sm:flex-row sm:flex-wrap sm:items-end" noValidate>
      <FormField id="swap-assignment-id" label="My shift to swap">
        <Select id="swap-assignment-id" name="assignmentId" required invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="">— select —</option>
          {mySchedule.map((s) => (
            <option key={s.assignmentId} value={s.assignmentId}>
              {s.workDate} — {s.shiftTemplateName}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id="swap-target-employee-id" label="Colleague's employee id">
        <Input id="swap-target-employee-id" name="targetEmployeeId" required placeholder="employee UUID" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="swap-target-assignment-id" label="Their shift's assignment id">
        <Input id="swap-target-assignment-id" name="targetAssignmentId" required placeholder="assignment UUID" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="swap-reason" label="Reason">
        <Input id="swap-reason" name="reason" required placeholder="e.g. family event" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Requesting…">
        Request swap
      </Button>
      {state.error ? <ValidationMessage id="request-swap-error">{state.error}</ValidationMessage> : null}
    </form>
  );
}

function CancelSwapButton({ requestId, expectedVersion, cancelMySwapAction }: { requestId: string; expectedVersion: number; cancelMySwapAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(cancelMySwapAction, INITIAL_STATE);
  return (
    <form action={formAction} className="mt-1">
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Cancelling…">
        Cancel request
      </Button>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
    </form>
  );
}

export function MySchedulePanel({
  mySchedule,
  mySwapRequests,
  requestMySwapAction,
  cancelMySwapAction,
}: {
  mySchedule: MyScheduleRow[];
  mySwapRequests: MySwapRequestRow[];
  requestMySwapAction: BoundAction;
  cancelMySwapAction: (requestId: string, expectedVersion: number) => BoundAction;
}) {
  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">My schedule</h1>

      {mySchedule.length === 0 ? (
        <EmptyState title="No published schedule yet" description="Once your scheduler assigns and publishes a shift for you, it will show up here." />
      ) : (
        <ul className="flex flex-col gap-2">
          {mySchedule.map((s) => (
            <li key={s.assignmentId} className="rounded-md border border-neutral-200 p-3">
              <p className="text-sm font-medium">
                {s.workDate} — {s.shiftTemplateName}
              </p>
              <p className="text-xs text-neutral-500">
                {s.shiftType}
                {s.crossesMidnight ? " (crosses midnight)" : ""}
              </p>
            </li>
          ))}
        </ul>
      )}

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-700">Request a shift swap</h2>
        <RequestSwapForm mySchedule={mySchedule} requestMySwapAction={requestMySwapAction} />
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-700">My swap requests</h2>
        {mySwapRequests.length === 0 ? (
          <EmptyState title="No swap requests yet" />
        ) : (
          <ul className="flex flex-col gap-2">
            {mySwapRequests.map((r) => (
              <li key={r.id} className="rounded-md border border-neutral-200 p-3">
                <div className="flex items-center justify-between">
                  <span className="text-sm">{r.role === "requester" ? "You requested this swap" : "A colleague requested this swap with you"}</span>
                  <StatusBadge tone={SWAP_TONE[r.status] ?? "neutral"} label={r.status} />
                </div>
                {r.status === "pending_approval" && r.role === "requester" ? (
                  <CancelSwapButton requestId={r.id} expectedVersion={r.recordVersion} cancelMySwapAction={cancelMySwapAction(r.id, r.recordVersion)} />
                ) : null}
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
