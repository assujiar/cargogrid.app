"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../../components/ui/empty-state.tsx";
import type { PositionWizardActionState } from "./actions.ts";
import type { EmployeeProfile } from "../../../../../../../server/contracts/employee/employee.ts";
import { ASSIGNMENT_TYPES, CHANGE_REASONS, type EmployeePositionAssignment, type AssignmentStatus, type PositionListRow, type PositionGrade } from "../../../../../../../server/contracts/position/position.ts";

const INITIAL_STATE: PositionWizardActionState = { error: null, preview: null };

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

  if (!open) {
    return (
      <Button type="button" variant={variant} onClick={() => setOpen(true)} className="text-xs">
        {label}
      </Button>
    );
  }

  return (
    <form action={formAction} className="flex flex-col gap-1 rounded-md border border-neutral-200 p-2">
      <label className="text-xs font-medium text-neutral-600">
        Reason
        <input name="reason" type="text" required className="mt-1 block w-full rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      </label>
      <Button type="submit" variant={variant} loading={pending} loadingLabel="Working…" className="text-xs">
        Confirm {label.toLowerCase()}
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
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
  const [selectedPositionId, setSelectedPositionId] = useState("");
  const [selectedManagerId, setSelectedManagerId] = useState("");
  const [selectedStartDate, setSelectedStartDate] = useState("");

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

      <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
        <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
          Position
          <select
            name="positionId"
            form="assignment-wizard-form"
            required
            value={selectedPositionId}
            onChange={(event) => setSelectedPositionId(event.currentTarget.value)}
            className="rounded-md border border-neutral-300 px-2 py-1 text-sm"
          >
            <option value="" disabled>
              Select…
            </option>
            {positions.map((p) => (
              <option key={p.id} value={p.id}>
                {p.code} — {p.title} ({p.currentHeadcount}/{p.capacity})
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
          Grade (optional, defaults to the position&apos;s own grade)
          <select name="gradeId" form="assignment-wizard-form" defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1 text-sm">
            <option value="">Use position default</option>
            {grades.map((g) => (
              <option key={g.id} value={g.id}>
                {g.code} — {g.name}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
          Manager (employee id, optional)
          <input
            name="managerEmployeeId"
            form="assignment-wizard-form"
            type="text"
            value={selectedManagerId}
            onChange={(event) => setSelectedManagerId(event.currentTarget.value)}
            placeholder="uuid, leave blank for none"
            className="rounded-md border border-neutral-300 px-2 py-1 text-sm"
          />
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
          Assignment type
          <select name="assignmentType" form="assignment-wizard-form" defaultValue="primary" className="rounded-md border border-neutral-300 px-2 py-1 text-sm">
            {ASSIGNMENT_TYPES.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
          Allocation % (optional, default 100)
          <input name="allocationPct" form="assignment-wizard-form" type="number" min="1" max="100" placeholder="100" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
          Effective start date
          <input
            name="effectiveStartDate"
            form="assignment-wizard-form"
            type="date"
            required
            value={selectedStartDate}
            onChange={(event) => setSelectedStartDate(event.currentTarget.value)}
            className="rounded-md border border-neutral-300 px-2 py-1 text-sm"
          />
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
          Effective end date (optional, open-ended if blank)
          <input name="effectiveEndDate" form="assignment-wizard-form" type="date" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
          Change reason
          <select name="changeReason" form="assignment-wizard-form" defaultValue="transfer" className="rounded-md border border-neutral-300 px-2 py-1 text-sm">
            {CHANGE_REASONS.map((r) => (
              <option key={r} value={r}>
                {r.replace(/_/g, " ")}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600 sm:col-span-3">
          Reason note (optional)
          <input name="reasonNote" form="assignment-wizard-form" type="text" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
        </label>
      </div>

      <div className="flex flex-wrap gap-2">
        <form action={previewFormAction}>
          <input type="hidden" name="positionId" value={selectedPositionId} />
          <input type="hidden" name="managerEmployeeId" value={selectedManagerId} />
          <input type="hidden" name="effectiveStartDate" value={selectedStartDate} />
          <Button type="submit" variant="secondary" loading={previewPending} loadingLabel="Computing…" disabled={!selectedPositionId}>
            Preview impact
          </Button>
        </form>
        <form id="assignment-wizard-form" action={proposeFormAction}>
          <Button type="submit" loading={proposePending} loadingLabel="Proposing…">
            Propose assignment
          </Button>
        </form>
      </div>

      {previewState.error ? (
        <p role="alert" className="text-sm text-danger">
          {previewState.error}
        </p>
      ) : null}
      {previewState.preview ? <ImpactPreviewCard preview={previewState.preview} /> : null}
      {proposeState.error ? (
        <p role="alert" className="text-sm text-danger">
          {proposeState.error}
        </p>
      ) : null}
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
