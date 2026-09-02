"use client";

import { useActionState, useId } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { Textarea } from "../../../../../../components/forms/textarea.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type { AssessmentActionState } from "../actions.ts";
import type {
  VendorAssessment,
  VendorAssessmentTemplate,
  VendorAssessmentTemplateCriterion,
  VendorAssessmentScoreBreakdownRow,
  VendorAssessmentFinding,
  VendorAssessmentCorrectiveAction,
  VendorAssessmentStatus,
} from "../../../../../../server/contracts/vendor-assessment/vendor-assessment.ts";

const INITIAL_STATE: AssessmentActionState = { error: null };

const STATUS_TONE: Record<VendorAssessmentStatus, StatusTone> = {
  draft: "neutral",
  in_progress: "info",
  submitted: "info",
  under_review: "info",
  approved: "success",
  rejected: "danger",
  closed: "neutral",
};

type BoundFormAction = (prevState: AssessmentActionState, formData: FormData) => Promise<AssessmentActionState>;

function ActionForm({
  action,
  children,
  submitLabel,
  loadingLabel,
  variant = "primary",
  confirmMessage,
}: {
  action: BoundFormAction;
  children?: (describedBy: string | undefined) => React.ReactNode;
  submitLabel: string;
  loadingLabel?: string;
  variant?: "primary" | "secondary" | "destructive";
  confirmMessage?: string;
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form
      action={formAction}
      onSubmit={(event) => {
        if (confirmMessage && !window.confirm(confirmMessage)) event.preventDefault();
      }}
      className="flex flex-col gap-2"
    >
      {children?.(describedBy)}
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant={variant} loading={pending} loadingLabel={loadingLabel ?? "Working…"} className="w-fit">
        {submitLabel}
      </Button>
    </form>
  );
}

export function AssessmentDetailPanel({
  tenantSlug: _tenantSlug,
  viewerAuthUserId,
  assessment,
  template,
  criteria,
  breakdown,
  findings,
  correctiveActions,
  vendorLegalName,
  reassessmentTemplates,
  recordAnswerActionFor,
  calculateAction,
  submitAction,
  beginReviewAction,
  decideReviewAction,
  adjustScoreAction,
  closeAction,
  startReassessmentAction,
  raiseFindingAction,
  decideFindingActionFor,
  createCorrectiveActionActionFor,
  updateCorrectiveActionStatusActionFor,
}: {
  tenantSlug: string;
  viewerAuthUserId: string;
  assessment: VendorAssessment;
  template: VendorAssessmentTemplate;
  criteria: readonly VendorAssessmentTemplateCriterion[];
  breakdown: readonly VendorAssessmentScoreBreakdownRow[];
  findings: readonly VendorAssessmentFinding[];
  correctiveActions: readonly VendorAssessmentCorrectiveAction[];
  vendorLegalName: string;
  reassessmentTemplates: readonly VendorAssessmentTemplate[];
  recordAnswerActionFor: (criterionId: string) => BoundFormAction;
  calculateAction: BoundFormAction;
  submitAction: BoundFormAction;
  beginReviewAction: BoundFormAction;
  decideReviewAction: BoundFormAction;
  adjustScoreAction: BoundFormAction;
  closeAction: BoundFormAction;
  startReassessmentAction: BoundFormAction;
  raiseFindingAction: BoundFormAction;
  decideFindingActionFor: (findingId: string, expectedVersion: number) => BoundFormAction;
  createCorrectiveActionActionFor: (findingId: string) => BoundFormAction;
  updateCorrectiveActionStatusActionFor: (correctiveActionId: string, expectedVersion: number) => BoundFormAction;
}) {
  const isAssessor = viewerAuthUserId === assessment.assessorAuthUserId;
  const canEditAnswers = isAssessor && (assessment.status === "draft" || assessment.status === "in_progress");
  const canSubmit = isAssessor && (assessment.status === "draft" || assessment.status === "in_progress");
  const canBeginReview = !isAssessor && assessment.status === "submitted";
  const canDecide = !isAssessor && (assessment.status === "submitted" || assessment.status === "under_review");
  const canAdjustScore = assessment.status === "submitted" || assessment.status === "under_review";
  const canClose = assessment.status === "approved" || assessment.status === "rejected";
  const canReassess = assessment.status === "approved" || assessment.status === "closed";
  const canRaiseFinding = ["draft", "in_progress", "submitted", "under_review"].includes(assessment.status);
  const openCorrectiveActionCount = correctiveActions.filter((ca) => ca.status === "open" || ca.status === "overdue").length;

  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-col gap-1">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-xl font-semibold text-neutral-900">
            {vendorLegalName} — {assessment.assessmentType.replace(/_/g, " ")} assessment
          </h1>
          <StatusBadge tone={STATUS_TONE[assessment.status]} label={assessment.status.replace(/_/g, " ")} />
          {assessment.reassessmentDue ? <StatusBadge tone="warning" label="Reassessment due" /> : null}
        </div>
        <p className="text-xs text-neutral-500">
          Applied template: {template.name} (v{template.recordVersion}, pass ≥ {template.passThreshold}, conditional ≥ {template.conditionalThreshold})
          {assessment.expiryDate ? ` · Expires ${assessment.expiryDate}` : ""}
        </p>
        {assessment.predecessorAssessmentId ? <p className="text-xs text-neutral-500">Reassessment of a prior cycle.</p> : null}
      </header>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Questionnaire</h2>
        {criteria.length === 0 ? (
          <EmptyState title="This template defines no criteria" />
        ) : (
          <ul className="flex flex-col gap-4">
            {criteria.map((criterion) => {
              const answer = breakdown.find((row) => row.criterionId === criterion.id);
              return (
                <li key={criterion.id} className="rounded-md border border-neutral-100 p-3">
                  <div className="flex items-baseline justify-between gap-2">
                    <p className="text-sm font-medium text-neutral-900">
                      {criterion.label} <span className="text-xs font-normal text-neutral-500">(weight {criterion.weight}, {criterion.purposeTag})</span>
                    </p>
                    {answer?.answered ? <StatusBadge tone="success" label="Answered" /> : <StatusBadge tone="neutral" label="Unanswered" /> }
                  </div>
                  {criterion.scoringGuidance ? <p className="text-xs text-neutral-500">{criterion.scoringGuidance}</p> : null}

                  {canEditAnswers ? (
                    <ActionForm action={recordAnswerActionFor(criterion.id)} submitLabel={answer?.answered ? "Update answer" : "Record answer"} loadingLabel="Saving…">
                      {(describedBy) => (
                        <div className="grid grid-cols-1 gap-2 sm:grid-cols-4">
                          <label htmlFor={`answer-value-${criterion.id}`} className="sr-only">
                            Value / observation
                          </label>
                          <Input id={`answer-value-${criterion.id}`} name="value" defaultValue={answer?.value ?? ""} placeholder="Value / observation" className="sm:col-span-2" aria-describedby={describedBy} />
                          <label htmlFor={`answer-score-${criterion.id}`} className="sr-only">
                            Score
                          </label>
                          <Input id={`answer-score-${criterion.id}`} name="score" type="number" min={0} max={100} defaultValue={answer?.answerScore ?? undefined} placeholder="Score (0-100)" required aria-describedby={describedBy} />
                          <label htmlFor={`answer-evidence-${criterion.id}`} className="sr-only">
                            Evidence file
                          </label>
                          <input id={`answer-evidence-${criterion.id}`} name="evidenceFile" type="file" className="text-xs" aria-describedby={describedBy} />
                          <label htmlFor={`answer-notes-${criterion.id}`} className="sr-only">
                            Notes
                          </label>
                          <Textarea id={`answer-notes-${criterion.id}`} name="notes" defaultValue={answer?.notes ?? ""} placeholder="Notes (optional)" className="sm:col-span-4" rows={2} aria-describedby={describedBy} />
                        </div>
                      )}
                    </ActionForm>
                  ) : (
                    <dl className="grid grid-cols-2 gap-1 text-xs text-neutral-600 sm:grid-cols-4">
                      <div>
                        <dt className="text-neutral-400">Value</dt>
                        <dd>{answer?.value ?? "—"}</dd>
                      </div>
                      <div>
                        <dt className="text-neutral-400">Score</dt>
                        <dd>{answer?.answerScore ?? "—"}</dd>
                      </div>
                      <div>
                        <dt className="text-neutral-400">Contribution</dt>
                        <dd>{answer?.contribution ?? "—"}</dd>
                      </div>
                      <div>
                        <dt className="text-neutral-400">Evidence</dt>
                        <dd>{answer?.evidenceFileId ? "Attached" : "—"}</dd>
                      </div>
                    </dl>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Score explanation</h2>
        <div className="overflow-x-auto">
        <table className="w-full min-w-[480px] text-sm">
          <thead>
            <tr className="text-left text-xs text-neutral-500">
              <th className="pb-1">Criterion</th>
              <th className="pb-1">Weight</th>
              <th className="pb-1">Score</th>
              <th className="pb-1">Contribution</th>
            </tr>
          </thead>
          <tbody>
            {breakdown.map((row) => (
              <tr key={row.criterionId} className="border-t border-neutral-100">
                <td className="py-1">{row.label}</td>
                <td className="py-1">{row.weight}</td>
                <td className="py-1">{row.answerScore ?? "—"}</td>
                <td className="py-1 font-medium">{row.contribution}</td>
              </tr>
            ))}
          </tbody>
        </table>
        </div>
        <p className="text-sm text-neutral-700">
          Calculated score: <strong>{assessment.calculatedScore ?? "—"}</strong> ({assessment.scoreBand ?? "not yet calculated"})
          {assessment.adjustedScore !== null ? (
            <>
              {" "}
              · Manually adjusted to <strong>{assessment.adjustedScore}</strong> ({assessment.adjustmentReason})
            </>
          ) : null}
        </p>
        {assessment.status !== "closed" ? (
          <ActionForm action={calculateAction} submitLabel="Recalculate score" loadingLabel="Calculating…" variant="secondary" />
        ) : null}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Submit and review</h2>
        <div className="flex flex-wrap gap-4">
          {canSubmit ? <ActionForm action={submitAction} submitLabel="Submit for review" loadingLabel="Submitting…" /> : null}
          {canBeginReview ? <ActionForm action={beginReviewAction} submitLabel="Begin review" loadingLabel="Starting review…" variant="secondary" /> : null}
        </div>

        {canDecide ? (
          <ActionForm action={decideReviewAction} submitLabel="Record decision" loadingLabel="Recording…">
            {(describedBy) => (
              <div className="flex flex-wrap items-end gap-2">
                <label htmlFor="review-decision" className="sr-only">
                  Decision
                </label>
                <Select id="review-decision" name="decision" required aria-describedby={describedBy}>
                  <option value="approve">Approve</option>
                  <option value="reject">Reject</option>
                </Select>
                <label htmlFor="review-decision-reason" className="sr-only">
                  Reason
                </label>
                <Input id="review-decision-reason" name="reason" placeholder="Reason (required to reject)" aria-describedby={describedBy} />
              </div>
            )}
          </ActionForm>
        ) : isAssessor && (assessment.status === "submitted" || assessment.status === "under_review") ? (
          <p className="text-xs text-neutral-500">As the assessor, you cannot decide your own review (maker-checker separation).</p>
        ) : null}

        {canAdjustScore ? (
          <details className="rounded-md border border-neutral-100 p-2">
            <summary className="cursor-pointer text-sm font-medium text-neutral-700">Manual score override (requires elevated authority)</summary>
            <ActionForm action={adjustScoreAction} submitLabel="Apply override" loadingLabel="Applying…" variant="destructive">
              {(describedBy) => (
                <div className="flex flex-wrap items-end gap-2">
                  <label htmlFor="adjust-score" className="sr-only">
                    Adjusted score
                  </label>
                  <Input id="adjust-score" name="adjustedScore" type="number" min={0} max={100} placeholder="Adjusted score" required aria-describedby={describedBy} />
                  <label htmlFor="adjust-score-reason" className="sr-only">
                    Reason
                  </label>
                  <Input id="adjust-score-reason" name="reason" placeholder="Reason (required)" required aria-describedby={describedBy} />
                </div>
              )}
            </ActionForm>
          </details>
        ) : null}

        {canClose ? (
          <ActionForm action={closeAction} submitLabel="Close assessment" loadingLabel="Closing…" variant="secondary">
            {(describedBy) =>
              openCorrectiveActionCount > 0 ? (
                <div className="flex flex-col gap-1">
                  <p className="text-xs text-warning">{openCorrectiveActionCount} corrective action(s) still open. Closing requires an override reason and elevated authority.</p>
                  <label htmlFor="close-override-reason" className="sr-only">
                    Override reason
                  </label>
                  <Input id="close-override-reason" name="overrideReason" placeholder="Override reason (required)" required aria-describedby={describedBy} />
                </div>
              ) : null
            }
          </ActionForm>
        ) : null}

        {canReassess ? (
          <details className="rounded-md border border-neutral-100 p-2">
            <summary className="cursor-pointer text-sm font-medium text-neutral-700">Start reassessment</summary>
            {reassessmentTemplates.length === 0 ? (
              <p className="text-xs text-neutral-500">No published template of this assessment type is available.</p>
            ) : (
              <ActionForm action={startReassessmentAction} submitLabel="Start reassessment" loadingLabel="Starting…">
                {(describedBy) => (
                  <>
                    <label htmlFor="reassessment-template" className="sr-only">
                      Template
                    </label>
                    <Select id="reassessment-template" name="templateVersionId" required aria-describedby={describedBy}>
                      {reassessmentTemplates.map((t) => (
                        <option key={t.id} value={t.id}>
                          {t.name}
                        </option>
                      ))}
                    </Select>
                  </>
                )}
              </ActionForm>
            )}
          </details>
        ) : null}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Findings and corrective actions</h2>
        {findings.length === 0 ? <EmptyState title="No findings raised" /> : null}
        <ul className="flex flex-col gap-3">
          {findings.map((finding) => (
            <li key={finding.id} className="rounded-md border border-neutral-100 p-3">
              <div className="flex flex-wrap items-center gap-2">
                <StatusBadge tone={finding.severity === "critical" || finding.severity === "high" ? "danger" : finding.severity === "medium" ? "warning" : "neutral"} label={finding.severity} />
                <StatusBadge tone={finding.status === "open" ? "warning" : finding.status === "resolved" ? "success" : "neutral"} label={finding.status} />
                <p className="text-sm text-neutral-800">{finding.description}</p>
              </div>

              {finding.status === "open" ? (
                <ActionForm action={decideFindingActionFor(finding.id, finding.recordVersion)} submitLabel="Record decision" loadingLabel="Recording…" variant="secondary">
                  {(describedBy) => (
                    <div className="flex flex-wrap items-end gap-2">
                      <label htmlFor={`finding-decision-${finding.id}`} className="sr-only">
                        Decision
                      </label>
                      <Select id={`finding-decision-${finding.id}`} name="decision" required aria-describedby={describedBy}>
                        <option value="resolved">Resolved</option>
                        <option value="waived">Waived</option>
                      </Select>
                      <label htmlFor={`finding-decision-reason-${finding.id}`} className="sr-only">
                        Reason
                      </label>
                      <Input id={`finding-decision-reason-${finding.id}`} name="reason" placeholder="Reason (required)" required aria-describedby={describedBy} />
                    </div>
                  )}
                </ActionForm>
              ) : null}

              <div className="mt-2 flex flex-col gap-2">
                <p className="text-xs font-medium text-neutral-600">Corrective actions</p>
                <ul className="flex flex-col gap-2">
                  {correctiveActions
                    .filter((ca) => ca.findingId === finding.id)
                    .map((ca) => (
                      <li key={ca.id} className="rounded-md border border-neutral-100 p-2">
                        <div className="flex flex-wrap items-center gap-2">
                          <StatusBadge tone={ca.status === "open" || ca.status === "overdue" ? "warning" : "success"} label={ca.status} />
                          <p className="text-sm text-neutral-800">{ca.description}</p>
                          {ca.dueDate ? <span className="text-xs text-neutral-500">due {ca.dueDate}</span> : null}
                        </div>
                        {ca.status === "open" || ca.status === "overdue" ? (
                          <ActionForm action={updateCorrectiveActionStatusActionFor(ca.id, ca.recordVersion)} submitLabel="Update" loadingLabel="Updating…" variant="secondary">
                            {(describedBy) => (
                              <div className="grid grid-cols-1 gap-2 sm:grid-cols-4">
                                <label htmlFor={`ca-status-${ca.id}`} className="sr-only">
                                  New status
                                </label>
                                <Select id={`ca-status-${ca.id}`} name="newStatus" required aria-describedby={describedBy}>
                                  <option value="overdue">Mark overdue</option>
                                  <option value="completed">Mark completed</option>
                                  <option value="waived">Waive</option>
                                </Select>
                                <label htmlFor={`ca-resolution-notes-${ca.id}`} className="sr-only">
                                  Resolution notes
                                </label>
                                <Input id={`ca-resolution-notes-${ca.id}`} name="resolutionNotes" placeholder="Resolution notes (required for completed/waived)" className="sm:col-span-2" aria-describedby={describedBy} />
                                <label htmlFor={`ca-evidence-${ca.id}`} className="sr-only">
                                  Evidence file
                                </label>
                                <input id={`ca-evidence-${ca.id}`} name="evidenceFile" type="file" className="text-xs" aria-describedby={describedBy} />
                              </div>
                            )}
                          </ActionForm>
                        ) : (
                          <p className="text-xs text-neutral-500">{ca.resolutionNotes}</p>
                        )}
                      </li>
                    ))}
                </ul>
                {finding.status === "open" ? (
                  <ActionForm action={createCorrectiveActionActionFor(finding.id)} submitLabel="Add corrective action" loadingLabel="Adding…" variant="secondary">
                    {(describedBy) => (
                      <div className="flex flex-wrap items-end gap-2">
                        <label htmlFor={`ca-new-description-${finding.id}`} className="sr-only">
                          Description
                        </label>
                        <Input id={`ca-new-description-${finding.id}`} name="description" placeholder="Description" required aria-describedby={describedBy} />
                        <label htmlFor={`ca-new-due-date-${finding.id}`} className="sr-only">
                          Due date
                        </label>
                        <Input id={`ca-new-due-date-${finding.id}`} name="dueDate" type="date" aria-describedby={describedBy} />
                      </div>
                    )}
                  </ActionForm>
                ) : null}
              </div>
            </li>
          ))}
        </ul>

        {canRaiseFinding ? (
          <ActionForm action={raiseFindingAction} submitLabel="Raise finding" loadingLabel="Raising…" variant="secondary">
            {(describedBy) => (
              <div className="flex flex-wrap items-end gap-2">
                <label htmlFor="raise-finding-severity" className="sr-only">
                  Severity
                </label>
                <Select id="raise-finding-severity" name="severity" required aria-describedby={describedBy}>
                  <option value="low">Low</option>
                  <option value="medium">Medium</option>
                  <option value="high">High</option>
                  <option value="critical">Critical</option>
                </Select>
                <label htmlFor="raise-finding-description" className="sr-only">
                  Description
                </label>
                <Input id="raise-finding-description" name="description" placeholder="Description" required aria-describedby={describedBy} />
              </div>
            )}
          </ActionForm>
        ) : null}
      </section>
    </div>
  );
}
