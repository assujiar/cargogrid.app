"use client";

import { useActionState, useId, useState } from "react";
import { Button } from "../../../../../../../components/ui/button.tsx";
import { EmptyState } from "../../../../../../../components/ui/empty-state.tsx";
import { Input } from "../../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../../components/forms/validation-message.tsx";
import type {
  ApplicationDetail,
  CandidateProfile,
  ApplicationStageHistoryRow,
  CandidateAssessment,
  InterviewWithPanel,
  Interview,
  ApplicationStage,
  OfferStatus,
  OfferApprovalStatus,
  OfferResponse,
} from "../../../../../../../server/contracts/recruitment/recruitment.ts";
import type { ApplicationActionState } from "./actions.ts";

const INITIAL_STATE: ApplicationActionState = { error: null };

const FORWARD_STAGES: { value: ApplicationStage; label: string }[] = [
  { value: "screening", label: "Screening" },
  { value: "assessment", label: "Assessment" },
  { value: "interview", label: "Interview" },
  { value: "offer", label: "Offer" },
];

type Bound0 = (prevState: ApplicationActionState, formData: FormData) => Promise<ApplicationActionState>;

interface OfferSummary {
  readonly id: string;
  readonly status: OfferStatus;
  readonly approvalStatus: OfferApprovalStatus;
  readonly approvalRequestId: string | null;
  readonly currentVersionId: string | null;
  readonly recordVersion: number;
}

export function ApplicationDetailPanel({
  tenantSlug,
  detail,
  candidate,
  stageHistory,
  assessments,
  interviews,
  offer,
  transitionStageAction,
  rejectAction,
  withdrawAction,
  createAssessmentAction,
  recordAssessmentResultAction,
  cancelAssessmentAction,
  scheduleInterviewAction,
  rescheduleInterviewAction,
  cancelInterviewAction,
  completeInterviewAction,
  submitFeedbackAction,
  createOfferVersionAction,
  submitOfferForApprovalAction,
  decideOfferApprovalAction,
  extendOfferAction,
  recordOfferResponseAction,
}: {
  tenantSlug: string;
  detail: ApplicationDetail;
  candidate: CandidateProfile;
  stageHistory: ApplicationStageHistoryRow[];
  assessments: CandidateAssessment[];
  interviews: InterviewWithPanel[];
  offer: OfferSummary | null;
  transitionStageAction: (toStage: ApplicationStage) => Bound0;
  rejectAction: Bound0;
  withdrawAction: Bound0;
  createAssessmentAction: Bound0;
  recordAssessmentResultAction: (assessmentId: string, expectedVersion: number) => Bound0;
  cancelAssessmentAction: (assessmentId: string, expectedVersion: number) => Bound0;
  scheduleInterviewAction: Bound0;
  rescheduleInterviewAction: (interviewId: string, expectedVersion: number) => Bound0;
  cancelInterviewAction: (interviewId: string, expectedVersion: number) => Bound0;
  completeInterviewAction: (interviewId: string, expectedVersion: number) => Bound0;
  submitFeedbackAction: (interviewId: string) => Bound0;
  createOfferVersionAction: Bound0;
  submitOfferForApprovalAction: (offerId: string, expectedVersion: number) => Bound0;
  decideOfferApprovalAction: (requestStepId: string, decision: "approved" | "rejected") => Bound0;
  extendOfferAction: (offerId: string, expectedVersion: number) => Bound0;
  recordOfferResponseAction: (offerId: string, expectedVersion: number, response: OfferResponse) => Bound0;
}) {
  const { application } = detail;
  const isTerminal = application.stage === "rejected" || application.stage === "withdrawn" || application.stage === "offer_accepted";

  const [rejectState, rejectFormAction, rejectPending] = useActionState(rejectAction, INITIAL_STATE);
  const [withdrawState, withdrawFormAction, withdrawPending] = useActionState(withdrawAction, INITIAL_STATE);
  const [assessState, assessFormAction, assessPending] = useActionState(createAssessmentAction, INITIAL_STATE);
  const [interviewState, interviewFormAction, interviewPending] = useActionState(scheduleInterviewAction, INITIAL_STATE);
  const [offerState, offerFormAction, offerPending] = useActionState(createOfferVersionAction, INITIAL_STATE);

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">{candidate.fullName}</h1>
        <p className="text-sm text-neutral-500">
          Applying for <span className="font-medium">{detail.vacancyTitle}</span>
        </p>
        <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-neutral-500">
          <span className="rounded-full bg-neutral-100 px-2 py-0.5 font-medium text-neutral-700">{application.stage.replace("_", " ")}</span>
          {candidate.personalDataMasked ? <span className="italic">Contact details masked -- you don&apos;t hold HRS:View personal data</span> : <span>{candidate.email}</span>}
        </div>
      </div>

      {!isTerminal ? (
        <section className="flex flex-wrap items-center gap-2 rounded-md border border-neutral-200 p-3">
          {FORWARD_STAGES.filter((s) => rankOf(s.value) > rankOf(application.stage)).map((s) => (
            <StageButton key={s.value} label={`Advance to ${s.label}`} action={transitionStageAction(s.value)} />
          ))}
          <details className="ml-auto">
            <summary className="cursor-pointer text-sm text-danger">Reject / withdraw</summary>
            <div className="mt-2 flex flex-col gap-2">
              <form action={rejectFormAction} className="flex items-center gap-2">
                <label className="sr-only" htmlFor="reject-reason">
                  Rejection reason
                </label>
                <Input id="reject-reason" name="reason" placeholder="Rejection reason" required invalid={Boolean(rejectState.error)} aria-describedby={rejectState.error ? "reject-error" : undefined} />
                <Button type="submit" variant="destructive" loading={rejectPending} loadingLabel="Rejecting…">
                  Reject
                </Button>
              </form>
              <form action={withdrawFormAction} className="flex items-center gap-2">
                <label className="sr-only" htmlFor="withdraw-reason">
                  Withdrawal reason
                </label>
                <Input id="withdraw-reason" name="reason" placeholder="Withdrawal reason" required invalid={Boolean(withdrawState.error)} aria-describedby={withdrawState.error ? "withdraw-error" : undefined} />
                <Button type="submit" variant="secondary" loading={withdrawPending} loadingLabel="Withdrawing…">
                  Withdraw
                </Button>
              </form>
            </div>
          </details>
        </section>
      ) : null}
      {rejectState.error ? <ValidationMessage id="reject-error">{rejectState.error}</ValidationMessage> : null}
      {withdrawState.error ? <ValidationMessage id="withdraw-error">{withdrawState.error}</ValidationMessage> : null}

      <section>
        <h2 className="mb-2 text-sm font-semibold text-neutral-900">Stage history</h2>
        {stageHistory.length === 0 ? (
          <EmptyState title="No history yet" />
        ) : (
          <ol className="flex flex-col gap-1 text-sm text-neutral-600">
            {stageHistory.map((h) => (
              <li key={h.id}>
                {h.fromStage} &rarr; {h.toStage}
                {h.reason ? ` (${h.reason})` : ""} <span className="text-xs text-neutral-400">{new Date(h.occurredAt).toLocaleString()}</span>
              </li>
            ))}
          </ol>
        )}
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-900">Assessments</h2>
        {assessments.map((a) => (
          <div key={a.id} className="rounded-md border border-neutral-200 p-3 text-sm">
            <div className="flex items-center justify-between">
              <span className="font-medium">
                {a.assessmentType} ({a.criteriaVersion})
              </span>
              <span className="rounded-full bg-neutral-100 px-2 py-0.5 text-xs">{a.status}</span>
            </div>
            {a.status === "completed" ? (
              <p className="mt-1 text-neutral-600">
                Score: {a.score} / {a.maxScore}
                {a.passThreshold != null ? ` (pass threshold ${a.passThreshold})` : ""}
              </p>
            ) : a.status === "cancelled" ? (
              <p className="mt-1 text-neutral-500">Cancelled{a.notes ? `: ${a.notes}` : "."}</p>
            ) : (
              <>
                <AssessmentResultForm assessmentId={a.id} expectedVersion={a.recordVersion} action={recordAssessmentResultAction(a.id, a.recordVersion)} />
                <CancelForm label="Cancel assessment" reasonPlaceholder="Cancellation reason" action={cancelAssessmentAction(a.id, a.recordVersion)} />
              </>
            )}
          </div>
        ))}
        {application.stage === "assessment" || application.stage === "screening" ? (
          <form action={assessFormAction} className="flex flex-wrap items-end gap-2 rounded-md border border-dashed border-neutral-300 p-3" noValidate>
            <FormField id="assessmentType" label="Type">
              <Select id="assessmentType" name="assessmentType" invalid={Boolean(assessState.error)} aria-describedby={assessState.error ? "assess-error" : undefined}>
                <option value="screening">Screening</option>
                <option value="technical">Technical</option>
                <option value="behavioral">Behavioral</option>
                <option value="case_study">Case study</option>
                <option value="other">Other</option>
              </Select>
            </FormField>
            <FormField id="criteriaVersion" label="Criteria version">
              <Input id="criteriaVersion" name="criteriaVersion" required className="w-32" invalid={Boolean(assessState.error)} aria-describedby={assessState.error ? "assess-error" : undefined} />
            </FormField>
            <FormField id="maxScore" label="Max score">
              <Input id="maxScore" name="maxScore" type="number" min="1" defaultValue={100} className="w-24" invalid={Boolean(assessState.error)} aria-describedby={assessState.error ? "assess-error" : undefined} />
            </FormField>
            <FormField id="passThreshold" label="Pass threshold">
              <Input id="passThreshold" name="passThreshold" type="number" min="0" className="w-24" invalid={Boolean(assessState.error)} aria-describedby={assessState.error ? "assess-error" : undefined} />
            </FormField>
            <Button type="submit" variant="secondary" loading={assessPending} loadingLabel="Adding…">
              Add assessment
            </Button>
            {assessState.error ? (
              <div className="w-full">
                <ValidationMessage id="assess-error">{assessState.error}</ValidationMessage>
              </div>
            ) : null}
          </form>
        ) : null}
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-900">Interviews</h2>
        {interviews.map((iw) => (
          <div key={iw.interview.id} className="rounded-md border border-neutral-200 p-3 text-sm">
            <div className="flex items-center justify-between">
              <span className="font-medium">
                Round {iw.interview.round} &middot; {iw.interview.mode} &middot; {new Date(iw.interview.scheduledAt).toLocaleString()}
              </span>
              <span className="rounded-full bg-neutral-100 px-2 py-0.5 text-xs">{iw.interview.status}</span>
            </div>
            <p className="mt-1 text-xs text-neutral-500">{iw.feedbackCount} of {iw.interviewerEmployeeIds.length} scorecard(s) submitted</p>
            <div className="mt-2 flex flex-wrap items-start gap-2">
              {iw.interview.status === "scheduled" ? (
                <>
                  <FeedbackForm interviewId={iw.interview.id} action={submitFeedbackAction(iw.interview.id)} />
                  <StageButton label="Mark completed" action={completeInterviewAction(iw.interview.id, iw.interview.recordVersion)} />
                  <RescheduleInterviewForm interview={iw.interview} action={rescheduleInterviewAction(iw.interview.id, iw.interview.recordVersion)} />
                  <CancelForm label="Cancel interview" reasonPlaceholder="Cancellation reason" action={cancelInterviewAction(iw.interview.id, iw.interview.recordVersion)} />
                </>
              ) : null}
            </div>
          </div>
        ))}
        {application.stage === "interview" ? (
          <form action={interviewFormAction} className="flex flex-wrap items-end gap-2 rounded-md border border-dashed border-neutral-300 p-3" noValidate>
            <FormField id="mode" label="Mode">
              <Select id="mode" name="mode" invalid={Boolean(interviewState.error)} aria-describedby={interviewState.error ? "interview-error" : undefined}>
                <option value="video">Video</option>
                <option value="phone">Phone</option>
                <option value="in_person">In person</option>
              </Select>
            </FormField>
            <FormField id="scheduledAt" label="Scheduled at">
              <Input id="scheduledAt" name="scheduledAt" type="datetime-local" required invalid={Boolean(interviewState.error)} aria-describedby={interviewState.error ? "interview-error" : undefined} />
            </FormField>
            <FormField id="durationMinutes" label="Duration (min)">
              <Input id="durationMinutes" name="durationMinutes" type="number" min="1" defaultValue={45} className="w-24" invalid={Boolean(interviewState.error)} aria-describedby={interviewState.error ? "interview-error" : undefined} />
            </FormField>
            <FormField id="interviewerEmployeeId" label="Interviewer employee id">
              <Input id="interviewerEmployeeId" name="interviewerEmployeeId" required placeholder="uuid" className="w-56" invalid={Boolean(interviewState.error)} aria-describedby={interviewState.error ? "interview-error" : undefined} />
            </FormField>
            <Button type="submit" variant="secondary" loading={interviewPending} loadingLabel="Scheduling…">
              Schedule
            </Button>
            {interviewState.error ? (
              <div className="w-full">
                <ValidationMessage id="interview-error">{interviewState.error}</ValidationMessage>
              </div>
            ) : null}
          </form>
        ) : null}
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-900">Offer</h2>
        {offer ? (
          <div className="rounded-md border border-neutral-200 p-3 text-sm">
            <div className="flex items-center justify-between">
              <span className="font-medium">Status: {offer.status.replace("_", " ")}</span>
              <span className="rounded-full bg-neutral-100 px-2 py-0.5 text-xs">approval: {offer.approvalStatus.replace("_", " ")}</span>
            </div>
            <div className="mt-2 flex flex-wrap gap-2">
              {offer.status === "draft" && offer.currentVersionId ? <StageButton label="Submit for approval" action={submitOfferForApprovalAction(offer.id, offer.recordVersion)} /> : null}
              {offer.status === "pending_approval" && offer.approvalRequestId ? <ApprovalStepForm decideAction={decideOfferApprovalAction} /> : null}
              {offer.status === "approved" ? <StageButton label="Extend to candidate" action={extendOfferAction(offer.id, offer.recordVersion)} /> : null}
              {offer.status === "extended" ? (
                <>
                  <OfferResponseForm label="Record accepted" action={recordOfferResponseAction(offer.id, offer.recordVersion, "accepted")} />
                  <OfferResponseForm label="Record declined" action={recordOfferResponseAction(offer.id, offer.recordVersion, "declined")} />
                </>
              ) : null}
            </div>
          </div>
        ) : (
          <p className="text-sm text-neutral-500">No offer created yet.</p>
        )}
        {application.stage === "offer" && (!offer || ["draft", "approved", "declined"].includes(offer.status)) ? (
          <form action={offerFormAction} className="flex flex-wrap items-end gap-2 rounded-md border border-dashed border-neutral-300 p-3" noValidate>
            <FormField id="title" label="Title">
              <Input id="title" name="title" required defaultValue={detail.vacancyTitle} invalid={Boolean(offerState.error)} aria-describedby={offerState.error ? "offer-error" : undefined} />
            </FormField>
            <FormField id="compensationAmount" label="Compensation">
              <Input id="compensationAmount" name="compensationAmount" type="number" min="0" step="0.01" required className="w-32" invalid={Boolean(offerState.error)} aria-describedby={offerState.error ? "offer-error" : undefined} />
            </FormField>
            <FormField id="compensationCurrency" label="Currency">
              <Input id="compensationCurrency" name="compensationCurrency" defaultValue="IDR" required className="w-20" invalid={Boolean(offerState.error)} aria-describedby={offerState.error ? "offer-error" : undefined} />
            </FormField>
            <FormField id="effectiveDate" label="Effective date">
              <Input id="effectiveDate" name="effectiveDate" type="date" required invalid={Boolean(offerState.error)} aria-describedby={offerState.error ? "offer-error" : undefined} />
            </FormField>
            <FormField id="expiryDate" label="Response deadline">
              <Input id="expiryDate" name="expiryDate" type="date" invalid={Boolean(offerState.error)} aria-describedby={offerState.error ? "offer-error" : undefined} />
            </FormField>
            <input type="hidden" name="employmentType" value="full_time" />
            <Button type="submit" variant="secondary" loading={offerPending} loadingLabel="Saving…">
              {offer ? "Create revised version" : "Create offer"}
            </Button>
            {offerState.error ? (
              <div className="w-full">
                <ValidationMessage id="offer-error">{offerState.error}</ValidationMessage>
              </div>
            ) : null}
          </form>
        ) : null}
      </section>
    </div>
  );
}

function rankOf(stage: ApplicationStage): number {
  return { new: 1, screening: 2, assessment: 3, interview: 4, offer: 5, offer_accepted: 6, rejected: 0, withdrawn: 0 }[stage];
}

function StageButton({ label, action }: { label: string; action: Bound0 }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <Button type="submit" loading={pending} loadingLabel="Working…">
        {label}
      </Button>
      {state.error ? <ValidationMessage id={`${reactId}-error`}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function AssessmentResultForm({ assessmentId, action }: { assessmentId: string; expectedVersion: number; action: Bound0 }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const notesId = `assessment-notes-${assessmentId}`;
  const errorId = `assessment-result-error-${assessmentId}`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="mt-2 flex flex-wrap items-end gap-2">
      <FormField id={`assessment-score-${assessmentId}`} label="Score">
        <Input id={`assessment-score-${assessmentId}`} name="score" type="number" min="0" step="0.01" required className="w-24" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <label className="sr-only" htmlFor={notesId}>
        Notes
      </label>
      <Input id={notesId} name="notes" placeholder="Notes" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
        Record result
      </Button>
      {state.error ? (
        <div className="w-full">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

/** ISS-2026-067 item 3: `app.cancel_candidate_assessment`/`app.cancel_interview` had no UI caller. Shared shape -- both take just a reason. */
function CancelForm({ label, reasonPlaceholder, action }: { label: string; reasonPlaceholder: string; action: Bound0 }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  return (
    <details>
      <summary className="cursor-pointer text-sm text-danger">{label}</summary>
      <form action={formAction} className="mt-2 flex items-center gap-2">
        <label className="sr-only" htmlFor={reactId}>
          {reasonPlaceholder}
        </label>
        <Input id={reactId} name="reason" placeholder={reasonPlaceholder} required invalid={Boolean(state.error)} aria-describedby={state.error ? errorId : undefined} />
        <Button type="submit" variant="destructive" loading={pending} loadingLabel="Cancelling…">
          Confirm
        </Button>
      </form>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </details>
  );
}

/** ISS-2026-067 item 3: `app.reschedule_interview` had no UI caller. */
function RescheduleInterviewForm({ interview, action }: { interview: Interview; action: Bound0 }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const errorId = `reschedule-error-${interview.id}`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <details>
      <summary className="cursor-pointer text-sm text-primary">Reschedule</summary>
      <form action={formAction} className="mt-2 flex flex-wrap items-end gap-2" noValidate>
        <FormField id={`reschedule-mode-${interview.id}`} label="Mode">
          <Select id={`reschedule-mode-${interview.id}`} name="mode" defaultValue={interview.mode} invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="video">Video</option>
            <option value="phone">Phone</option>
            <option value="in_person">In person</option>
          </Select>
        </FormField>
        <FormField id={`reschedule-at-${interview.id}`} label="New scheduled time">
          <Input id={`reschedule-at-${interview.id}`} name="scheduledAt" type="datetime-local" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id={`reschedule-duration-${interview.id}`} label="Duration (min)">
          <Input
            id={`reschedule-duration-${interview.id}`}
            name="durationMinutes"
            type="number"
            min="1"
            defaultValue={interview.durationMinutes}
            className="w-24"
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          />
        </FormField>
        <FormField id={`reschedule-location-${interview.id}`} label="Location / link">
          <Input
            id={`reschedule-location-${interview.id}`}
            name="locationOrLink"
            defaultValue={interview.locationOrLink ?? ""}
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          />
        </FormField>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
          Reschedule
        </Button>
        {state.error ? (
          <div className="w-full">
            <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
          </div>
        ) : null}
      </form>
    </details>
  );
}

function FeedbackForm({ interviewId, action }: { interviewId: string; action: Bound0 }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const notesId = `feedback-notes-${interviewId}`;
  const errorId = `feedback-error-${interviewId}`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <details>
      <summary className="cursor-pointer text-sm text-primary">Submit my feedback</summary>
      <form action={formAction} className="mt-2 flex flex-wrap items-end gap-2" noValidate>
        <FormField id={`feedback-rating-${interviewId}`} label="Rating (1-5)">
          <Input id={`feedback-rating-${interviewId}`} name="rating" type="number" min="1" max="5" defaultValue={3} className="w-16" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id={`feedback-recommendation-${interviewId}`} label="Recommendation">
          <Select id={`feedback-recommendation-${interviewId}`} name="recommendation" invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="strong_yes">Strong yes</option>
            <option value="yes">Yes</option>
            <option value="no">No</option>
            <option value="strong_no">Strong no</option>
          </Select>
        </FormField>
        <label className="sr-only" htmlFor={notesId}>
          Notes
        </label>
        <Input id={notesId} name="notes" placeholder="Notes" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Submitting…">
          Submit feedback
        </Button>
        {state.error ? (
          <div className="w-full">
            <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
          </div>
        ) : null}
      </form>
    </details>
  );
}

/**
 * Records an approver's decision (design note 4: no domain permission gate of its own
 * -- app.decide_approval_step already gates on eligible-approver identity, PLT-123).
 * This repository has no dedicated approver inbox UI anywhere yet (the same
 * disclosed, standing "ships with zero authoring/inbox UI" posture PLT-123 itself
 * established) -- an approver enters the step id from wherever their own approval was
 * routed to them (e.g. app.list_pending_approval_steps_for_actor, scripted today).
 * The two decision buttons themselves are real, working Server Actions, not a
 * placeholder -- only the step-id lookup surface is the disclosed gap.
 */
function ApprovalStepForm({ decideAction }: { decideAction: (requestStepId: string, decision: "approved" | "rejected") => Bound0 }) {
  const [requestStepId, setRequestStepId] = useState("");
  const reactId = useId();
  return (
    <details>
      <summary className="cursor-pointer text-sm text-primary">Decide (as approver)</summary>
      <div className="mt-2 flex flex-col gap-2">
        <FormField id={reactId} label="Approval step id">
          <Input
            id={reactId}
            value={requestStepId}
            onChange={(e) => setRequestStepId(e.target.value)}
            required
            placeholder="uuid"
          />
        </FormField>
        {requestStepId ? (
          <div className="flex gap-2">
            <ApprovalDecisionButton label="Approve" decision="approved" requestStepId={requestStepId} action={decideAction} />
            <ApprovalDecisionButton label="Reject" decision="rejected" requestStepId={requestStepId} action={decideAction} />
          </div>
        ) : null}
      </div>
    </details>
  );
}

function ApprovalDecisionButton({
  label,
  decision,
  requestStepId,
  action,
}: {
  label: string;
  decision: "approved" | "rejected";
  requestStepId: string;
  action: (requestStepId: string, decision: "approved" | "rejected") => Bound0;
}) {
  const [state, formAction, pending] = useActionState(action(requestStepId, decision), INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  return (
    <form action={formAction} className="flex flex-col gap-1">
      {decision === "rejected" ? (
        <>
          <label className="sr-only" htmlFor={reactId}>
            Reason
          </label>
          <Input id={reactId} name="reason" placeholder="Reason" className="text-xs" invalid={Boolean(state.error)} aria-describedby={state.error ? errorId : undefined} />
        </>
      ) : null}
      <Button type="submit" variant={decision === "rejected" ? "destructive" : "primary"} loading={pending} loadingLabel="Saving…">
        {label}
      </Button>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function OfferResponseForm({ label, action }: { label: string; action: Bound0 }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <label className="sr-only" htmlFor={reactId}>
        Note (optional)
      </label>
      <Input id={reactId} name="responseNote" placeholder="Note (optional)" invalid={Boolean(state.error)} aria-describedby={state.error ? errorId : undefined} />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
        {label}
      </Button>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}
