"use client";

import { useActionState, useEffect, useId, useRef, useState } from "react";
import { Button } from "../../../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../../components/ui/empty-state.tsx";
import { Input } from "../../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../../components/forms/validation-message.tsx";
import type { PositionWizardActionState } from "./actions.ts";
import type { EmployeeProfile } from "../../../../../../../server/contracts/employee/employee.ts";
import { ASSIGNMENT_TYPES, CHANGE_REASONS, type EmployeePositionAssignment, type AssignmentStatus, type PositionListRow, type PositionGrade } from "../../../../../../../server/contracts/position/position.ts";

const INITIAL_STATE: PositionWizardActionState = { error: null, preview: null };

/** Unsaved-change protection (review-round fix, section 15): the exact real
 * `beforeunload` pattern app/(tenant)/[tenantSlug]/hris/employees/[masterRecordId]/
 * employee-detail-panel.tsx's `EmployeeEditForm` and
 * app/(tenant)/[tenantSlug]/hris/positions/[positionId]/position-detail-panel.tsx's
 * edit form already established -- a browser-native "leave site?" prompt while any
 * wizard field has diverged from its blank baseline, cleared once a proposal is
 * submitted without error. */
function useUnsavedChangeGuard<T>(values: T, pending: boolean, error: string | null, initial: T) {
  const [savedValues, setSavedValues] = useState(initial);
  const dirty = JSON.stringify(values) !== JSON.stringify(savedValues);
  const valuesRef = useRef(values);
  const wasPendingRef = useRef(false);

  useEffect(() => {
    valuesRef.current = values;
  }, [values]);

  useEffect(() => {
    if (!dirty) return;
    const handler = (event: BeforeUnloadEvent) => {
      event.preventDefault();
    };
    window.addEventListener("beforeunload", handler);
    return () => window.removeEventListener("beforeunload", handler);
  }, [dirty]);

  useEffect(() => {
    if (wasPendingRef.current && !pending && error === null) {
      setSavedValues(valuesRef.current);
    }
    wasPendingRef.current = pending;
  }, [pending, error]);

  return dirty;
}

const STATUS_TONE: Record<AssignmentStatus, StatusTone> = {
  pending_approval: "warning",
  active: "success",
  rejected: "danger",
  cancelled: "neutral",
};

type WizardAction = (prevState: PositionWizardActionState, formData: FormData) => Promise<PositionWizardActionState>;

export function EmployeePositionPanel({
  tenantSlug,
  profile,
  history,
  positions,
  grades,
  previewAction,
  proposeAction,
  decideAction,
  cancelAction,
}: {
  tenantSlug: string;
  profile: EmployeeProfile;
  history: readonly EmployeePositionAssignment[];
  positions: readonly PositionListRow[];
  grades: readonly PositionGrade[];
  previewAction: WizardAction;
  proposeAction: WizardAction;
  decideAction: (assignmentId: string, expectedVersion: number, decision: "approve" | "reject") => WizardAction;
  cancelAction: (assignmentId: string, expectedVersion: number) => WizardAction;
}) {
  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">
            Position &amp; assignment timeline <span className="text-sm font-normal text-neutral-500">— {profile.fullName}</span>
          </h1>
          <p className="text-xs text-neutral-500">Effective-dated position/grade/manager history. This table is the source of truth; the employee&apos;s own record carries a synced convenience pointer only.</p>
        </div>
        <a href={`/${tenantSlug}/hris/employees/${profile.masterRecordId}`} className="text-sm text-primary underline">
          Back to employee
        </a>
      </div>

      <AssignmentTimeline history={history} decideAction={decideAction} cancelAction={cancelAction} />
      <AssignmentWizard tenantSlug={tenantSlug} positions={positions} grades={grades} previewAction={previewAction} proposeAction={proposeAction} />
    </div>
  );
}

function AssignmentTimeline({
  history,
  decideAction,
  cancelAction,
}: {
  history: readonly EmployeePositionAssignment[];
  decideAction: (assignmentId: string, expectedVersion: number, decision: "approve" | "reject") => WizardAction;
  cancelAction: (assignmentId: string, expectedVersion: number) => WizardAction;
}) {
  if (history.length === 0) {
    return <EmptyState title="No position assignment yet" description="Propose this employee's first governed position/grade/manager assignment below." />;
  }

  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Assignment history</h2>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-xs text-neutral-500">
              <th className="pb-1">Type</th>
              <th className="pb-1">Change</th>
              <th className="pb-1">Effective from</th>
              <th className="pb-1">Effective to</th>
              <th className="pb-1">Status</th>
              <th className="pb-1">Action</th>
            </tr>
          </thead>
          <tbody>
            {history.map((assignment) => (
              <AssignmentRow key={assignment.id} assignment={assignment} decideAction={decideAction} cancelAction={cancelAction} />
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

function AssignmentRow({
  assignment,
  decideAction,
  cancelAction,
}: {
  assignment: EmployeePositionAssignment;
  decideAction: (assignmentId: string, expectedVersion: number, decision: "approve" | "reject") => WizardAction;
  cancelAction: (assignmentId: string, expectedVersion: number) => WizardAction;
}) {
  const isEffective = assignment.status === "active" && assignment.effectiveStartDate <= new Date().toISOString().slice(0, 10);
  const canCancel = assignment.status === "pending_approval" || (assignment.status === "active" && !isEffective);

  return (
    <tr className="border-t border-neutral-100 align-top">
      <td className="py-1 text-xs">{assignment.assignmentType}</td>
      <td className="py-1 text-xs">{assignment.changeReason.replace(/_/g, " ")}</td>
      <td className="py-1 text-xs">{assignment.effectiveStartDate}</td>
      <td className="py-1 text-xs">{assignment.effectiveEndDate ?? "open-ended"}</td>
      <td className="py-1">
        <StatusBadge tone={STATUS_TONE[assignment.status]} label={assignment.status.replace(/_/g, " ")} />
      </td>
      <td className="py-1">
        {assignment.status === "pending_approval" ? (
          <div className="flex flex-col gap-1">
            <DecisionForm action={decideAction(assignment.id, assignment.recordVersion, "approve")} label="Approve" variant="primary" />
            <DecisionForm action={decideAction(assignment.id, assignment.recordVersion, "reject")} label="Reject" variant="destructive" />
          </div>
        ) : null}
        {canCancel ? <DecisionForm action={cancelAction(assignment.id, assignment.recordVersion)} label="Cancel" variant="secondary" /> : null}
      </td>
    </tr>
  );
}

function DecisionForm({ action, label, variant }: { action: WizardAction; label: string; variant: "primary" | "secondary" | "destructive" }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const [open, setOpen] = useState(false);
  const reactId = useId();
  const errorId = `${reactId}-error`;

  if (!open) {
    return (
      <Button type="button" variant={variant} onClick={() => setOpen(true)} className="text-xs">
        {label}
      </Button>
    );
  }

  return (
    <form action={formAction} className="flex flex-col gap-1 rounded-md border border-neutral-200 p-2">
      <FormField id={reactId} label="Reason">
        <Input id={reactId} name="reason" type="text" required className="text-xs" invalid={Boolean(state.error)} aria-describedby={state.error ? errorId : undefined} />
      </FormField>
      <Button type="submit" variant={variant} loading={pending} loadingLabel="Working…" className="text-xs">
        Confirm {label.toLowerCase()}
      </Button>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function AssignmentWizard({
  tenantSlug,
  positions,
  grades,
  previewAction,
  proposeAction,
}: {
  tenantSlug: string;
  positions: readonly PositionListRow[];
  grades: readonly PositionGrade[];
  previewAction: WizardAction;
  proposeAction: WizardAction;
}) {
  const [previewState, previewFormAction, previewPending] = useActionState(previewAction, INITIAL_STATE);
  const [proposeState, proposeFormAction, proposePending] = useActionState(proposeAction, INITIAL_STATE);

  const initialWizardValues = {
    positionId: "",
    gradeId: "",
    managerEmployeeId: "",
    assignmentType: "primary",
    allocationPct: "",
    effectiveStartDate: "",
    effectiveEndDate: "",
    changeReason: "transfer",
    reasonNote: "",
  };
  const [wizardValues, setWizardValues] = useState(initialWizardValues);
  const wizardDirty = useUnsavedChangeGuard(wizardValues, proposePending, proposeState.error, initialWizardValues);
  function wizardField<K extends keyof typeof wizardValues>(key: K) {
    return {
      value: wizardValues[key],
      onChange: (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => setWizardValues((v) => ({ ...v, [key]: e.target.value })),
    };
  }

  const proposeErrorId = "propose-error";
  const previewErrorId = "preview-error";
  const proposeDescribedBy = proposeState.error ? proposeErrorId : undefined;

  if (positions.length === 0) {
    return (
      <EmptyState
        title="No active positions in the catalogue yet"
        description="Create a position in the position/grade catalogue before proposing an assignment."
        primaryAction={
          <a href={`/${tenantSlug}/hris/positions`} className="text-sm text-primary underline">
            Go to position catalogue
          </a>
        }
      />
    );
  }

  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Transfer, promote, or reorganize</h2>
      <p className="text-xs text-neutral-500">Preview the impact before proposing. Proposing creates a status=pending approval record; a separate HRS:Approve-holding reviewer must decide it (section 21).</p>

      {wizardDirty ? <p className="text-xs text-warning">You have unsaved changes.</p> : null}

      <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
        <FormField id="positionId" label="Position">
          <Select
            id="positionId"
            name="positionId"
            form="assignment-wizard-form"
            required
            invalid={Boolean(proposeState.error)}
            aria-describedby={proposeDescribedBy}
            {...wizardField("positionId")}
          >
            <option value="" disabled>
              Select…
            </option>
            {positions.map((p) => (
              <option key={p.id} value={p.id}>
                {p.code} — {p.title} ({p.currentHeadcount}/{p.capacity})
              </option>
            ))}
          </Select>
        </FormField>
        <FormField id="gradeId" label="Grade (optional, defaults to the position's own grade)">
          <Select id="gradeId" name="gradeId" form="assignment-wizard-form" invalid={Boolean(proposeState.error)} aria-describedby={proposeDescribedBy} {...wizardField("gradeId")}>
            <option value="">Use position default</option>
            {grades.map((g) => (
              <option key={g.id} value={g.id}>
                {g.code} — {g.name}
              </option>
            ))}
          </Select>
        </FormField>
        <FormField id="managerEmployeeId" label="Manager (employee id, optional)">
          <Input
            id="managerEmployeeId"
            name="managerEmployeeId"
            form="assignment-wizard-form"
            type="text"
            placeholder="uuid, leave blank for none"
            invalid={Boolean(proposeState.error)}
            aria-describedby={proposeDescribedBy}
            {...wizardField("managerEmployeeId")}
          />
        </FormField>
        <FormField id="assignmentType" label="Assignment type">
          <Select id="assignmentType" name="assignmentType" form="assignment-wizard-form" invalid={Boolean(proposeState.error)} aria-describedby={proposeDescribedBy} {...wizardField("assignmentType")}>
            {ASSIGNMENT_TYPES.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </Select>
        </FormField>
        <FormField id="allocationPct" label="Allocation % (optional, default 100)">
          <Input
            id="allocationPct"
            name="allocationPct"
            form="assignment-wizard-form"
            type="number"
            min="1"
            max="100"
            placeholder="100"
            invalid={Boolean(proposeState.error)}
            aria-describedby={proposeDescribedBy}
            {...wizardField("allocationPct")}
          />
        </FormField>
        <FormField id="effectiveStartDate" label="Effective start date">
          <Input
            id="effectiveStartDate"
            name="effectiveStartDate"
            form="assignment-wizard-form"
            type="date"
            required
            invalid={Boolean(proposeState.error)}
            aria-describedby={proposeDescribedBy}
            {...wizardField("effectiveStartDate")}
          />
        </FormField>
        <FormField id="effectiveEndDate" label="Effective end date (optional, open-ended if blank)">
          <Input
            id="effectiveEndDate"
            name="effectiveEndDate"
            form="assignment-wizard-form"
            type="date"
            invalid={Boolean(proposeState.error)}
            aria-describedby={proposeDescribedBy}
            {...wizardField("effectiveEndDate")}
          />
        </FormField>
        <FormField id="changeReason" label="Change reason">
          <Select id="changeReason" name="changeReason" form="assignment-wizard-form" invalid={Boolean(proposeState.error)} aria-describedby={proposeDescribedBy} {...wizardField("changeReason")}>
            {CHANGE_REASONS.map((r) => (
              <option key={r} value={r}>
                {r.replace(/_/g, " ")}
              </option>
            ))}
          </Select>
        </FormField>
        <div className="sm:col-span-3">
          <FormField id="reasonNote" label="Reason note (optional)">
            <Input
              id="reasonNote"
              name="reasonNote"
              form="assignment-wizard-form"
              type="text"
              invalid={Boolean(proposeState.error)}
              aria-describedby={proposeDescribedBy}
              {...wizardField("reasonNote")}
            />
          </FormField>
        </div>
      </div>

      <div className="flex flex-wrap gap-2">
        <form action={previewFormAction}>
          <input type="hidden" name="positionId" value={wizardValues.positionId} />
          <input type="hidden" name="managerEmployeeId" value={wizardValues.managerEmployeeId} />
          <input type="hidden" name="effectiveStartDate" value={wizardValues.effectiveStartDate} />
          <Button type="submit" variant="secondary" loading={previewPending} loadingLabel="Computing…" disabled={!wizardValues.positionId}>
            Preview impact
          </Button>
        </form>
        <form id="assignment-wizard-form" action={proposeFormAction}>
          <Button type="submit" loading={proposePending} loadingLabel="Proposing…">
            Propose assignment
          </Button>
        </form>
      </div>

      {previewState.error ? <ValidationMessage id={previewErrorId}>{previewState.error}</ValidationMessage> : null}
      {previewState.preview ? <ImpactPreviewCard preview={previewState.preview} /> : null}
      {proposeState.error ? <ValidationMessage id={proposeErrorId}>{proposeState.error}</ValidationMessage> : null}
    </section>
  );
}

function ImpactPreviewCard({ preview }: { preview: NonNullable<PositionWizardActionState["preview"]> }) {
  return (
    <div role="status" className="flex flex-col gap-2 rounded-md border border-info/30 bg-info/5 p-3 text-sm">
      <p className="font-medium text-neutral-900">Impact preview</p>
      <dl className="grid grid-cols-1 gap-1 sm:grid-cols-2">
        <div>
          <dt className="text-xs text-neutral-500">Proposed position</dt>
          <dd>{preview.proposedPositionTitle}</dd>
        </div>
        <div>
          <dt className="text-xs text-neutral-500">Capacity</dt>
          <dd>
            {preview.positionCurrentHeadcount} / {preview.positionCapacity} used ({preview.positionCapacityRemaining} remaining)
          </dd>
        </div>
        <div>
          <dt className="text-xs text-neutral-500">Target org unit active</dt>
          <dd>{preview.targetOrgUnitActive ? "Yes" : "No — assignment will be rejected"}</dd>
        </div>
        <div>
          <dt className="text-xs text-neutral-500">Would create a cyclic reporting line</dt>
          <dd className={preview.wouldCreateManagerCycle ? "text-danger" : ""}>{preview.wouldCreateManagerCycle ? "Yes — assignment will be rejected" : "No"}</dd>
        </div>
        <div>
          <dt className="text-xs text-neutral-500">This employee&apos;s own direct reports</dt>
          <dd>{preview.directReportCount} (reporting lines unaffected by this change)</dd>
        </div>
        <div>
          <dt className="text-xs text-neutral-500">Open HR items on this profile</dt>
          <dd>
            {preview.pendingChangeRequestCount} change request(s), {preview.pendingDuplicateCandidateCount} duplicate candidate(s)
          </dd>
        </div>
      </dl>
      <p className="text-xs text-neutral-500">{preview.downstreamDisclosure}</p>
    </div>
  );
}
