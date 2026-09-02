"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Textarea } from "../../../../../../components/forms/textarea.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type {
  PerformanceMyGoalAssignmentRow,
  PerformanceMyAssessmentRow,
  PerformanceAssessmentKpiScoreRow,
  PerformanceGoalProgressEntryRow,
  PerformanceMyOutcomeRow,
  PerformanceMyAppealRow,
} from "../../../../../../server/contracts/kpi-performance/kpi-performance.ts";
import type { MyPerformanceActionState } from "./actions.ts";

const INITIAL_STATE: MyPerformanceActionState = { error: null };
const OUTCOME_STATUS_TONE: Record<string, StatusTone> = {
  draft: "neutral", published: "info", acknowledged: "success", appealed: "warning", reopened: "warning", closed: "success",
};
const APPEAL_STATUS_TONE: Record<string, StatusTone> = {
  submitted: "warning", under_review: "warning", upheld: "success", overturned: "info", withdrawn: "neutral",
};

type BoundAction = (prevState: MyPerformanceActionState, formData: FormData) => Promise<MyPerformanceActionState>;

function ErrorLine({ error, id }: { error: string | null; id?: string }) {
  return error ? <ValidationMessage id={id}>{error}</ValidationMessage> : null;
}

function GoalCard({
  goal, progress, selfAssessmentId, selfScore, canScore, recordProgressAction, scoreGoalAction,
}: {
  goal: PerformanceMyGoalAssignmentRow;
  progress: PerformanceGoalProgressEntryRow[];
  selfAssessmentId: string | null;
  selfScore: PerformanceAssessmentKpiScoreRow | undefined;
  canScore: boolean;
  recordProgressAction: (goalAssignmentId: string) => BoundAction;
  scoreGoalAction: (assessmentId: string, goalAssignmentId: string) => BoundAction;
}) {
  const [progressState, progressFormAction, progressPending] = useActionState(recordProgressAction(goal.id), INITIAL_STATE);
  const [scoreState, scoreFormAction, scorePending] = useActionState(
    selfAssessmentId ? scoreGoalAction(selfAssessmentId, goal.id) : async (s: MyPerformanceActionState) => s,
    INITIAL_STATE,
  );

  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>{goal.kpiCode} — weight {goal.weight}{goal.targetValue ? `, target ${goal.targetValue} ${goal.targetUnit ?? ""}` : ""}</span>
        <StatusBadge tone={goal.status === "active" ? "success" : "neutral"} label={goal.status.replace(/_/g, " ")} />
      </div>
      {goal.status === "not_applicable" ? <span className="text-xs text-neutral-500">Not applicable: {goal.naReason}</span> : null}

      {goal.status === "active" ? (
        <>
          <details className="text-xs text-neutral-600">
            <summary className="cursor-pointer">Progress log ({progress.length})</summary>
            <ul className="mt-1 flex flex-col gap-1">
              {progress.map((p) => <li key={p.id}>{p.recordedAt}: {p.actualValue ?? "—"} {p.note ? `— ${p.note}` : ""}</li>)}
            </ul>
          </details>
          <form action={progressFormAction} className="flex flex-wrap items-end gap-2" noValidate>
            <FormField id={`progress-actual-${goal.id}`} label="Actual value">
              <Input id={`progress-actual-${goal.id}`} type="number" name="actualValue" step="0.0001" className="w-28" invalid={Boolean(progressState.error)} aria-describedby={progressState.error ? `progress-${goal.id}-error` : undefined} />
            </FormField>
            <FormField id={`progress-note-${goal.id}`} label="Note">
              <Input id={`progress-note-${goal.id}`} type="text" name="note" invalid={Boolean(progressState.error)} aria-describedby={progressState.error ? `progress-${goal.id}-error` : undefined} />
            </FormField>
            <Button type="submit" variant="secondary" loading={progressPending} loadingLabel="Saving…">Log progress</Button>
          </form>
          <ErrorLine error={progressState.error} id={`progress-${goal.id}-error`} />

          {canScore && selfAssessmentId ? (
            <form action={scoreFormAction} className="flex flex-col gap-2 rounded-md border border-neutral-100 bg-neutral-50 p-2" noValidate>
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                <FormField id={`score-actual-${goal.id}`} label="Actual value (self)">
                  <Input id={`score-actual-${goal.id}`} type="number" name="actualValue" step="0.0001" defaultValue={selfScore?.actualValue ?? ""} invalid={Boolean(scoreState.error)} aria-describedby={scoreState.error ? `score-${goal.id}-error` : undefined} />
                </FormField>
                <FormField id={`score-manual-${goal.id}`} label="Manual score (0-100)">
                  <Input id={`score-manual-${goal.id}`} type="number" name="manualScore" min={0} max={100} step="0.001" defaultValue={selfScore?.manualScore ?? ""} invalid={Boolean(scoreState.error)} aria-describedby={scoreState.error ? `score-${goal.id}-error` : undefined} />
                </FormField>
              </div>
              <FormField id={`score-rationale-${goal.id}`} label="Self-rationale (required)">
                <Textarea id={`score-rationale-${goal.id}`} name="scoreRationale" required rows={2} defaultValue={selfScore?.scoreRationale ?? ""} invalid={Boolean(scoreState.error)} aria-describedby={scoreState.error ? `score-${goal.id}-error` : undefined} />
              </FormField>
              <Button type="submit" variant="primary" loading={scorePending} loadingLabel="Saving…">Save self score</Button>
              <ErrorLine error={scoreState.error} id={`score-${goal.id}-error`} />
            </form>
          ) : null}
        </>
      ) : null}
    </li>
  );
}

function SubmitSelfAssessmentForm({ assessment, action }: { assessment: PerformanceMyAssessmentRow; action: (cycleId: string, expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(action(assessment.cycleId, assessment.recordVersion), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <h3 className="text-sm font-semibold text-neutral-900">Submit self assessment — {assessment.cycleCode}</h3>
      <p className="text-xs text-neutral-500">Every active goal must be scored first, and your active goal weights must sum to exactly the cycle&rsquo;s required total.</p>
      <FormField id="self-assessment-comment" label="Overall comment">
        <Textarea id="self-assessment-comment" name="overallComment" rows={3} invalid={Boolean(state.error)} aria-describedby={state.error ? "self-assessment-error" : undefined} />
      </FormField>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Submitting…">Submit self assessment</Button>
      <ErrorLine error={state.error} id="self-assessment-error" />
    </form>
  );
}

function OutcomeCard({
  outcome, acknowledgeAction, submitAppealAction,
}: {
  outcome: PerformanceMyOutcomeRow;
  acknowledgeAction: (outcomeId: string, expectedVersion: number, agreement: "agree" | "disagree") => BoundAction;
  submitAppealAction: (outcomeId: string) => BoundAction;
}) {
  const [expanded, setExpanded] = useState(false);
  const [agreeState, agreeFormAction, agreePending] = useActionState(acknowledgeAction(outcome.id, outcome.recordVersion, "agree"), INITIAL_STATE);
  const [disagreeState, disagreeFormAction, disagreePending] = useActionState(acknowledgeAction(outcome.id, outcome.recordVersion, "disagree"), INITIAL_STATE);
  const [appealState, appealFormAction, appealPending] = useActionState(submitAppealAction(outcome.id), INITIAL_STATE);

  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>{outcome.cycleCode} — final score {outcome.finalScore ?? "—"}</span>
        <div className="flex items-center gap-2">
          <StatusBadge tone={OUTCOME_STATUS_TONE[outcome.status] ?? "neutral"} label={outcome.status} />
          <Button type="button" variant="secondary" onClick={() => setExpanded((v) => !v)}>{expanded ? "Hide detail" : "Show detail"}</Button>
        </div>
      </div>
      {expanded ? (
        <div className="flex flex-col gap-1 text-xs text-neutral-600">
          <div>Baseline: {outcome.baselineScore ?? "—"} · Calibrated: {outcome.calibratedScore ?? "—"}</div>
          <ul className="mt-1 flex flex-col gap-1 border-t border-neutral-100 pt-2">
            {outcome.scoreBreakdown.map((b, idx) => (
              <li key={idx}>weight {b.weight} × raw score {b.rawScore} = {b.weightedContribution}</li>
            ))}
          </ul>
        </div>
      ) : null}

      {outcome.status === "published" ? (
        <div className="flex flex-col gap-2 sm:flex-row">
          <form action={agreeFormAction} className="flex items-center gap-1">
            <label htmlFor={`agree-comment-${outcome.id}`} className="sr-only">
              Comment
            </label>
            <Input id={`agree-comment-${outcome.id}`} type="text" name="comment" placeholder="optional comment" className="text-xs" invalid={Boolean(agreeState.error)} aria-describedby={agreeState.error ? `ack-${outcome.id}-error` : undefined} />
            <Button type="submit" variant="primary" loading={agreePending} loadingLabel="…">Acknowledge — agree</Button>
          </form>
          <form action={disagreeFormAction} className="flex items-center gap-1">
            <label htmlFor={`disagree-comment-${outcome.id}`} className="sr-only">
              Comment
            </label>
            <Input id={`disagree-comment-${outcome.id}`} type="text" name="comment" placeholder="optional comment" className="text-xs" invalid={Boolean(disagreeState.error)} aria-describedby={disagreeState.error ? `ack-${outcome.id}-error` : undefined} />
            <Button type="submit" variant="secondary" loading={disagreePending} loadingLabel="…">Acknowledge — disagree</Button>
          </form>
        </div>
      ) : null}
      <ErrorLine error={agreeState.error ?? disagreeState.error} id={`ack-${outcome.id}-error`} />

      {outcome.status === "published" || outcome.status === "acknowledged" ? (
        <form action={appealFormAction} className="flex items-center gap-1">
          <label htmlFor={`appeal-reason-${outcome.id}`} className="sr-only">
            Appeal reason
          </label>
          <Input id={`appeal-reason-${outcome.id}`} type="text" name="appealReason" placeholder="appeal reason" required className="flex-1 text-xs" invalid={Boolean(appealState.error)} aria-describedby={appealState.error ? `appeal-${outcome.id}-error` : undefined} />
          <Button type="submit" variant="destructive" loading={appealPending} loadingLabel="…">File an appeal</Button>
        </form>
      ) : null}
      <ErrorLine error={appealState.error} id={`appeal-${outcome.id}-error`} />
    </li>
  );
}

export function MyKpiPerformancePanel({
  goals, selfAssessment, selfScores, progressByGoalId, outcomes, appeals,
  recordProgressAction, scoreGoalAction, submitSelfAssessmentAction, acknowledgeOutcomeAction, submitAppealAction,
}: {
  goals: PerformanceMyGoalAssignmentRow[];
  selfAssessment: PerformanceMyAssessmentRow | null;
  selfScores: PerformanceAssessmentKpiScoreRow[];
  progressByGoalId: Record<string, PerformanceGoalProgressEntryRow[]>;
  outcomes: PerformanceMyOutcomeRow[];
  appeals: PerformanceMyAppealRow[];
  recordProgressAction: (goalAssignmentId: string) => BoundAction;
  scoreGoalAction: (assessmentId: string, goalAssignmentId: string) => BoundAction;
  submitSelfAssessmentAction: (cycleId: string, expectedVersion: number) => BoundAction;
  acknowledgeOutcomeAction: (outcomeId: string, expectedVersion: number, agreement: "agree" | "disagree") => BoundAction;
  submitAppealAction: (outcomeId: string) => BoundAction;
}) {
  const scoreByGoalId = new Map(selfScores.map((s) => [s.goalAssignmentId, s]));
  const canScore = selfAssessment !== null && selfAssessment.status !== "submitted";

  return (
    <div className="flex flex-col gap-8 p-6">
      <header>
        <h1 className="text-lg font-semibold text-neutral-900">My KPI and performance</h1>
        <p className="text-sm text-neutral-500">Your own goals, self-review, and outcomes — private to you and your manager.</p>
      </header>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-700">My goals{selfAssessment ? ` — ${selfAssessment.cycleCode}` : ""}</h2>
        {goals.length === 0 ? (
          <EmptyState title="No goals assigned yet" description="Your manager or HR assigns weighted goals for the current cycle." />
        ) : (
          <ul className="flex flex-col gap-2">
            {goals.map((g) => (
              <GoalCard
                key={g.id} goal={g} progress={progressByGoalId[g.id] ?? []} selfAssessmentId={selfAssessment?.id ?? null} selfScore={scoreByGoalId.get(g.id)}
                canScore={canScore} recordProgressAction={recordProgressAction} scoreGoalAction={scoreGoalAction}
              />
            ))}
          </ul>
        )}
        {selfAssessment && selfAssessment.status !== "submitted" ? <SubmitSelfAssessmentForm assessment={selfAssessment} action={submitSelfAssessmentAction} /> : null}
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-700">My outcomes</h2>
        {outcomes.length === 0 ? (
          <EmptyState title="No published outcomes yet" description="An outcome appears here once HR publishes it for a cycle." />
        ) : (
          <ul className="flex flex-col gap-2">
            {outcomes.map((o) => <OutcomeCard key={o.id} outcome={o} acknowledgeAction={acknowledgeOutcomeAction} submitAppealAction={submitAppealAction} />)}
          </ul>
        )}
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-700">My appeals</h2>
        {appeals.length === 0 ? (
          <EmptyState title="No appeals filed" />
        ) : (
          <ul className="flex flex-col gap-2">
            {appeals.map((a) => (
              <li key={a.id} className="flex items-center justify-between rounded-md border border-neutral-200 p-3 text-sm">
                <span>{a.appealReason}{a.decisionReason ? ` — decision: ${a.decisionReason}` : ""}</span>
                <StatusBadge tone={APPEAL_STATUS_TONE[a.status] ?? "neutral"} label={a.status.replace(/_/g, " ")} />
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
