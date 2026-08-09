"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../../../components/ui/button.tsx";
import { EmptyState } from "../../../../../../../components/ui/empty-state.tsx";
import type {
  ApplicationDetail,
  CandidateProfile,
  ApplicationStageHistoryRow,
  CandidateAssessment,
  InterviewWithPanel,
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
  scheduleInterviewAction,
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
  scheduleInterviewAction: Bound0;
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
                <input name="reason" placeholder="Rejection reason" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
                <Button type="submit" variant="destructive" loading={rejectPending} loadingLabel="Rejecting…">
                  Reject
                </Button>
              </form>
              <form action={withdrawFormAction} className="flex items-center gap-2">
                <input name="reason" placeholder="Withdrawal reason" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
                <Button type="submit" variant="secondary" loading={withdrawPending} loadingLabel="Withdrawing…">
                  Withdraw
                </Button>
              </form>
            </div>
          </details>
        </section>
      ) : null}
      {rejectState.error ? (
        <p role="alert" className="text-sm text-danger">
          {rejectState.error}
        </p>
      ) : null}
      {withdrawState.error ? (
        <p role="alert" className="text-sm text-danger">
          {withdrawState.error}
        </p>
      ) : null}

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
            ) : (
              <AssessmentResultForm assessmentId={a.id} expectedVersion={a.recordVersion} action={recordAssessmentResultAction(a.id, a.recordVersion)} />
            )}
          </div>
        ))}
        {application.stage === "assessment" || application.stage === "screening" ? (
          <form action={assessFormAction} className="flex flex-wrap items-end gap-2 rounded-md border border-dashed border-neutral-300 p-3" noValidate>
            <div className="flex flex-col gap-1">
              <label htmlFor="assessmentType" className="text-xs font-medium text-neutral-700">
                Type
              </label>
              <select id="assessmentType" name="assessmentType" className="rounded-md border border-neutral-300 px-2 py-1 text-sm">
                <option value="screening">Screening</option>
                <option value="technical">Technical</option>
                <option value="behavioral">Behavioral</option>
                <option value="case_study">Case study</option>
                <option value="other">Other</option>
              </select>
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="criteriaVersion" className="text-xs font-medium text-neutral-700">
                Criteria version
              </label>
              <input id="criteriaVersion" name="criteriaVersion" required className="w-32 rounded-md border border-neutral-300 px-2 py-1 text-sm" />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="maxScore" className="text-xs font-medium text-neutral-700">
                Max score
              </label>
              <input id="maxScore" name="maxScore" type="number" min="1" defaultValue={100} className="w-24 rounded-md border border-neutral-300 px-2 py-1 text-sm" />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="passThreshold" className="text-xs font-medium text-neutral-700">
                Pass threshold
              </label>
              <input id="passThreshold" name="passThreshold" type="number" min="0" className="w-24 rounded-md border border-neutral-300 px-2 py-1 text-sm" />
            </div>
            <Button type="submit" variant="secondary" loading={assessPending} loadingLabel="Adding…">
              Add assessment
            </Button>
            {assessState.error ? (
              <p role="alert" className="w-full text-sm text-danger">
                {assessState.error}
              </p>
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
            <div className="mt-2 flex flex-wrap gap-2">
              {iw.interview.status === "scheduled" ? (
                <>
                  <FeedbackForm action={submitFeedbackAction(iw.interview.id)} />
                  <StageButton label="Mark completed" action={completeInterviewAction(iw.interview.id, iw.interview.recordVersion)} />
                </>
              ) : null}
            </div>
          </div>
        ))}
        {application.stage === "interview" ? (
          <form action={interviewFormAction} className="flex flex-wrap items-end gap-2 rounded-md border border-dashed border-neutral-300 p-3" noValidate>
            <div className="flex flex-col gap-1">
              <label htmlFor="mode" className="text-xs font-medium text-neutral-700">
                Mode
              </label>
              <select id="mode" name="mode" className="rounded-md border border-neutral-300 px-2 py-1 text-sm">
                <option value="video">Video</option>
                <option value="phone">Phone</option>
                <option value="in_person">In person</option>
              </select>
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="scheduledAt" className="text-xs font-medium text-neutral-700">
                Scheduled at
              </label>
              <input id="scheduledAt" name="scheduledAt" type="datetime-local" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="durationMinutes" className="text-xs font-medium text-neutral-700">
                Duration (min)
              </label>
              <input id="durationMinutes" name="durationMinutes" type="number" min="1" defaultValue={45} className="w-24 rounded-md border border-neutral-300 px-2 py-1 text-sm" />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="interviewerEmployeeId" className="text-xs font-medium text-neutral-700">
                Interviewer employee id
              </label>
              <input id="interviewerEmployeeId" name="interviewerEmployeeId" required placeholder="uuid" className="w-56 rounded-md border border-neutral-300 px-2 py-1 text-sm" />
            </div>
            <Button type="submit" variant="secondary" loading={interviewPending} loadingLabel="Scheduling…">
              Schedule
            </Button>
            {interviewState.error ? (
              <p role="alert" className="w-full text-sm text-danger">
                {interviewState.error}
              </p>
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
            <div className="flex flex-col gap-1">
              <label htmlFor="title" className="text-xs font-medium text-neutral-700">
                Title
              </label>
              <input id="title" name="title" required defaultValue={detail.vacancyTitle} className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="compensationAmount" className="text-xs font-medium text-neutral-700">
                Compensation
              </label>
              <input id="compensationAmount" name="compensationAmount" type="number" min="0" step="0.01" required className="w-32 rounded-md border border-neutral-300 px-2 py-1 text-sm" />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="compensationCurrency" className="text-xs font-medium text-neutral-700">
                Currency
              </label>
              <input id="compensationCurrency" name="compensationCurrency" defaultValue="IDR" required className="w-20 rounded-md border border-neutral-300 px-2 py-1 text-sm" />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="effectiveDate" className="text-xs font-medium text-neutral-700">
                Effective date
              </label>
              <input id="effectiveDate" name="effectiveDate" type="date" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="expiryDate" className="text-xs font-medium text-neutral-700">
                Response deadline
              </label>
              <input id="expiryDate" name="expiryDate" type="date" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
            </div>
            <input type="hidden" name="employmentType" value="full_time" />
            <Button type="submit" variant="secondary" loading={offerPending} loadingLabel="Saving…">
              {offer ? "Create revised version" : "Create offer"}
            </Button>
            {offerState.error ? (
              <p role="alert" className="w-full text-sm text-danger">
                {offerState.error}
              </p>
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
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <Button type="submit" loading={pending} loadingLabel="Working…">
        {label}
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function AssessmentResultForm({ action }: { assessmentId: string; expectedVersion: number; action: Bound0 }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="mt-2 flex flex-wrap items-end gap-2">
      <div className="flex flex-col gap-1">
        <label className="text-xs font-medium text-neutral-700">Score</label>
        <input name="score" type="number" min="0" step="0.01" required className="w-24 rounded-md border border-neutral-300 px-2 py-1 text-sm" />
      </div>
      <input name="notes" placeholder="Notes" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
        Record result
      </Button>
      {state.error ? (
        <p role="alert" className="w-full text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function FeedbackForm({ action }: { action: Bound0 }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <details>
      <summary className="cursor-pointer text-sm text-primary">Submit my feedback</summary>
      <form action={formAction} className="mt-2 flex flex-wrap items-end gap-2" noValidate>
        <div className="flex flex-col gap-1">
          <label className="text-xs font-medium text-neutral-700">Rating (1-5)</label>
          <input name="rating" type="number" min="1" max="5" defaultValue={3} className="w-16 rounded-md border border-neutral-300 px-2 py-1 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label className="text-xs font-medium text-neutral-700">Recommendation</label>
          <select name="recommendation" className="rounded-md border border-neutral-300 px-2 py-1 text-sm">
            <option value="strong_yes">Strong yes</option>
            <option value="yes">Yes</option>
            <option value="no">No</option>
            <option value="strong_no">Strong no</option>
          </select>
        </div>
        <input name="notes" placeholder="Notes" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Submitting…">
          Submit feedback
        </Button>
        {state.error ? (
          <p role="alert" className="w-full text-xs text-danger">
            {state.error}
          </p>
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
  return (
    <details>
      <summary className="cursor-pointer text-sm text-primary">Decide (as approver)</summary>
      <div className="mt-2 flex flex-col gap-2">
        <label className="text-xs font-medium text-neutral-700">
          Approval step id
          <input
            value={requestStepId}
            onChange={(e) => setRequestStepId(e.target.value)}
            required
            placeholder="uuid"
            className="mt-1 block w-full rounded-md border border-neutral-300 px-2 py-1 text-sm"
          />
        </label>
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
  return (
    <form action={formAction} className="flex flex-col gap-1">
      {decision === "rejected" ? <input name="reason" placeholder="Reason" className="rounded-md border border-neutral-300 px-2 py-1 text-xs" /> : null}
      <Button type="submit" variant={decision === "rejected" ? "destructive" : "primary"} loading={pending} loadingLabel="Saving…">
        {label}
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function OfferResponseForm({ label, action }: { label: string; action: Bound0 }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <input name="responseNote" placeholder="Note (optional)" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
        {label}
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}
