"use client";

import { useActionState, useId } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { Textarea } from "../../../../../../components/forms/textarea.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type {
  TrainingSessionRow,
  TrainingEnrollmentRow,
  TrainingCertificateRow,
  TrainingDevelopmentPlanRow,
  TrainingDevelopmentPlanActionRow,
  TalentReviewAssignmentRow,
} from "../../../../../../server/contracts/training-talent/training-talent.ts";
import type { MyTrainingTalentActionState } from "./actions.ts";

const INITIAL_STATE: MyTrainingTalentActionState = { error: null };

const ENROLLMENT_STATUS_TONE: Record<string, StatusTone> = {
  pending_approval: "warning", enrolled: "success", waitlisted: "info", cancelled: "danger", completed: "success", failed: "danger", no_show: "danger",
};
const CERTIFICATE_STATUS_TONE: Record<string, StatusTone> = { issued: "success", expired: "danger", revoked: "danger" };
const PLAN_STATUS_TONE: Record<string, StatusTone> = { draft: "neutral", active: "info", completed: "success", cancelled: "danger" };
const ACTION_STATUS_TONE: Record<string, StatusTone> = { planned: "neutral", in_progress: "info", completed: "success", cancelled: "danger" };

type BoundAction = (prevState: MyTrainingTalentActionState, formData: FormData) => Promise<MyTrainingTalentActionState>;

function ErrorLine({ error, id }: { error: string | null; id?: string }) {
  return error ? <ValidationMessage id={id}>{error}</ValidationMessage> : null;
}

function Section({ title, description, children }: { title: string; description?: string; children: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-3 rounded-lg border border-neutral-200 p-4">
      <div>
        <h2 className="text-base font-semibold text-neutral-900">{title}</h2>
        {description ? <p className="text-xs text-neutral-500">{description}</p> : null}
      </div>
      {children}
    </section>
  );
}

function EnrollButton({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction}>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Enrolling…">Enroll</Button>
      <ErrorLine error={state.error} />
    </form>
  );
}

function CatalogueSection({ sessions, myEnrollments, enrollAction }: { sessions: TrainingSessionRow[]; myEnrollments: TrainingEnrollmentRow[]; enrollAction: (sessionId: string) => BoundAction }) {
  const myActiveSessionIds = new Set(myEnrollments.filter((e) => e.status !== "cancelled").map((e) => e.sessionId));
  const available = sessions.filter((s) => !myActiveSessionIds.has(s.id));
  return (
    <Section title="Available sessions" description="Prerequisites and capacity are enforced server-side -- a full session waitlists you automatically.">
      {available.length === 0 ? (
        <EmptyState title="No available sessions right now" description="Check back later, or ask HR about upcoming training." />
      ) : (
        <ul className="flex flex-col gap-2 text-sm">
          {available.map((s) => (
            <li key={s.id} className="flex items-center justify-between gap-2 rounded border border-neutral-200 p-2">
              <span>{s.courseName ?? s.courseCode ?? s.sessionCode} — {new Date(s.startAt).toLocaleDateString()} ({s.enrolledCount ?? 0}/{s.capacity})</span>
              <EnrollButton action={enrollAction(s.id)} />
            </li>
          ))}
        </ul>
      )}
    </Section>
  );
}

function MyEnrollmentsSection({ myEnrollments, cancelAction, rescheduleAction }: {
  myEnrollments: TrainingEnrollmentRow[];
  cancelAction: (enrollmentId: string, expectedVersion: number) => BoundAction;
  rescheduleAction: (enrollmentId: string) => BoundAction;
}) {
  return (
    <Section title="My enrollments">
      {myEnrollments.length === 0 ? (
        <EmptyState title="No enrollments yet" description="Enroll in a session above." />
      ) : (
        <ul className="flex flex-col gap-2 text-sm">
          {myEnrollments.map((e) => (
            <li key={e.id} className="flex flex-col gap-2 rounded border border-neutral-200 p-2">
              <div className="flex items-center justify-between">
                <span>{e.courseName ?? e.courseCode} {e.startAt ? `— ${new Date(e.startAt).toLocaleDateString()}` : ""}</span>
                <StatusBadge tone={ENROLLMENT_STATUS_TONE[e.status] ?? "neutral"} label={e.status} />
              </div>
              {e.status === "pending_approval" || e.status === "enrolled" || e.status === "waitlisted" ? (
                <div className="flex flex-wrap gap-2">
                  <CancelForm action={cancelAction(e.id, e.recordVersion)} />
                  <RescheduleForm action={rescheduleAction(e.id)} />
                </div>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </Section>
  );
}

function CancelForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  return (
    <form action={formAction} className="flex items-center gap-2">
      <label className="sr-only" htmlFor={reactId}>
        Reason
      </label>
      <Input id={reactId} name="reason" required placeholder="reason" invalid={Boolean(state.error)} />
      <Button type="submit" variant="destructive" loading={pending} loadingLabel="Cancelling…">Cancel</Button>
      <ErrorLine error={state.error} />
    </form>
  );
}

function RescheduleForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  return (
    <form action={formAction} className="flex items-center gap-2">
      <label className="sr-only" htmlFor={reactId}>
        New session id
      </label>
      <Input id={reactId} name="newSessionId" required placeholder="new session id" invalid={Boolean(state.error)} />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Rescheduling…">Reschedule</Button>
      <ErrorLine error={state.error} />
    </form>
  );
}

function MyCertificatesSection({ myCertificates }: { myCertificates: TrainingCertificateRow[] }) {
  return (
    <Section title="My certificates">
      {myCertificates.length === 0 ? (
        <EmptyState title="No certificates yet" description="Certificates appear here once HR issues or imports them." />
      ) : (
        <ul className="flex flex-col gap-1 text-sm">
          {myCertificates.map((c) => (
            <li key={c.id} className="flex items-center justify-between rounded border border-neutral-200 p-2">
              <span>{c.courseName ?? c.externalCourseName} {c.expiryDate ? `(expires ${c.expiryDate})` : ""}</span>
              <StatusBadge tone={CERTIFICATE_STATUS_TONE[c.status] ?? "neutral"} label={c.status} />
            </li>
          ))}
        </ul>
      )}
    </Section>
  );
}

function MyDevelopmentPlansSection({ myPlans, planActionsByPlanId, updateActionStatusAction }: {
  myPlans: TrainingDevelopmentPlanRow[];
  planActionsByPlanId: Record<string, TrainingDevelopmentPlanActionRow[]>;
  updateActionStatusAction: (actionId: string, expectedVersion: number) => BoundAction;
}) {
  return (
    <Section title="My development plan">
      {myPlans.length === 0 ? (
        <EmptyState title="No development plan yet" description="Your manager or HR can create one for you." />
      ) : (
        <ul className="flex flex-col gap-2 text-sm">
          {myPlans.map((p) => (
            <li key={p.id} className="flex flex-col gap-2 rounded border border-neutral-200 p-2">
              <div className="flex items-center justify-between">
                <span>{p.title} {p.cycleLabel ? `(${p.cycleLabel})` : ""}</span>
                <StatusBadge tone={PLAN_STATUS_TONE[p.status] ?? "neutral"} label={p.status} />
              </div>
              <ul className="flex flex-col gap-1 text-xs text-neutral-600">
                {(planActionsByPlanId[p.id] ?? []).map((a) => (
                  <li key={a.id} className="flex items-center justify-between gap-2">
                    <span>{a.description}</span>
                    <div className="flex items-center gap-2">
                      <StatusBadge tone={ACTION_STATUS_TONE[a.status] ?? "neutral"} label={a.status} />
                      {a.status !== "completed" && a.status !== "cancelled" ? (
                        <ProgressActionForm action={updateActionStatusAction(a.id, a.recordVersion)} />
                      ) : null}
                    </div>
                  </li>
                ))}
              </ul>
            </li>
          ))}
        </ul>
      )}
    </Section>
  );
}

function ProgressActionForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  return (
    <form action={formAction} className="flex items-center gap-2">
      <label className="sr-only" htmlFor={reactId}>
        Status
      </label>
      <Select id={reactId} name="status" className="text-xs" invalid={Boolean(state.error)}>
        <option value="in_progress">In progress</option>
        <option value="completed">Completed</option>
      </Select>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">Update</Button>
      <ErrorLine error={state.error} />
    </form>
  );
}

function MyTalentReviewSection({ myReviewAssignments, submitReviewAction }: { myReviewAssignments: TalentReviewAssignmentRow[]; submitReviewAction: (reviewId: string, expectedVersion: number) => BoundAction }) {
  if (myReviewAssignments.length === 0) return null;
  return (
    <Section title="My assigned talent review cases" description="Restricted -- visible only because you are the assigned reviewer for these specific cases.">
      <ul className="flex flex-col gap-2 text-sm">
        {myReviewAssignments.map((a) => (
          <li key={a.id} className="flex flex-col gap-2 rounded border border-neutral-200 p-2">
            <div className="flex items-center justify-between">
              <span>{a.subjectFullName ?? a.subjectEmployeeId} ({a.cycleName})</span>
              <StatusBadge tone={a.reviewStatus === "submitted" ? "success" : "warning"} label={a.reviewStatus ?? "draft"} />
            </div>
            {a.reviewStatus === "draft" && a.reviewId ? <SubmitReviewForm action={submitReviewAction(a.reviewId, 1)} /> : null}
          </li>
        ))}
      </ul>
    </Section>
  );
}

function SubmitReviewForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  const describedBy = state.error ? `${reactId}-error` : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      <label className="sr-only" htmlFor={`${reactId}-potential`}>
        Potential rating
      </label>
      <Select id={`${reactId}-potential`} name="potentialRating" required invalid={Boolean(state.error)} aria-describedby={describedBy}>
        <option value="">Potential rating…</option><option value="low">Low</option><option value="moderate">Moderate</option><option value="high">High</option>
      </Select>
      <label className="sr-only" htmlFor={`${reactId}-risk`}>
        Risk of loss
      </label>
      <Select id={`${reactId}-risk`} name="riskOfLoss" invalid={Boolean(state.error)} aria-describedby={describedBy}>
        <option value="">Risk of loss (optional)…</option><option value="low">Low</option><option value="medium">Medium</option><option value="high">High</option>
      </Select>
      <label className="sr-only" htmlFor={`${reactId}-note`}>
        Readiness note
      </label>
      <Textarea id={`${reactId}-note`} name="readinessNote" placeholder="readiness note" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Submitting…">Submit review</Button>
      <ErrorLine error={state.error} id={`${reactId}-error`} />
    </form>
  );
}

export interface MyTrainingTalentPanelProps {
  sessions: TrainingSessionRow[];
  myEnrollments: TrainingEnrollmentRow[];
  myCertificates: TrainingCertificateRow[];
  myPlans: TrainingDevelopmentPlanRow[];
  planActionsByPlanId: Record<string, TrainingDevelopmentPlanActionRow[]>;
  myReviewAssignments: TalentReviewAssignmentRow[];
  enrollAction: (sessionId: string) => BoundAction;
  cancelEnrollmentAction: (enrollmentId: string, expectedVersion: number) => BoundAction;
  rescheduleEnrollmentAction: (enrollmentId: string) => BoundAction;
  updateActionStatusAction: (actionId: string, expectedVersion: number) => BoundAction;
  submitReviewAction: (reviewId: string, expectedVersion: number) => BoundAction;
}

export function MyTrainingTalentPanel(props: MyTrainingTalentPanelProps) {
  return (
    <div className="flex flex-col gap-6 p-4">
      <h1 className="text-xl font-semibold text-neutral-900">My Training and Development</h1>
      <CatalogueSection sessions={props.sessions} myEnrollments={props.myEnrollments} enrollAction={props.enrollAction} />
      <MyEnrollmentsSection myEnrollments={props.myEnrollments} cancelAction={props.cancelEnrollmentAction} rescheduleAction={props.rescheduleEnrollmentAction} />
      <MyCertificatesSection myCertificates={props.myCertificates} />
      <MyDevelopmentPlansSection myPlans={props.myPlans} planActionsByPlanId={props.planActionsByPlanId} updateActionStatusAction={props.updateActionStatusAction} />
      <MyTalentReviewSection myReviewAssignments={props.myReviewAssignments} submitReviewAction={props.submitReviewAction} />
    </div>
  );
}
