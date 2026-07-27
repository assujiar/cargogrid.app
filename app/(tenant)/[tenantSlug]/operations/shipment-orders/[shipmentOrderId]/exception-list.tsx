"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import type { ShipmentOrderFormState } from "./actions.ts";
import type { ExceptionDirectoryRow } from "../../../../../../server/contracts/exception-escalation/exception-escalation.ts";

const INITIAL_STATE: ShipmentOrderFormState = { error: null };

const STATUS_TONE: Record<ExceptionDirectoryRow["status"], "success" | "warning" | "danger" | "info" | "neutral"> = {
  open: "warning",
  acknowledged: "info",
  resolved: "success",
  reopened: "danger",
  closed: "neutral",
};

const ACTIONS_BY_STATUS: Record<ExceptionDirectoryRow["status"], readonly string[]> = {
  open: ["acknowledge", "escalate", "resolve", "assign_owner"],
  acknowledged: ["escalate", "resolve", "assign_owner"],
  reopened: ["acknowledge", "escalate", "resolve", "assign_owner"],
  resolved: ["close", "reopen"],
  closed: ["reopen"],
};

/** Read-only exception list plus one compact per-exception action control (OPS-174, Prompt 174 §15). */
export function ExceptionList({
  exceptions,
  actionFor,
}: {
  exceptions: readonly ExceptionDirectoryRow[];
  actionFor: (exceptionId: string, expectedVersion: number) => (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
}) {
  if (exceptions.length === 0) {
    return <p className="text-sm text-neutral-500">No exceptions reported yet.</p>;
  }

  return (
    <ol className="flex flex-col gap-3">
      {exceptions.map((exception) => (
        <ExceptionRow key={exception.id} exception={exception} action={actionFor(exception.id, exception.recordVersion)} />
      ))}
    </ol>
  );
}

function ExceptionRow({
  exception,
  action,
}: {
  exception: ExceptionDirectoryRow;
  action: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const availableActions = ACTIONS_BY_STATUS[exception.status];

  return (
    <li className="flex flex-col gap-2 border-b border-neutral-100 pb-3 last:border-b-0 last:pb-0">
      <div className="flex items-center gap-2">
        <span className="text-sm font-medium text-neutral-900">
          {exception.type} — {exception.severity}
        </span>
        <StatusBadge tone={STATUS_TONE[exception.status]} label={exception.status} />
        {exception.escalationLevel > 0 ? <StatusBadge tone="danger" label={`escalation level ${exception.escalationLevel}`} /> : null}
      </div>
      <p className="text-sm text-neutral-700">{exception.description}</p>
      <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-neutral-600">
        <dt>Owner</dt>
        <dd>{exception.ownerUserId ?? "—"}</dd>
        <dt>Due</dt>
        <dd>{exception.dueAt ? new Date(exception.dueAt).toLocaleString() : "—"}</dd>
        {exception.sensitiveMasked ? (
          <>
            <dt>Sensitive details</dt>
            <dd>Masked (requires OPS:View cost)</dd>
          </>
        ) : null}
      </dl>

      {availableActions.length > 0 ? (
        <form action={formAction} className="flex flex-wrap items-end gap-2">
          <select name="action" required className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" defaultValue="">
            <option value="" disabled>
              Choose an action…
            </option>
            {availableActions.map((availableAction) => (
              <option key={availableAction} value={availableAction}>
                {availableAction.replace("_", " ")}
              </option>
            ))}
          </select>
          {availableActions.includes("assign_owner") ? (
            <input name="ownerUserId" type="text" placeholder="Owner user ID (for assign owner)" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
          ) : null}
          <input name="reason" type="text" placeholder="Reason / evidence (as required)" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
          <Button type="submit" variant="secondary" loading={pending} loadingLabel="Working…" className="w-fit">
            Apply
          </Button>
        </form>
      ) : null}
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
    </li>
  );
}
