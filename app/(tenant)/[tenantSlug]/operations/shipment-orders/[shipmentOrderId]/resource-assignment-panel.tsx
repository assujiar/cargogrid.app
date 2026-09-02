"use client";

import { useActionState, useId } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
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
  // This panel renders once per assignment role, so every id must be role-unique.
  const panelId = useId();
  const assignErrorId = `${panelId}-assign-error`;
  const reassignErrorId = `${panelId}-reassign-error`;
  const holdErrorId = `${panelId}-hold-error`;
  const unassignErrorId = `${panelId}-unassign-error`;

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
          <FormField id={`${panelId}-assign-resource-id`} label={`Assign a ${ROLE_LABELS[role].toLowerCase()}`}>
            <Select
              id={`${panelId}-assign-resource-id`}
              name="resourceId"
              required
              defaultValue=""
              invalid={Boolean(assignState.error)}
              aria-describedby={assignState.error ? assignErrorId : undefined}
            >
              <option value="" disabled>
                Select a {ROLE_LABELS[role].toLowerCase()}…
              </option>
              {candidates.map((candidate) => (
                <option key={candidate.id} value={candidate.id}>
                  {candidate.name} ({candidate.code})
                </option>
              ))}
            </Select>
          </FormField>
          <Button type="submit" variant="secondary" loading={assignPending} loadingLabel="Assigning…" className="w-fit">
            Assign
          </Button>
          {assignState.error ? <ValidationMessage id={assignErrorId}>{assignState.error}</ValidationMessage> : null}
        </form>
      ) : (
        <div className="flex flex-col gap-2">
          <form action={reassignFormAction} className="flex flex-wrap items-end gap-2">
            <FormField id={`${panelId}-reassign-resource-id`} label="Reassign to">
              <Select
                id={`${panelId}-reassign-resource-id`}
                name="resourceId"
                required
                defaultValue=""
                invalid={Boolean(reassignState.error)}
                aria-describedby={reassignState.error ? reassignErrorId : undefined}
              >
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
              </Select>
            </FormField>
            <FormField id={`${panelId}-reassign-reason`} label="Reason for reassignment">
              <Input
                id={`${panelId}-reassign-reason`}
                name="reason"
                type="text"
                required
                placeholder="Reason for reassignment"
                invalid={Boolean(reassignState.error)}
                aria-describedby={reassignState.error ? reassignErrorId : undefined}
              />
            </FormField>
            <Button type="submit" variant="secondary" loading={reassignPending} loadingLabel="Reassigning…" className="w-fit">
              Reassign
            </Button>
          </form>
          {reassignState.error ? <ValidationMessage id={reassignErrorId}>{reassignState.error}</ValidationMessage> : null}

          {current.status === "active" ? (
            <form action={holdFormAction} className="flex flex-wrap items-end gap-2">
              <FormField id={`${panelId}-hold-reason`} label="Reason for hold">
                <Input
                  id={`${panelId}-hold-reason`}
                  name="reason"
                  type="text"
                  required
                  placeholder="Reason for hold"
                  invalid={Boolean(holdState.error)}
                  aria-describedby={holdState.error ? holdErrorId : undefined}
                />
              </FormField>
              <Button type="submit" variant="secondary" loading={holdPending} loadingLabel="Holding…" className="w-fit">
                Hold
              </Button>
            </form>
          ) : null}
          {holdState.error ? <ValidationMessage id={holdErrorId}>{holdState.error}</ValidationMessage> : null}

          {current.status === "held" ? (
            <form action={resumeFormAction} className="flex items-end gap-2">
              <Button type="submit" variant="secondary" loading={resumePending} loadingLabel="Resuming…" className="w-fit">
                Resume
              </Button>
            </form>
          ) : null}
          {resumeState.error ? <ValidationMessage id={`${panelId}-resume-error`}>{resumeState.error}</ValidationMessage> : null}

          <form action={unassignFormAction} className="flex flex-wrap items-end gap-2">
            <FormField id={`${panelId}-unassign-reason`} label="Reason for unassignment">
              <Input
                id={`${panelId}-unassign-reason`}
                name="reason"
                type="text"
                required
                placeholder="Reason for unassignment"
                invalid={Boolean(unassignState.error)}
                aria-describedby={unassignState.error ? unassignErrorId : undefined}
              />
            </FormField>
            <Button type="submit" variant="destructive" loading={unassignPending} loadingLabel="Unassigning…" className="w-fit">
              Unassign
            </Button>
          </form>
          {unassignState.error ? <ValidationMessage id={unassignErrorId}>{unassignState.error}</ValidationMessage> : null}
        </div>
      )}
    </div>
  );
}
