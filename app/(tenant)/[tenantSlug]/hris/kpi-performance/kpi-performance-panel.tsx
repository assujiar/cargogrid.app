"use client";

import { useActionState, useId, useState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Checkbox } from "../../../../../components/forms/checkbox.tsx";
import { Textarea } from "../../../../../components/forms/textarea.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type {
  PerformanceKpiDefinitionRow,
  PerformanceTemplateRow,
  PerformanceTemplateKpiItemRow,
  PerformanceCycleRow,
  PerformanceGoalAssignmentRow,
  PerformanceReviewerAssignmentRow,
  PerformanceMyAssessmentRow,
  PerformanceAssessmentKpiScoreRow,
  PerformanceOutcomeRow,
  PerformanceAppealRow,
  PerformanceCycleScoreDistributionRow,
} from "../../../../../server/contracts/kpi-performance/kpi-performance.ts";
import type { PerformanceAdminActionState } from "./actions.ts";

const INITIAL_STATE: PerformanceAdminActionState = { error: null };
const CYCLE_STATUS_TONE: Record<string, StatusTone> = {
  draft: "neutral", goal_setting_open: "info", self_assessment_open: "info", manager_assessment_open: "warning",
  calibration: "warning", acknowledgement: "warning", closed: "success", cancelled: "danger",
};
const OUTCOME_STATUS_TONE: Record<string, StatusTone> = {
  draft: "neutral", published: "info", acknowledged: "success", appealed: "warning", reopened: "warning", closed: "success",
};
const APPEAL_STATUS_TONE: Record<string, StatusTone> = {
  submitted: "warning", under_review: "warning", upheld: "success", overturned: "info", withdrawn: "neutral",
};

const CYCLE_STAGE_ORDER = ["draft", "goal_setting_open", "self_assessment_open", "manager_assessment_open", "calibration", "acknowledgement", "closed"] as const;

function nextStage(status: string): string | null {
  const idx = CYCLE_STAGE_ORDER.indexOf(status as (typeof CYCLE_STAGE_ORDER)[number]);
  if (idx === -1 || idx === CYCLE_STAGE_ORDER.length - 1) return null;
  return CYCLE_STAGE_ORDER[idx + 1] ?? null;
}

type BoundAction = (prevState: PerformanceAdminActionState, formData: FormData) => Promise<PerformanceAdminActionState>;

function ErrorLine({ error, id }: { error: string | null; id?: string }) {
  return error ? <ValidationMessage id={id}>{error}</ValidationMessage> : null;
}

function CreateKpiForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">Create a KPI</h3>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <FormField id={`${reactId}-code`} label="Code">
          <Input id={`${reactId}-code`} name="code" required placeholder="e.g. sales_target" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id={`${reactId}-name`} label="Name">
          <Input id={`${reactId}-name`} name="name" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      </div>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
        <FormField id={`${reactId}-unitOfMeasure`} label="Unit of measure">
          <Select id={`${reactId}-unitOfMeasure`} name="unitOfMeasure" defaultValue="percent" invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="percent">Percent</option>
            <option value="count">Count</option>
            <option value="currency">Currency</option>
            <option value="ratio">Ratio</option>
            <option value="qualitative">Qualitative</option>
          </Select>
        </FormField>
        <FormField id={`${reactId}-scoringMethod`} label="Scoring method">
          <Select id={`${reactId}-scoringMethod`} name="scoringMethod" defaultValue="target_ratio" invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="target_ratio">Target ratio (actual vs. target)</option>
            <option value="milestone_percent">Milestone percent (0-100 direct)</option>
            <option value="qualitative_scale">Qualitative (assessor-scored)</option>
          </Select>
        </FormField>
        <FormField id={`${reactId}-targetDirection`} label="Target direction">
          <Select id={`${reactId}-targetDirection`} name="targetDirection" defaultValue="higher_is_better" invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="higher_is_better">Higher is better</option>
            <option value="lower_is_better">Lower is better</option>
          </Select>
        </FormField>
      </div>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating…">Create KPI</Button>
      <ErrorLine error={state.error} id={errorId} />
    </form>
  );
}

function CreateTemplateForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">Create a cycle template</h3>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <FormField id={`${reactId}-code`} label="Code">
          <Input id={`${reactId}-code`} name="code" required placeholder="e.g. annual_std" invalid={Boolean(state.error)} aria-describedby={state.error ? errorId : undefined} />
        </FormField>
        <FormField id={`${reactId}-name`} label="Name">
          <Input id={`${reactId}-name`} name="name" required invalid={Boolean(state.error)} aria-describedby={state.error ? errorId : undefined} />
        </FormField>
      </div>
      <Checkbox name="requiresReviewerStage" label="Requires a 360 reviewer stage" />
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating…">Create template</Button>
      <ErrorLine error={state.error} id={errorId} />
    </form>
  );
}

function TemplateCard({
  template, items, kpiDefinitions, addItemAction, publishAction,
}: {
  template: PerformanceTemplateRow;
  items: PerformanceTemplateKpiItemRow[];
  kpiDefinitions: PerformanceKpiDefinitionRow[];
  addItemAction: BoundAction;
  publishAction: BoundAction;
}) {
  const [addState, addFormAction, addPending] = useActionState(addItemAction, INITIAL_STATE);
  const [pubState, pubFormAction, pubPending] = useActionState(publishAction, INITIAL_STATE);
  const weightSum = items.reduce((sum, i) => sum + Number(i.defaultWeight), 0);
  const reactId = useId();
  const addErrorId = `${reactId}-add-error`;
  const pubErrorId = `${reactId}-pub-error`;

  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>{template.code} — {template.name} (weight sum {weightSum.toFixed(2)} / {Number(template.weightTotalRequired).toFixed(2)})</span>
        <StatusBadge tone={template.status === "published" ? "success" : "neutral"} label={template.status} />
      </div>
      <ul className="flex flex-col gap-1 text-xs text-neutral-600">
        {items.map((item) => (
          <li key={item.id}>{item.kpiCode} — default weight {item.defaultWeight}{item.isRequired ? " (required)" : ""}</li>
        ))}
      </ul>
      {template.status === "draft" ? (
        <>
          <form action={addFormAction} className="flex flex-wrap items-end gap-2">
            <FormField id={`${reactId}-kpiDefinitionId`} label="KPI">
              <Select id={`${reactId}-kpiDefinitionId`} name="kpiDefinitionId" required invalid={Boolean(addState.error)} aria-describedby={addState.error ? addErrorId : undefined}>
                <option value="">Select…</option>
                {kpiDefinitions.map((k) => <option key={k.id} value={k.id}>{k.code}</option>)}
              </Select>
            </FormField>
            <FormField id={`${reactId}-defaultWeight`} label="Default weight">
              <Input type="number" id={`${reactId}-defaultWeight`} name="defaultWeight" min={0} max={100} step="0.01" required className="w-24" invalid={Boolean(addState.error)} aria-describedby={addState.error ? addErrorId : undefined} />
            </FormField>
            <Button type="submit" variant="secondary" loading={addPending} loadingLabel="Adding…">Add KPI item</Button>
          </form>
          <ErrorLine error={addState.error} id={addErrorId} />
          <form action={pubFormAction}>
            <Button type="submit" variant="primary" loading={pubPending} loadingLabel="Publishing…">Publish template</Button>
          </form>
          <ErrorLine error={pubState.error} id={pubErrorId} />
        </>
      ) : null}
    </li>
  );
}

function CreateCycleForm({ templates, action }: { templates: PerformanceTemplateRow[]; action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const published = templates.filter((t) => t.status === "published");
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">Create a performance cycle</h3>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <FormField id={`${reactId}-templateId`} label="Template">
          <Select id={`${reactId}-templateId`} name="templateId" required invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="">Select a published template…</option>
            {published.map((t) => <option key={t.id} value={t.id}>{t.code}</option>)}
          </Select>
        </FormField>
        <FormField id={`${reactId}-code`} label="Code">
          <Input id={`${reactId}-code`} name="code" required placeholder="e.g. fy2026" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      </div>
      <FormField id={`${reactId}-name`} label="Name">
        <Input id={`${reactId}-name`} name="name" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <FormField id={`${reactId}-periodStart`} label="Period start">
          <Input type="date" id={`${reactId}-periodStart`} name="periodStart" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id={`${reactId}-periodEnd`} label="Period end">
          <Input type="date" id={`${reactId}-periodEnd`} name="periodEnd" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      </div>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating…">Create cycle</Button>
      <ErrorLine error={state.error} id={errorId} />
    </form>
  );
}

function CycleRowItem({ cycle, advanceAction, cancelAction }: { cycle: PerformanceCycleRow; advanceAction: (targetStatus: string) => BoundAction; cancelAction: BoundAction }) {
  const next = nextStage(cycle.status);
  const [advanceState, advanceFormAction, advancePending] = useActionState(next ? advanceAction(next) : advanceAction(cycle.status), INITIAL_STATE);
  const [cancelState, cancelFormAction, cancelPending] = useActionState(cancelAction, INITIAL_STATE);
  const reasonId = `cycle-cancel-reason-${cycle.id}`;
  const errorId = `cycle-error-${cycle.id}`;
  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>{cycle.code} — {cycle.name} ({cycle.periodStart} to {cycle.periodEnd})</span>
        <StatusBadge tone={CYCLE_STATUS_TONE[cycle.status] ?? "neutral"} label={cycle.status.replace(/_/g, " ")} />
      </div>
      <div className="flex flex-wrap gap-2">
        {next ? (
          <form action={advanceFormAction}>
            <Button type="submit" variant="secondary" loading={advancePending} loadingLabel="Advancing…">Advance to {next.replace(/_/g, " ")}</Button>
          </form>
        ) : null}
        {cycle.status !== "closed" && cycle.status !== "cancelled" ? (
          <form action={cancelFormAction} className="flex items-center gap-1">
            <label className="sr-only" htmlFor={reasonId}>
              Cancel reason
            </label>
            <Input id={reasonId} type="text" name="reason" placeholder="cancel reason" required className="text-xs" invalid={Boolean(cancelState.error)} aria-describedby={cancelState.error ? errorId : undefined} />
            <Button type="submit" variant="destructive" loading={cancelPending} loadingLabel="Cancelling…">Cancel</Button>
          </form>
        ) : null}
      </div>
      <ErrorLine error={advanceState.error ?? cancelState.error} id={errorId} />
    </li>
  );
}

function AssignGoalForm({ kpiDefinitions, action }: { kpiDefinitions: PerformanceKpiDefinitionRow[]; action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">Assign a weighted goal</h3>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <FormField id={`${reactId}-employeeId`} label="Employee ID">
          <Input id={`${reactId}-employeeId`} name="employeeId" required placeholder="employee master_record_id" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id={`${reactId}-kpiDefinitionId`} label="KPI">
          <Select id={`${reactId}-kpiDefinitionId`} name="kpiDefinitionId" required invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="">Select…</option>
            {kpiDefinitions.map((k) => <option key={k.id} value={k.id}>{k.code}</option>)}
          </Select>
        </FormField>
      </div>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
        <FormField id={`${reactId}-weight`} label="Weight">
          <Input type="number" id={`${reactId}-weight`} name="weight" min={0.01} max={100} step="0.01" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id={`${reactId}-targetValue`} label="Target value (target_ratio KPIs)">
          <Input type="number" id={`${reactId}-targetValue`} name="targetValue" step="0.0001" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id={`${reactId}-targetUnit`} label="Target unit">
          <Input id={`${reactId}-targetUnit`} name="targetUnit" placeholder="e.g. IDR" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      </div>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Assigning…">Assign goal</Button>
      <ErrorLine error={state.error} id={errorId} />
    </form>
  );
}

function GoalAssignmentRowItem({ goal, naAction }: { goal: PerformanceGoalAssignmentRow; naAction: (goalAssignmentId: string, expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(naAction(goal.id, goal.recordVersion), INITIAL_STATE);
  const reasonId = `goal-na-reason-${goal.id}`;
  const errorId = `goal-na-error-${goal.id}`;
  return (
    <li className="flex flex-col gap-1 rounded-md border border-neutral-200 p-2 text-sm">
      <div className="flex items-center justify-between">
        <span>{goal.employeeFullName ?? goal.employeeId} — {goal.kpiCode} (weight {goal.weight})</span>
        <StatusBadge tone={goal.status === "active" ? "success" : "neutral"} label={goal.status.replace(/_/g, " ")} />
      </div>
      {goal.status === "active" ? (
        <form action={formAction} className="flex items-center gap-1">
          <label className="sr-only" htmlFor={reasonId}>
            Not-applicable reason
          </label>
          <Input id={reasonId} type="text" name="reason" placeholder="not-applicable reason" required className="text-xs" invalid={Boolean(state.error)} aria-describedby={state.error ? errorId : undefined} />
          <Button type="submit" variant="secondary" loading={pending} loadingLabel="Marking…">Mark N/A</Button>
        </form>
      ) : (
        <span className="text-xs text-neutral-500">{goal.naReason}</span>
      )}
      <ErrorLine error={state.error} id={errorId} />
    </li>
  );
}

function AssignReviewerForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <FormField id={`${reactId}-employeeId`} label="Employee ID">
        <Input id={`${reactId}-employeeId`} name="employeeId" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`${reactId}-role`} label="Role">
        <Select id={`${reactId}-role`} name="role" defaultValue="reviewer" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="manager">Manager</option>
          <option value="reviewer">Reviewer (360)</option>
        </Select>
      </FormField>
      <FormField id={`${reactId}-assignedToEmployeeId`} label="Assign to (employee ID)">
        <Input id={`${reactId}-assignedToEmployeeId`} name="assignedToEmployeeId" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Assigning…">Assign</Button>
      <ErrorLine error={state.error} id={errorId} />
    </form>
  );
}

/**
 * Batch 283-285 Tier C fix (spec-compliance lens finding 2): the "manager
 * reassignment does NOT silently transfer already-submitted reviews"
 * business rule (decision 5, a named mandatory-reading item) was real and
 * tested at the RPC layer (`app.reassign_performance_reviewer_assignment`)
 * from this checkpoint's own original commit, but had no reachable UI form
 * -- the bound action existed only as a `void`-ed, unused prop. Wired here
 * as a peer of `AssignReviewerForm` rather than merely disclosed.
 */
function ReviewerAssignmentRowItem({ assignment, reassignAction }: {
  assignment: PerformanceReviewerAssignmentRow;
  reassignAction: (assignmentId: string) => BoundAction;
}) {
  const [state, formAction, pending] = useActionState(reassignAction(assignment.id), INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <li className="flex flex-col gap-1 rounded-md border border-neutral-200 p-2 text-sm">
      <div className="flex items-center justify-between">
        <span>{assignment.employeeFullName ?? assignment.employeeId} — {assignment.role} assigned to {assignment.assignedToFullName ?? assignment.assignedToEmployeeId}</span>
        <StatusBadge tone={assignment.status === "active" ? "success" : "neutral"} label={assignment.status.replace(/_/g, " ")} />
      </div>
      {assignment.status === "active" ? (
        <details className="text-xs">
          <summary className="cursor-pointer">Reassign</summary>
          <form action={formAction} className="mt-1 flex flex-wrap items-end gap-2">
            <FormField id={`${reactId}-newAssignedToEmployeeId`} label="New assignee (employee ID)">
              <Input id={`${reactId}-newAssignedToEmployeeId`} name="newAssignedToEmployeeId" required className="text-xs" invalid={Boolean(state.error)} aria-describedby={describedBy} />
            </FormField>
            <FormField id={`${reactId}-reason`} label="Reason (required)">
              <Input id={`${reactId}-reason`} name="reason" required className="text-xs" invalid={Boolean(state.error)} aria-describedby={describedBy} />
            </FormField>
            <Button type="submit" variant="secondary" loading={pending} loadingLabel="Reassigning…">Reassign</Button>
          </form>
          <ErrorLine error={state.error} id={errorId} />
        </details>
      ) : null}
    </li>
  );
}

function ScoreGoalForm({
  assessmentId, goal, existingScore, action,
}: {
  assessmentId: string;
  goal: PerformanceGoalAssignmentRow;
  existingScore: PerformanceAssessmentKpiScoreRow | undefined;
  action: (assessmentId: string, goalAssignmentId: string) => BoundAction;
}) {
  const [state, formAction, pending] = useActionState(action(assessmentId, goal.id), INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-100 bg-neutral-50 p-2 text-xs">
      <span className="font-medium text-neutral-700">{goal.kpiCode} (weight {goal.weight}{goal.targetValue ? `, target ${goal.targetValue}` : ""})</span>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <FormField id={`${reactId}-actualValue`} label="Actual value">
          <Input type="number" id={`${reactId}-actualValue`} name="actualValue" step="0.0001" defaultValue={existingScore?.actualValue ?? ""} invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id={`${reactId}-manualScore`} label="Manual score (0-100, qualitative)">
          <Input type="number" id={`${reactId}-manualScore`} name="manualScore" min={0} max={100} step="0.001" defaultValue={existingScore?.manualScore ?? ""} invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      </div>
      <FormField id={`${reactId}-scoreRationale`} label="Score rationale (required)">
        <Textarea id={`${reactId}-scoreRationale`} name="scoreRationale" required rows={2} defaultValue={existingScore?.scoreRationale ?? ""} invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      {existingScore ? <span className="text-neutral-500">current raw score: {existingScore.rawScore}</span> : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">Save score</Button>
      <ErrorLine error={state.error} id={errorId} />
    </form>
  );
}

function MyAssessmentCard({
  assessment, goals, scores, scoreGoalAction, submitManagerAction, submitReviewerAction,
}: {
  assessment: PerformanceMyAssessmentRow;
  goals: PerformanceGoalAssignmentRow[];
  scores: PerformanceAssessmentKpiScoreRow[];
  scoreGoalAction: (assessmentId: string, goalAssignmentId: string) => BoundAction;
  submitManagerAction: (assessmentId: string, expectedVersion: number) => BoundAction;
  submitReviewerAction: (assessmentId: string, expectedVersion: number) => BoundAction;
}) {
  const [expanded, setExpanded] = useState(false);
  const submitAction = assessment.assessmentType === "manager" ? submitManagerAction : submitReviewerAction;
  const [submitState, submitFormAction, submitPending] = useActionState(submitAction(assessment.id, assessment.recordVersion), INITIAL_STATE);
  const commentId = `assessment-comment-${assessment.id}`;
  const submitErrorId = `assessment-submit-error-${assessment.id}`;
  const scoreByGoalId = new Map(scores.map((s) => [s.goalAssignmentId, s]));
  const activeGoals = goals.filter((g) => g.status === "active");

  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>{assessment.employeeFullName ?? assessment.employeeId} — {assessment.assessmentType} review, {assessment.cycleCode}</span>
        <div className="flex items-center gap-2">
          <StatusBadge tone={assessment.status === "submitted" ? "success" : "warning"} label={assessment.status.replace(/_/g, " ")} />
          <Button type="button" variant="secondary" onClick={() => setExpanded((v) => !v)}>{expanded ? "Hide" : "Score"}</Button>
        </div>
      </div>
      {expanded ? (
        <div className="flex flex-col gap-2">
          {activeGoals.length === 0 ? (
            <EmptyState title="No active goals for this employee yet" />
          ) : (
            activeGoals.map((g) => <ScoreGoalForm key={g.id} assessmentId={assessment.id} goal={g} existingScore={scoreByGoalId.get(g.id)} action={scoreGoalAction} />)
          )}
          {assessment.status !== "submitted" ? (
            <form action={submitFormAction} className="flex flex-col gap-2">
              <FormField id={commentId} label="Overall comment">
                <Textarea id={commentId} name="overallComment" rows={2} invalid={Boolean(submitState.error)} aria-describedby={submitState.error ? submitErrorId : undefined} />
              </FormField>
              <Button type="submit" variant="primary" loading={submitPending} loadingLabel="Submitting…">Submit {assessment.assessmentType} assessment</Button>
              <ErrorLine error={submitState.error} id={submitErrorId} />
            </form>
          ) : null}
        </div>
      ) : null}
    </li>
  );
}

function CalibrationRow({
  outcome, calibrateAction, publishAction,
}: {
  outcome: PerformanceOutcomeRow;
  calibrateAction: (outcomeId: string, expectedVersion: number) => BoundAction;
  publishAction: (outcomeId: string, expectedVersion: number) => BoundAction;
}) {
  const [calState, calFormAction, calPending] = useActionState(calibrateAction(outcome.id, outcome.recordVersion), INITIAL_STATE);
  const [pubState, pubFormAction, pubPending] = useActionState(publishAction(outcome.id, outcome.recordVersion), INITIAL_STATE);
  const scoreId = `calibrate-row-score-${outcome.id}`;
  const reasonId = `calibrate-row-reason-${outcome.id}`;
  const errorId = `calibrate-row-error-${outcome.id}`;
  const describedBy = calState.error || pubState.error ? errorId : undefined;
  return (
    <tr className="border-b border-neutral-100">
      <td className="p-2">{outcome.employeeFullName ?? outcome.employeeId}</td>
      <td className="p-2">{outcome.baselineScore ?? "—"}</td>
      <td className="p-2">{outcome.calibratedScore ?? "—"}</td>
      <td className="p-2 font-medium">{outcome.finalScore ?? "—"}</td>
      <td className="p-2"><StatusBadge tone={OUTCOME_STATUS_TONE[outcome.status] ?? "neutral"} label={outcome.status} /></td>
      <td className="p-2">
        {outcome.status === "draft" || outcome.status === "published" || outcome.status === "reopened" ? (
          <form action={calFormAction} className="mb-1 flex items-center gap-1">
            <label className="sr-only" htmlFor={scoreId}>
              Adjusted score
            </label>
            <Input id={scoreId} type="number" name="adjustedScore" min={0} max={100} step="0.001" placeholder="score" required className="w-20 text-xs" invalid={Boolean(calState.error)} aria-describedby={describedBy} />
            <label className="sr-only" htmlFor={reasonId}>
              Reason
            </label>
            <Input id={reasonId} type="text" name="reason" placeholder="reason" required className="w-32 text-xs" invalid={Boolean(calState.error)} aria-describedby={describedBy} />
            <Button type="submit" variant="secondary" loading={calPending} loadingLabel="…">Calibrate</Button>
          </form>
        ) : null}
        {outcome.status === "draft" || outcome.status === "reopened" ? (
          <form action={pubFormAction}>
            <Button type="submit" variant="primary" loading={pubPending} loadingLabel="…">Publish</Button>
          </form>
        ) : null}
        <ErrorLine error={calState.error ?? pubState.error} id={errorId} />
      </td>
    </tr>
  );
}

function CalibrationCard({
  outcome, calibrateAction, publishAction,
}: {
  outcome: PerformanceOutcomeRow;
  calibrateAction: (outcomeId: string, expectedVersion: number) => BoundAction;
  publishAction: (outcomeId: string, expectedVersion: number) => BoundAction;
}) {
  const [calState, calFormAction, calPending] = useActionState(calibrateAction(outcome.id, outcome.recordVersion), INITIAL_STATE);
  const [pubState, pubFormAction, pubPending] = useActionState(publishAction(outcome.id, outcome.recordVersion), INITIAL_STATE);
  const scoreId = `calibrate-card-score-${outcome.id}`;
  const reasonId = `calibrate-card-reason-${outcome.id}`;
  const calErrorId = `calibrate-card-cal-error-${outcome.id}`;
  const pubErrorId = `calibrate-card-pub-error-${outcome.id}`;
  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>{outcome.employeeFullName ?? outcome.employeeId}</span>
        <StatusBadge tone={OUTCOME_STATUS_TONE[outcome.status] ?? "neutral"} label={outcome.status} />
      </div>
      <dl className="grid grid-cols-3 gap-1 text-xs text-neutral-600">
        <div><dt>Baseline</dt><dd className="font-medium text-neutral-900">{outcome.baselineScore ?? "—"}</dd></div>
        <div><dt>Calibrated</dt><dd className="font-medium text-neutral-900">{outcome.calibratedScore ?? "—"}</dd></div>
        <div><dt>Final</dt><dd className="font-medium text-neutral-900">{outcome.finalScore ?? "—"}</dd></div>
      </dl>
      {outcome.status === "draft" || outcome.status === "published" || outcome.status === "reopened" ? (
        <form action={calFormAction} className="flex items-center gap-1">
          <label className="sr-only" htmlFor={scoreId}>
            Adjusted score
          </label>
          <Input id={scoreId} type="number" name="adjustedScore" min={0} max={100} step="0.001" placeholder="score" required className="w-20 text-xs" invalid={Boolean(calState.error)} aria-describedby={calState.error ? calErrorId : undefined} />
          <label className="sr-only" htmlFor={reasonId}>
            Reason
          </label>
          <Input id={reasonId} type="text" name="reason" placeholder="reason" required className="flex-1 text-xs" invalid={Boolean(calState.error)} aria-describedby={calState.error ? calErrorId : undefined} />
          <Button type="submit" variant="secondary" loading={calPending} loadingLabel="…">Calibrate</Button>
        </form>
      ) : null}
      <ErrorLine error={calState.error} id={calErrorId} />
      {outcome.status === "draft" || outcome.status === "reopened" ? (
        <form action={pubFormAction}>
          <Button type="submit" variant="primary" loading={pubPending} loadingLabel="…">Publish</Button>
        </form>
      ) : null}
      <ErrorLine error={pubState.error} id={pubErrorId} />
    </li>
  );
}

function AppealRowItem({ appeal, decideAction }: { appeal: PerformanceAppealRow; decideAction: (appealId: string, expectedVersion: number, decision: "uphold" | "overturn") => BoundAction }) {
  const [upholdState, upholdFormAction, upholdPending] = useActionState(decideAction(appeal.id, appeal.recordVersion, "uphold"), INITIAL_STATE);
  const [overturnState, overturnFormAction, overturnPending] = useActionState(decideAction(appeal.id, appeal.recordVersion, "overturn"), INITIAL_STATE);
  const upholdReasonId = `appeal-uphold-reason-${appeal.id}`;
  const overturnReasonId = `appeal-overturn-reason-${appeal.id}`;
  const errorId = `appeal-error-${appeal.id}`;
  const describedBy = upholdState.error || overturnState.error ? errorId : undefined;
  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>{appeal.employeeFullName ?? appeal.employeeId} — {appeal.appealReason}</span>
        <StatusBadge tone={APPEAL_STATUS_TONE[appeal.status] ?? "neutral"} label={appeal.status.replace(/_/g, " ")} />
      </div>
      {appeal.status === "submitted" || appeal.status === "under_review" ? (
        <div className="flex flex-col gap-2 sm:flex-row">
          <form action={upholdFormAction} className="flex items-center gap-1">
            <label className="sr-only" htmlFor={upholdReasonId}>
              Uphold reason
            </label>
            <Input id={upholdReasonId} type="text" name="decisionReason" placeholder="uphold reason" required className="text-xs" invalid={Boolean(upholdState.error)} aria-describedby={describedBy} />
            <Button type="submit" variant="secondary" loading={upholdPending} loadingLabel="…">Uphold</Button>
          </form>
          <form action={overturnFormAction} className="flex items-center gap-1">
            <label className="sr-only" htmlFor={overturnReasonId}>
              Overturn reason
            </label>
            <Input id={overturnReasonId} type="text" name="decisionReason" placeholder="overturn reason" required className="text-xs" invalid={Boolean(overturnState.error)} aria-describedby={describedBy} />
            <Button type="submit" variant="primary" loading={overturnPending} loadingLabel="…">Overturn (reopen)</Button>
          </form>
        </div>
      ) : appeal.decisionReason ? (
        <span className="text-xs text-neutral-500">Decision: {appeal.decisionReason}</span>
      ) : null}
      <ErrorLine error={upholdState.error ?? overturnState.error} id={errorId} />
    </li>
  );
}

export function KpiPerformanceAdminPanel({
  kpiDefinitions, templates, templateItemsByTemplateId, cycles, currentCycle, goalAssignments, reviewerAssignments,
  myManagerReviewerAssessments, scoresByAssessmentId, goalsByEmployeeId, outcomes, appeals, distribution,
  createPerformanceKpiDefinitionAction, createPerformanceTemplateAction, addPerformanceTemplateKpiItemAction, publishPerformanceTemplateAction,
  createPerformanceCycleAction, advancePerformanceCycleStageAction, cancelPerformanceCycleAction,
  assignPerformanceGoalAction, markPerformanceGoalNotApplicableAction, assignPerformanceReviewerAction, reassignPerformanceReviewerAssignmentAction,
  scorePerformanceGoalAction, submitPerformanceManagerAssessmentAction, submitPerformanceReviewerAssessmentAction,
  calibratePerformanceOutcomeScoreAction, publishPerformanceOutcomeAction, decidePerformanceAppealAction,
}: {
  kpiDefinitions: PerformanceKpiDefinitionRow[];
  templates: PerformanceTemplateRow[];
  templateItemsByTemplateId: Record<string, PerformanceTemplateKpiItemRow[]>;
  cycles: PerformanceCycleRow[];
  currentCycle: PerformanceCycleRow | null;
  goalAssignments: PerformanceGoalAssignmentRow[];
  reviewerAssignments: PerformanceReviewerAssignmentRow[];
  myManagerReviewerAssessments: PerformanceMyAssessmentRow[];
  scoresByAssessmentId: Record<string, PerformanceAssessmentKpiScoreRow[]>;
  goalsByEmployeeId: Record<string, PerformanceGoalAssignmentRow[]>;
  outcomes: PerformanceOutcomeRow[];
  appeals: PerformanceAppealRow[];
  distribution: PerformanceCycleScoreDistributionRow[];
  createPerformanceKpiDefinitionAction: BoundAction;
  createPerformanceTemplateAction: BoundAction;
  addPerformanceTemplateKpiItemAction: (templateId: string) => BoundAction;
  publishPerformanceTemplateAction: (templateId: string, expectedVersion: number) => BoundAction;
  createPerformanceCycleAction: BoundAction;
  advancePerformanceCycleStageAction: (cycleId: string, expectedVersion: number, targetStatus: string) => BoundAction;
  cancelPerformanceCycleAction: (cycleId: string, expectedVersion: number) => BoundAction;
  assignPerformanceGoalAction: (cycleId: string) => BoundAction;
  markPerformanceGoalNotApplicableAction: (goalAssignmentId: string, expectedVersion: number) => BoundAction;
  assignPerformanceReviewerAction: (cycleId: string) => BoundAction;
  reassignPerformanceReviewerAssignmentAction: (assignmentId: string) => BoundAction;
  scorePerformanceGoalAction: (assessmentId: string, goalAssignmentId: string) => BoundAction;
  submitPerformanceManagerAssessmentAction: (assessmentId: string, expectedVersion: number) => BoundAction;
  submitPerformanceReviewerAssessmentAction: (assessmentId: string, expectedVersion: number) => BoundAction;
  calibratePerformanceOutcomeScoreAction: (outcomeId: string, expectedVersion: number) => BoundAction;
  publishPerformanceOutcomeAction: (outcomeId: string, expectedVersion: number) => BoundAction;
  decidePerformanceAppealAction: (appealId: string, expectedVersion: number, decision: "uphold" | "overturn") => BoundAction;
}) {
  const [calibrationView, setCalibrationView] = useState<"table" | "cards">("table");

  return (
    <div className="flex flex-col gap-8 p-6">
      <header>
        <h1 className="text-lg font-semibold text-neutral-900">KPI and performance</h1>
        <p className="text-sm text-neutral-500">Library, cycle/template builder, team review, and calibration. Every action is enforced server-side regardless of what this page shows.</p>
      </header>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-700">KPI library</h2>
        <CreateKpiForm action={createPerformanceKpiDefinitionAction} />
        <ul className="flex flex-col gap-1 text-sm">
          {kpiDefinitions.map((k) => <li key={k.id} className="rounded-md border border-neutral-200 p-2">{k.code} — {k.name} ({k.unitOfMeasure})</li>)}
        </ul>
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-700">Templates</h2>
        <CreateTemplateForm action={createPerformanceTemplateAction} />
        {templates.length === 0 ? (
          <EmptyState title="No templates yet" />
        ) : (
          <ul className="flex flex-col gap-2">
            {templates.map((t) => (
              <TemplateCard
                key={t.id} template={t} items={templateItemsByTemplateId[t.id] ?? []} kpiDefinitions={kpiDefinitions}
                addItemAction={addPerformanceTemplateKpiItemAction(t.id)} publishAction={publishPerformanceTemplateAction(t.id, t.recordVersion)}
              />
            ))}
          </ul>
        )}
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-700">Cycles</h2>
        <CreateCycleForm templates={templates} action={createPerformanceCycleAction} />
        {cycles.length === 0 ? (
          <EmptyState title="No performance cycles yet" />
        ) : (
          <ul className="flex flex-col gap-2">
            {cycles.map((c) => <CycleRowItem key={c.id} cycle={c} advanceAction={(t) => advancePerformanceCycleStageAction(c.id, c.recordVersion, t)} cancelAction={cancelPerformanceCycleAction(c.id, c.recordVersion)} />)}
          </ul>
        )}
      </section>

      {currentCycle ? (
        <>
          <section className="flex flex-col gap-3">
            <h2 className="text-sm font-semibold text-neutral-700">Goal assignment — {currentCycle.code}</h2>
            <AssignGoalForm kpiDefinitions={kpiDefinitions} action={assignPerformanceGoalAction(currentCycle.id)} />
            <AssignReviewerForm action={assignPerformanceReviewerAction(currentCycle.id)} />
            {reviewerAssignments.length > 0 ? (
              <ul className="flex flex-col gap-1">
                {reviewerAssignments.map((a) => (
                  <ReviewerAssignmentRowItem key={a.id} assignment={a} reassignAction={reassignPerformanceReviewerAssignmentAction} />
                ))}
              </ul>
            ) : null}
            {goalAssignments.length === 0 ? (
              <EmptyState title="No goals assigned yet for this cycle" />
            ) : (
              <ul className="flex flex-col gap-1">
                {goalAssignments.map((g) => <GoalAssignmentRowItem key={g.id} goal={g} naAction={markPerformanceGoalNotApplicableAction} />)}
              </ul>
            )}
          </section>

          <section className="flex flex-col gap-3">
            <h2 className="text-sm font-semibold text-neutral-700">My team review tasks (manager / reviewer)</h2>
            {myManagerReviewerAssessments.length === 0 ? (
              <EmptyState title="No pending review assignments" description="Assessments assigned to you as a manager or 360 reviewer appear here." />
            ) : (
              <ul className="flex flex-col gap-2">
                {myManagerReviewerAssessments.map((a) => (
                  <MyAssessmentCard
                    key={a.id} assessment={a} goals={goalsByEmployeeId[a.employeeId] ?? []} scores={scoresByAssessmentId[a.id] ?? []}
                    scoreGoalAction={scorePerformanceGoalAction} submitManagerAction={submitPerformanceManagerAssessmentAction} submitReviewerAction={submitPerformanceReviewerAssessmentAction}
                  />
                ))}
              </ul>
            )}
          </section>

          <section className="flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-semibold text-neutral-700">Calibration grid — {currentCycle.code}</h2>
              <Button type="button" variant="secondary" onClick={() => setCalibrationView((v) => (v === "table" ? "cards" : "table"))}>
                {calibrationView === "table" ? "Switch to card view" : "Switch to table view"}
              </Button>
            </div>
            {outcomes.length === 0 ? (
              <EmptyState title="No computed outcomes yet" description="An outcome appears once a manager assessment is submitted." />
            ) : calibrationView === "table" ? (
              <div className="overflow-x-auto">
                <table className="w-full border-collapse text-sm">
                  <caption className="sr-only">Calibration grid for {currentCycle.code}: employee, baseline score, calibrated score, final score, status, and calibration actions.</caption>
                  <thead>
                    <tr className="border-b border-neutral-300 text-left text-xs text-neutral-500">
                      <th scope="col" className="p-2">Employee</th>
                      <th scope="col" className="p-2">Baseline</th>
                      <th scope="col" className="p-2">Calibrated</th>
                      <th scope="col" className="p-2">Final</th>
                      <th scope="col" className="p-2">Status</th>
                      <th scope="col" className="p-2">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {outcomes.map((o) => <CalibrationRow key={o.id} outcome={o} calibrateAction={calibratePerformanceOutcomeScoreAction} publishAction={publishPerformanceOutcomeAction} />)}
                  </tbody>
                </table>
              </div>
            ) : (
              <ul className="flex flex-col gap-2">
                {outcomes.map((o) => <CalibrationCard key={o.id} outcome={o} calibrateAction={calibratePerformanceOutcomeScoreAction} publishAction={publishPerformanceOutcomeAction} />)}
              </ul>
            )}
          </section>

          <section className="flex flex-col gap-3">
            <h2 className="text-sm font-semibold text-neutral-700">Appeals — {currentCycle.code}</h2>
            {appeals.length === 0 ? (
              <EmptyState title="No appeals filed for this cycle" />
            ) : (
              <ul className="flex flex-col gap-2">
                {appeals.map((a) => <AppealRowItem key={a.id} appeal={a} decideAction={decidePerformanceAppealAction} />)}
              </ul>
            )}
          </section>

          <section className="flex flex-col gap-3">
            <h2 className="text-sm font-semibold text-neutral-700">Score distribution (privacy-safe) — {currentCycle.code}</h2>
            <p className="text-xs text-neutral-500">Any department with fewer than 5 employees has its average suppressed — a genuine k-anonymity floor enforced server-side, not merely hidden here.</p>
            {distribution.length === 0 ? (
              <EmptyState title="No distribution data available" description="Either no outcomes are published yet, or you don't hold HRS:View personal data." />
            ) : (
              <ul className="flex flex-col gap-1 text-sm">
                {distribution.map((d) => (
                  <li key={d.departmentOrgUnitId ?? "none"} className="flex items-center justify-between rounded-md border border-neutral-200 p-2">
                    <span>{d.departmentName ?? "Unassigned"} ({d.employeeCount} employee{d.employeeCount === 1 ? "" : "s"})</span>
                    <span>{d.suppressed ? <StatusBadge tone="neutral" label="suppressed (small cohort)" /> : `avg ${d.avgFinalScore}`}</span>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </>
      ) : (
        <EmptyState title="No active performance cycle" description="Create and advance a cycle above to unlock goal assignment, team review, and calibration." />
      )}
    </div>
  );
}
