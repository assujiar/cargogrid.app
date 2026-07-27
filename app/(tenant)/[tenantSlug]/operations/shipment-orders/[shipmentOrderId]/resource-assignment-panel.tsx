"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import type { ShipmentOrderFormState } from "./actions.ts";
import type { AssignmentCandidate, ResourceAssignment, ResourceAssignmentRole } from "../../../../../../server/contracts/resource-assignment/resource-assignment.ts";

const INITIAL_STATE: ShipmentOrderFormState = { error: null };

const ROLE_LABELS: Record<ResourceAssignmentRole, string> = {
  vendor: "Vendor",
  fleet: "Fleet",
  vehicle: "Vehicle",
  driver: "Driver",
};

/**
 * One (shipmentOrderId, role) assignment slot (OPS-172, Prompt 172 §15). Shows the
 * current assignment (if any, active or held) with its own minimized {code, name}
 * snapshot -- never app.master_records.attributes -- and the one action available for
 * its current state: assign (no current row), or reassign/hold-resume/unassign (a
 * current row exists). Candidates are the tenant-scoped, active-only, minimized-
 * projection list app.find_assignment_candidates returns.
 */
export function ResourceAssignmentPanel({
  role,
  current,
  candidates,
  assignAction,
  reassignAction,
  holdAction,
  resumeAction,
  unassignAction,
}: {
  role: ResourceAssignmentRole;
  current: ResourceAssignment | null;
  candidates: readonly AssignmentCandidate[];
  assignAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  reassignAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  holdAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  resumeAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  unassignAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
}) {
  const [assignState, assignFormAction, assignPending] = useActionState(assignAction, INITIAL_STATE);
  const [reassignState, reassignFormAction, reassignPending] = useActionState(reassignAction, INITIAL_STATE);
  const [holdState, holdFormAction, holdPending] = useActionState(holdAction, INITIAL_STATE);
  const [resumeState, resumeFormAction, resumePending] = useActionState(resumeAction, INITIAL_STATE);
  const [unassignState, unassignFormAction, unassignPending] = useActionState(unassignAction, INITIAL_STATE);

  return (
    <div className="flex flex-col gap-2 border-b border-neutral-100 pb-3 last:border-b-0 last:pb-0">
      <div className="flex items-center gap-2">
        <span className="w-16 text-sm font-medium text-neutral-700">{ROLE_LABELS[role]}</span>
        {current ? (
          <>
            <span className="text-sm text-neutral-900">
              {current.resourceSnapshot.name} ({current.resourceSnapshot.code})
            </span>
            <StatusBadge tone={current.status === "held" ? "warning" : "success"} label={current.status} />
          </>
        ) : (
          <StatusBadge tone="neutral" label="unassigned" />
        )}
      </div>

      {!current ? (
        <form action={assignFormAction} className="flex items-end gap-2">
          <select name="resourceId" required className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" defaultValue="">
            <option value="" disabled>
              Select a {ROLE_LABELS[role].toLowerCase()}…
            </option>
            {candidates.map((candidate) => (
              <option key={candidate.id} value={candidate.id}>
                {candidate.name} ({candidate.code})
              </option>
            ))}
          </select>
          <Button type="submit" variant="secondary" loading={assignPending} loadingLabel="Assigning…" className="w-fit">
            Assign
          </Button>
          {assignState.error ? (
            <p role="alert" className="text-sm text-danger">
              {assignState.error}
            </p>
          ) : null}
        </form>
      ) : (
        <div className="flex flex-col gap-2">
          <form action={reassignFormAction} className="flex flex-wrap items-end gap-2">
            <select name="resourceId" required className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" defaultValue="">
              <option value="" disabled>
                Reassign to…
              </option>
              {candidates
                .filter((candidate) => candidate.id !== current.resourceId)
                .map((candidate) => (
                  <option key={candidate.id} value={candidate.id}>
                    {candidate.name} ({candidate.code})
                  </option>
                ))}
            </select>
            <input name="reason" type="text" required placeholder="Reason for reassignment" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
            <Button type="submit" variant="secondary" loading={reassignPending} loadingLabel="Reassigning…" className="w-fit">
              Reassign
            </Button>
          </form>
          {reassignState.error ? (
            <p role="alert" className="text-sm text-danger">
              {reassignState.error}
            </p>
          ) : null}

          {current.status === "active" ? (
            <form action={holdFormAction} className="flex flex-wrap items-end gap-2">
              <input name="reason" type="text" required placeholder="Reason for hold" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
              <Button type="submit" variant="secondary" loading={holdPending} loadingLabel="Holding…" className="w-fit">
                Hold
              </Button>
            </form>
          ) : null}
          {holdState.error ? (
            <p role="alert" className="text-sm text-danger">
              {holdState.error}
            </p>
          ) : null}

          {current.status === "held" ? (
            <form action={resumeFormAction} className="flex items-end gap-2">
              <Button type="submit" variant="secondary" loading={resumePending} loadingLabel="Resuming…" className="w-fit">
                Resume
              </Button>
            </form>
          ) : null}
          {resumeState.error ? (
            <p role="alert" className="text-sm text-danger">
              {resumeState.error}
            </p>
          ) : null}

          <form action={unassignFormAction} className="flex flex-wrap items-end gap-2">
            <input name="reason" type="text" required placeholder="Reason for unassignment" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
            <Button type="submit" variant="destructive" loading={unassignPending} loadingLabel="Unassigning…" className="w-fit">
              Unassign
            </Button>
          </form>
          {unassignState.error ? (
            <p role="alert" className="text-sm text-danger">
              {unassignState.error}
            </p>
          ) : null}
        </div>
      )}
    </div>
  );
}
