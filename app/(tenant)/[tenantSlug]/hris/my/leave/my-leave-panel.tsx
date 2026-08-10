"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type { EmployeeLeaveBalanceRow, LeaveRequestListRow, LeaveTypeRow, DayPortion } from "../../../../../../server/contracts/leave/leave.ts";
import type { MyLeaveActionState } from "./actions.ts";

type BoundAction = (prevState: MyLeaveActionState, formData: FormData) => Promise<MyLeaveActionState>;

const INITIAL_STATE: MyLeaveActionState = { error: null };
const REQUEST_STATUS_TONE: Record<string, StatusTone> = {
  draft: "neutral",
  pending_approval: "warning",
  approved: "success",
  rejected: "danger",
  cancelled: "neutral",
};

function RequestLeaveForm({ leaveTypes, requestLeaveAction }: { leaveTypes: LeaveTypeRow[]; requestLeaveAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(requestLeaveAction, INITIAL_STATE);
  const [leaveTypeId, setLeaveTypeId] = useState(leaveTypes[0]?.id ?? "");
  const [dayPortion, setDayPortion] = useState<DayPortion>("full_day");
  const [idempotencyKey] = useState(() => `leave-${crypto.randomUUID()}`);
  const selectedType = leaveTypes.find((t) => t.id === leaveTypeId);

  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Request leave, permit or business trip</h2>
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label className="text-xs text-neutral-500">
        Type
        <select name="leaveTypeId" value={leaveTypeId} onChange={(e) => setLeaveTypeId(e.target.value)} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          {leaveTypes.map((t) => (
            <option key={t.id} value={t.id}>
              {t.name} ({t.category.replace(/_/g, " ")})
            </option>
          ))}
        </select>
      </label>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <label className="text-xs text-neutral-500">
          From
          <input type="date" name="dateFrom" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
        <label className="text-xs text-neutral-500">
          To
          <input type="date" name="dateTo" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
      </div>
      <label className="text-xs text-neutral-500">
        Portion
        <select name="dayPortion" value={dayPortion} onChange={(e) => setDayPortion(e.target.value as DayPortion)} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          <option value="full_day">Full day</option>
          <option value="half_day_morning">Half day (morning)</option>
          <option value="half_day_afternoon">Half day (afternoon)</option>
        </select>
      </label>
      {selectedType?.category === "business_trip" ? (
        <label className="text-xs text-neutral-500">
          Destination
          <input name="destination" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="City / site" />
        </label>
      ) : null}
      <label className="text-xs text-neutral-500">
        Reason
        <textarea name="reason" required minLength={1} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" rows={2} />
      </label>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Submitting…">
        Submit for approval
      </Button>
      {state.error ? <p role="alert" className="text-xs text-danger">{state.error}</p> : null}
    </form>
  );
}

function RequestRow({
  request,
  resubmitAction,
  cancelAction,
}: {
  request: LeaveRequestListRow;
  resubmitAction: (requestId: string, expectedVersion: number) => BoundAction;
  cancelAction: (requestId: string, expectedVersion: number) => BoundAction;
}) {
  const [resubmitState, resubmitFormAction, resubmitPending] = useActionState(resubmitAction(request.id, request.recordVersion), INITIAL_STATE);
  const [cancelState, cancelFormAction, cancelPending] = useActionState(cancelAction(request.id, request.recordVersion), INITIAL_STATE);
  const canCancel = request.status === "draft" || request.status === "pending_approval" || request.status === "approved";

  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>
          {request.leaveTypeCode.replace(/_/g, " ")} — {request.dateFrom}
          {request.dateTo !== request.dateFrom ? ` to ${request.dateTo}` : ""} ({request.dayPortion.replace(/_/g, " ")}, {request.totalUnits} unit(s))
        </span>
        <StatusBadge tone={REQUEST_STATUS_TONE[request.status] ?? "neutral"} label={request.status.replace(/_/g, " ")} />
      </div>
      {request.reasonVisible && request.reason ? <p className="text-xs text-neutral-500">{request.reason}</p> : null}
      <div className="flex flex-wrap items-center gap-2">
        {request.status === "draft" ? (
          <form action={resubmitFormAction}>
            <Button type="submit" variant="secondary" loading={resubmitPending} loadingLabel="Resubmitting…">
              Resubmit
            </Button>
          </form>
        ) : null}
        {canCancel ? (
          <form action={cancelFormAction} className="flex flex-1 items-center gap-2">
            <input name="cancelReason" required placeholder="Cancellation reason (required)" className="min-w-[10rem] flex-1 rounded border border-neutral-300 p-2 text-xs" />
            <Button type="submit" variant="destructive" loading={cancelPending} loadingLabel="Cancelling…">
              Cancel
            </Button>
          </form>
        ) : null}
      </div>
      {resubmitState.error ? <p role="alert" className="text-xs text-danger">{resubmitState.error}</p> : null}
      {cancelState.error ? <p role="alert" className="text-xs text-danger">{cancelState.error}</p> : null}
    </li>
  );
}

export function MyLeavePanel({
  balances,
  requests,
  leaveTypes,
  requestLeaveAction,
  resubmitLeaveRequestAction,
  cancelMyLeaveRequestAction,
}: {
  balances: EmployeeLeaveBalanceRow[];
  requests: LeaveRequestListRow[];
  leaveTypes: LeaveTypeRow[];
  requestLeaveAction: BoundAction;
  resubmitLeaveRequestAction: (requestId: string, expectedVersion: number) => BoundAction;
  cancelMyLeaveRequestAction: (requestId: string, expectedVersion: number) => BoundAction;
}) {
  return (
    <div className="mx-auto flex max-w-lg flex-col gap-4">
      <h1 className="text-xl font-semibold text-neutral-900">My leave, permits and business trips</h1>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Balances</h2>
        {balances.length === 0 ? (
          <EmptyState title="No leave types available yet" description="HR has not published a leave type for this tenant yet." />
        ) : (
          <div className="overflow-x-auto rounded-md border border-neutral-200">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-neutral-500">
                  <th className="p-2">Type</th>
                  <th className="p-2">Available</th>
                  <th className="p-2">Pending</th>
                </tr>
              </thead>
              <tbody>
                {balances.map((b) => (
                  <tr key={b.leaveTypeId} className="border-t border-neutral-100">
                    <td className="p-2">{b.name}</td>
                    <td className="p-2">{b.requiresBalance ? b.balance : "—"}</td>
                    <td className="p-2">{b.requiresBalance && b.pendingUnits > 0 ? b.pendingUnits : "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {leaveTypes.length > 0 ? <RequestLeaveForm leaveTypes={leaveTypes} requestLeaveAction={requestLeaveAction} /> : null}

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">My requests</h2>
        {requests.length === 0 ? (
          <EmptyState title="No leave requests yet" description="Requests you submit will appear here with their review status." />
        ) : (
          <ul className="flex flex-col gap-2">
            {requests.map((r) => (
              <RequestRow key={r.id} request={r} resubmitAction={resubmitLeaveRequestAction} cancelAction={cancelMyLeaveRequestAction} />
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
