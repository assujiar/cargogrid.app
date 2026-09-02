"use client";

import { useActionState, useId } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { DateInput } from "../../../../../../components/forms/date-input.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../../../components/forms/number-input.tsx";
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
  children?: (describedBy: string | undefined, invalid: boolean) => React.ReactNode;
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
      {children?.(describedBy, Boolean(state.error))}
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
                      {(describedBy, invalid) => (
                        <div className="grid grid-cols-1 gap-2 sm:grid-cols-4">
                          <div className="sm:col-span-2">
                            <FormField id={`answer-value-${criterion.id}`} label={<span className="sr-only">Value / observation</span>}>
                              <Input id={`answer-value-${criterion.id}`} name="value" defaultValue={answer?.value ?? ""} placeholder="Value / observation" invalid={invalid} aria-describedby={describedBy} />
                            </FormField>
                          </div>
                          <FormField id={`answer-score-${criterion.id}`} label={<span className="sr-only">Score</span>}>
                            <NumberInput
                              id={`answer-score-${criterion.id}`}
                              name="score"
                              min={0}
                              max={100}
                              defaultValue={answer?.answerScore ?? undefined}
                              placeholder="Score (0-100)"
                              required
                              invalid={invalid} aria-describedby={describedBy}
                            />
                          </FormField>
                          <FormField id={`answer-evidence-${criterion.id}`} label={<span className="sr-only">Evidence file</span>}>
                            <input id={`answer-evidence-${criterion.id}`} name="evidenceFile" type="file" className="text-xs" aria-describedby={describedBy} />
                          </FormField>
                          <div className="sm:col-span-4">
                            <FormField id={`answer-notes-${criterion.id}`} label={<span className="sr-only">Notes</span>}>
                              <Textarea id={`answer-notes-${criterion.id}`} name="notes" defaultValue={answer?.notes ?? ""} placeholder="Notes (optional)" rows={2} invalid={invalid} aria-describedby={describedBy} />
                            </FormField>
                          </div>
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
            {(describedBy, invalid) => (
              <div className="flex flex-wrap items-end gap-2">
                <FormField id="review-decision" label={<span className="sr-only">Decision</span>}>
                  <Select id="review-decision" name="decision" required invalid={invalid} aria-describedby={describedBy}>
                    <option value="approve">Approve</option>
                    <option value="reject">Reject</option>
                  </Select>
                </FormField>
                <FormField id="review-decision-reason" label={<span className="sr-only">Reason</span>}>
                  <Input id="review-decision-reason" name="reason" placeholder="Reason (required to reject)" invalid={invalid} aria-describedby={describedBy} />
                </FormField>
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
              {(describedBy, invalid) => (
                <div className="flex flex-wrap items-end gap-2">
                  <FormField id="adjust-score" label={<span className="sr-only">Adjusted score</span>}>
                    <NumberInput id="adjust-score" name="adjustedScore" min={0} max={100} placeholder="Adjusted score" required invalid={invalid} aria-describedby={describedBy} />
                  </FormField>
                  <FormField id="adjust-score-reason" label={<span className="sr-only">Reason</span>}>
                    <Input id="adjust-score-reason" name="reason" placeholder="Reason (required)" required invalid={invalid} aria-describedby={describedBy} />
                  </FormField>
                </div>
              )}
            </ActionForm>
          </details>
        ) : null}

        {canClose ? (
          <ActionForm action={closeAction} submitLabel="Close assessment" loadingLabel="Closing…" variant="secondary">
            {(describedBy, invalid) =>
              openCorrectiveActionCount > 0 ? (
                <div className="flex flex-col gap-1">
                  <p className="text-xs text-warning">{openCorrectiveActionCount} corrective action(s) still open. Closing requires an override reason and elevated authority.</p>
                  <FormField id="close-override-reason" label={<span className="sr-only">Override reason</span>}>
                    <Input id="close-override-reason" name="overrideReason" placeholder="Override reason (required)" required invalid={invalid} aria-describedby={describedBy} />
                  </FormField>
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
                {(describedBy, invalid) => (
                  <FormField id="reassessment-template" label={<span className="sr-only">Template</span>}>
                    <Select id="reassessment-template" name="templateVersionId" required invalid={invalid} aria-describedby={describedBy}>
                      {reassessmentTemplates.map((t) => (
                        <option key={t.id} value={t.id}>
                          {t.name}
                        </option>
                      ))}
                    </Select>
                  </FormField>
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
                  {(describedBy, invalid) => (
                    <div className="flex flex-wrap items-end gap-2">
                      <FormField id={`finding-decision-${finding.id}`} label={<span className="sr-only">Decision</span>}>
                        <Select id={`finding-decision-${finding.id}`} name="decision" required invalid={invalid} aria-describedby={describedBy}>
                          <option value="resolved">Resolved</option>
                          <option value="waived">Waived</option>
                        </Select>
                      </FormField>
                      <FormField id={`finding-decision-reason-${finding.id}`} label={<span className="sr-only">Reason</span>}>
                        <Input id={`finding-decision-reason-${finding.id}`} name="reason" placeholder="Reason (required)" required invalid={invalid} aria-describedby={describedBy} />
                      </FormField>
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
                            {(describedBy, invalid) => (
                              <div className="grid grid-cols-1 gap-2 sm:grid-cols-4">
                                <FormField id={`ca-status-${ca.id}`} label={<span className="sr-only">New status</span>}>
                                  <Select id={`ca-status-${ca.id}`} name="newStatus" required invalid={invalid} aria-describedby={describedBy}>
                                    <option value="overdue">Mark overdue</option>
                                    <option value="completed">Mark completed</option>
                                    <option value="waived">Waive</option>
                                  </Select>
                                </FormField>
                                <div className="sm:col-span-2">
                                  <FormField id={`ca-resolution-notes-${ca.id}`} label={<span className="sr-only">Resolution notes</span>}>
                                    <Input
                                      id={`ca-resolution-notes-${ca.id}`}
                                      name="resolutionNotes"
                                      placeholder="Resolution notes (required for completed/waived)"
                                      invalid={invalid} aria-describedby={describedBy}
                                    />
                                  </FormField>
                                </div>
                                <FormField id={`ca-evidence-${ca.id}`} label={<span className="sr-only">Evidence file</span>}>
                                  <input id={`ca-evidence-${ca.id}`} name="evidenceFile" type="file" className="text-xs" aria-describedby={describedBy} />
                                </FormField>
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
                    {(describedBy, invalid) => (
                      <div className="flex flex-wrap items-end gap-2">
                        <FormField id={`ca-new-description-${finding.id}`} label={<span className="sr-only">Description</span>}>
                          <Input id={`ca-new-description-${finding.id}`} name="description" placeholder="Description" required invalid={invalid} aria-describedby={describedBy} />
                        </FormField>
                        <FormField id={`ca-new-due-date-${finding.id}`} label={<span className="sr-only">Due date</span>}>
                          <DateInput id={`ca-new-due-date-${finding.id}`} name="dueDate" invalid={invalid} aria-describedby={describedBy} />
                        </FormField>
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
            {(describedBy, invalid) => (
              <div className="flex flex-wrap items-end gap-2">
                <FormField id="raise-finding-severity" label={<span className="sr-only">Severity</span>}>
                  <Select id="raise-finding-severity" name="severity" required invalid={invalid} aria-describedby={describedBy}>
                    <option value="low">Low</option>
                    <option value="medium">Medium</option>
                    <option value="high">High</option>
                    <option value="critical">Critical</option>
                  </Select>
                </FormField>
                <FormField id="raise-finding-description" label={<span className="sr-only">Description</span>}>
                  <Input id="raise-finding-description" name="description" placeholder="Description" required invalid={invalid} aria-describedby={describedBy} />
                </FormField>
              </div>
            )}
          </ActionForm>
        ) : null}
      </section>
    </div>
  );
}
