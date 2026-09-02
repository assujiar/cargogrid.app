"use client";

import { useActionState, useId } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Checkbox } from "../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type {
  TrainingCompetencyRow,
  TrainingCourseRow,
  TrainingCourseVersionRow,
  TrainingProviderRow,
  TrainingSessionRow,
  TrainingEnrollmentRow,
  TrainingCertificateRow,
  TrainingDevelopmentPlanRow,
  TalentReviewCycleRow,
  TalentReviewAssignmentRow,
  TalentPoolRow,
  TalentPoolMemberRow,
  TalentPoolDistributionRow,
  TalentSuccessionCandidateRow,
} from "../../../../../server/contracts/training-talent/training-talent.ts";
import type { TrainingTalentAdminActionState } from "./actions.ts";

const INITIAL_STATE: TrainingTalentAdminActionState = { error: null };

const CATALOGUE_STATUS_TONE: Record<string, StatusTone> = { draft: "neutral", published: "success", archived: "neutral" };
const SESSION_STATUS_TONE: Record<string, StatusTone> = { scheduled: "info", in_progress: "warning", completed: "success", cancelled: "danger" };
const ENROLLMENT_STATUS_TONE: Record<string, StatusTone> = {
  pending_approval: "warning", enrolled: "success", waitlisted: "info", cancelled: "danger", completed: "success", failed: "danger", no_show: "danger",
};
const CERTIFICATE_STATUS_TONE: Record<string, StatusTone> = { issued: "success", expired: "danger", revoked: "danger" };
const CYCLE_STATUS_TONE: Record<string, StatusTone> = { draft: "neutral", active: "info", closed: "success" };
const CANDIDATE_STATUS_TONE: Record<string, StatusTone> = { proposed: "warning", confirmed: "success", withdrawn: "neutral" };

type BoundAction = (prevState: TrainingTalentAdminActionState, formData: FormData) => Promise<TrainingTalentAdminActionState>;

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

function InlineForm({ action, children, submitLabel, pendingLabel }: { action: BoundAction; children: (describedBy: string | undefined, invalid: boolean) => React.ReactNode; submitLabel: string; pendingLabel?: string }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  return (
    <form action={formAction} className="flex flex-col gap-2">
      {children(state.error ? errorId : undefined, Boolean(state.error))}
      <Button type="submit" variant="primary" loading={pending} loadingLabel={pendingLabel ?? "Working…"}>{submitLabel}</Button>
      <ErrorLine error={state.error} id={errorId} />
    </form>
  );
}

// --- Competency ---

function CompetencySection({ competencies, createAction, publishAction }: {
  competencies: TrainingCompetencyRow[];
  createAction: BoundAction;
  publishAction: (competencyId: string, expectedVersion: number) => BoundAction;
}) {
  return (
    <Section title="Competencies" description="The skill/competency reference taxonomy a course can teach.">
      <InlineForm action={createAction} submitLabel="Create competency">
        {(describedBy, invalid) => (
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
            <FormField id="competency-code" label="Code">
              <Input id="competency-code" name="code" required placeholder="e.g. safety_basics" invalid={invalid} aria-describedby={describedBy} />
            </FormField>
            <FormField id="competency-name" label="Name">
              <Input id="competency-name" name="name" required invalid={invalid} aria-describedby={describedBy} />
            </FormField>
            <FormField id="competency-category" label="Category">
              <Input id="competency-category" name="category" invalid={invalid} aria-describedby={describedBy} />
            </FormField>
          </div>
        )}
      </InlineForm>
      {competencies.length === 0 ? (
        <EmptyState title="No competencies yet" description="Create the first one above." />
      ) : (
        <ul className="flex flex-col gap-1 text-sm">
          {competencies.map((c) => (
            <li key={c.id} className="flex items-center justify-between gap-2 rounded border border-neutral-200 p-2">
              <span>{c.code} — {c.name}</span>
              <div className="flex items-center gap-2">
                <StatusBadge tone={CATALOGUE_STATUS_TONE[c.status] ?? "neutral"} label={c.status} />
                {c.status === "draft" ? (
                  <PublishButton action={publishAction(c.id, c.recordVersion)} />
                ) : null}
              </div>
            </li>
          ))}
        </ul>
      )}
    </Section>
  );
}

function PublishButton({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  return (
    <form action={formAction}>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Publishing…">Publish</Button>
      <ErrorLine error={state.error} id={`${reactId}-error`} />
    </form>
  );
}

// --- Course / version ---

function CourseSection({ courses, courseVersionsByCourseId, createAction, publishVersionAction, addCompetencyAction, addPrerequisiteAction }: {
  courses: TrainingCourseRow[];
  courseVersionsByCourseId: Record<string, TrainingCourseVersionRow[]>;
  createAction: BoundAction;
  publishVersionAction: (versionId: string, expectedVersion: number) => BoundAction;
  addCompetencyAction: (courseId: string) => BoundAction;
  addPrerequisiteAction: (courseId: string) => BoundAction;
}) {
  return (
    <Section title="Courses" description="A course's curriculum content (assessment/certificate rules, mandatory flag) is versioned -- exactly one published version at a time.">
      <InlineForm action={createAction} submitLabel="Create course + draft version">
        {(describedBy, invalid) => (
          <>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
              <FormField id="course-code" label="Code">
                <Input id="course-code" name="code" required placeholder="e.g. safety_101" invalid={invalid} aria-describedby={describedBy} />
              </FormField>
              <FormField id="course-name" label="Name">
                <Input id="course-name" name="name" required invalid={invalid} aria-describedby={describedBy} />
              </FormField>
              <FormField id="course-category" label="Category">
                <Input id="course-category" name="category" invalid={invalid} aria-describedby={describedBy} />
              </FormField>
            </div>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
              <FormField id="course-deliveryMode" label="Delivery mode">
                <Select id="course-deliveryMode" name="deliveryMode" defaultValue="in_person" invalid={invalid} aria-describedby={describedBy}>
                  <option value="in_person">In person</option><option value="virtual">Virtual</option><option value="e_learning">E-learning</option><option value="blended">Blended</option>
                </Select>
              </FormField>
              <FormField id="course-description" label="Description">
                <Input id="course-description" name="description" invalid={invalid} aria-describedby={describedBy} />
              </FormField>
            </div>
            <div className="flex flex-wrap gap-4 text-xs text-neutral-600">
              <Checkbox name="isMandatory" label="Mandatory compliance training" />
              <Checkbox name="requiresEnrollmentApproval" label="Requires enrollment approval" />
              <Checkbox name="requiresAssessment" label="Requires assessment" />
              <Checkbox name="issuesCertificate" label="Issues a certificate" />
            </div>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
              <FormField id="course-passingScore" label="Passing score (if assessed)">
                <Input id="course-passingScore" name="passingScore" type="number" defaultValue={70} invalid={invalid} aria-describedby={describedBy} />
              </FormField>
              <FormField id="course-certificateValidityMonths" label="Certificate validity (months)">
                <Input id="course-certificateValidityMonths" name="certificateValidityMonths" type="number" invalid={invalid} aria-describedby={describedBy} />
              </FormField>
            </div>
          </>
        )}
      </InlineForm>
      {courses.length === 0 ? (
        <EmptyState title="No courses yet" description="Create the first one above." />
      ) : (
        <ul className="flex flex-col gap-2 text-sm">
          {courses.map((course) => {
            const versions = courseVersionsByCourseId[course.id] ?? [];
            const published = versions.find((v) => v.status === "published");
            const draft = versions.find((v) => v.status === "draft");
            return (
              <li key={course.id} className="flex flex-col gap-1 rounded border border-neutral-200 p-2">
                <div className="flex items-center justify-between">
                  <span>{course.code} — {course.name}{course.category ? ` (${course.category})` : ""}</span>
                  {published ? <StatusBadge tone="success" label={`published v${published.versionNumber}`} /> : <StatusBadge tone="neutral" label="no published version" />}
                </div>
                {draft ? (
                  <div className="flex items-center gap-2 text-xs text-neutral-600">
                    <span>draft v{draft.versionNumber}</span>
                    <PublishButton action={publishVersionAction(draft.id, draft.recordVersion)} />
                  </div>
                ) : null}
                <details className="text-xs text-neutral-500">
                  <summary className="cursor-pointer">Link a competency this course teaches (by competency id)</summary>
                  <InlineForm action={addCompetencyAction(course.id)} submitLabel="Link competency">
                    {(describedBy, invalid) => (
                      <>
                        <label className="sr-only" htmlFor={`course-${course.id}-competencyId`}>
                          Competency id
                        </label>
                        <Input id={`course-${course.id}-competencyId`} name="competencyId" required placeholder="competency id" invalid={invalid} aria-describedby={describedBy} />
                      </>
                    )}
                  </InlineForm>
                </details>
                <details className="text-xs text-neutral-500">
                  <summary className="cursor-pointer">Add prerequisite (by course id)</summary>
                  <InlineForm action={addPrerequisiteAction(course.id)} submitLabel="Add prerequisite">
                    {(describedBy, invalid) => (
                      <>
                        <label className="sr-only" htmlFor={`course-${course.id}-prerequisiteCourseId`}>
                          Prerequisite course id
                        </label>
                        <Input id={`course-${course.id}-prerequisiteCourseId`} name="prerequisiteCourseId" required placeholder="prerequisite course id" invalid={invalid} aria-describedby={describedBy} />
                      </>
                    )}
                  </InlineForm>
                </details>
              </li>
            );
          })}
        </ul>
      )}
    </Section>
  );
}

// --- Provider / session ---

function ProviderSessionSection({ providers, sessions, courses, courseVersionsByCourseId, createProviderAction, attachProviderEvidenceAction, createSessionAction, cancelSessionAction, enrollEmployeeAction, bulkAssignAction }: {
  providers: TrainingProviderRow[];
  attachProviderEvidenceAction: (providerId: string, expectedVersion: number) => BoundAction;
  sessions: TrainingSessionRow[];
  courses: TrainingCourseRow[];
  courseVersionsByCourseId: Record<string, TrainingCourseVersionRow[]>;
  createProviderAction: BoundAction;
  createSessionAction: BoundAction;
  cancelSessionAction: (sessionId: string, expectedVersion: number) => BoundAction;
  enrollEmployeeAction: (sessionId: string) => BoundAction;
  bulkAssignAction: (sessionId: string) => BoundAction;
}) {
  const publishedVersions = courses.flatMap((c) => (courseVersionsByCourseId[c.id] ?? []).filter((v) => v.status === "published").map((v) => ({ course: c, version: v })));
  return (
    <Section title="Providers and sessions" description="Capacity and waitlist are enforced server-side under a session-row lock -- never trust a client-computed remaining count.">
      <InlineForm action={createProviderAction} submitLabel="Create provider">
        {(describedBy, invalid) => (
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <FormField id="provider-name" label="Name">
              <Input id="provider-name" name="name" required invalid={invalid} aria-describedby={describedBy} />
            </FormField>
            <FormField id="provider-type" label="Type">
              <Select id="provider-type" name="providerType" defaultValue="internal" invalid={invalid} aria-describedby={describedBy}>
                <option value="internal">Internal</option><option value="external">External</option>
              </Select>
            </FormField>
          </div>
        )}
      </InlineForm>

      {/*
        ISS-2026-083: the provider's own accreditation document -- Prompt 284 §16's other half.
        Certificate evidence proves an employee attended; this proves the body that issued the
        certificate was entitled to. Same PLT-128 discipline, enforced server-side.
      */}
      {providers.length > 0 ? (
        <ul className="flex flex-col gap-2 text-sm">
          {providers.slice(0, 25).map((p) => (
            <li key={p.id} className="flex items-center justify-between gap-2 rounded border border-neutral-200 p-2">
              <span>
                {p.name} ({p.providerType}
                {p.evidenceFileId ? ", accreditation attached" : ", no accreditation on file"})
              </span>
              <details className="text-xs">
                <summary className="cursor-pointer">{p.evidenceFileId ? "Replace accreditation" : "Attach accreditation"}</summary>
                <InlineForm action={attachProviderEvidenceAction(p.id, p.recordVersion)} submitLabel="Attach">
                  {(describedBy, invalid) => (
                    <>
                      <label className="sr-only" htmlFor={`provider-${p.id}-evidenceFileId`}>
                        Evidence file id
                      </label>
                      <Input id={`provider-${p.id}-evidenceFileId`} name="evidenceFileId" required placeholder="evidence file id (malware-scanned, PLT-128)" invalid={invalid} aria-describedby={describedBy} />
                    </>
                  )}
                </InlineForm>
              </details>
            </li>
          ))}
        </ul>
      ) : null}

      <InlineForm action={createSessionAction} submitLabel="Schedule session">
        {(describedBy, invalid) => (
          <>
            <FormField id="session-courseVersionId" label="Published course version">
              <Select id="session-courseVersionId" name="courseVersionId" required invalid={invalid} aria-describedby={describedBy}>
                <option value="">Select…</option>
                {publishedVersions.map(({ course, version }) => (
                  <option key={version.id} value={version.id}>{course.code} v{version.versionNumber}</option>
                ))}
              </Select>
            </FormField>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
              <FormField id="session-providerId" label="Provider">
                <Select id="session-providerId" name="providerId" invalid={invalid} aria-describedby={describedBy}>
                  <option value="">None</option>
                  {providers.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                </Select>
              </FormField>
              <FormField id="session-sessionCode" label="Session code">
                <Input id="session-sessionCode" name="sessionCode" required invalid={invalid} aria-describedby={describedBy} />
              </FormField>
            </div>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
              <FormField id="session-startAt" label="Start">
                <Input id="session-startAt" name="startAt" type="datetime-local" required invalid={invalid} aria-describedby={describedBy} />
              </FormField>
              <FormField id="session-endAt" label="End">
                <Input id="session-endAt" name="endAt" type="datetime-local" required invalid={invalid} aria-describedby={describedBy} />
              </FormField>
              <FormField id="session-capacity" label="Capacity">
                <Input id="session-capacity" name="capacity" type="number" min={1} required invalid={invalid} aria-describedby={describedBy} />
              </FormField>
            </div>
          </>
        )}
      </InlineForm>

      {sessions.length === 0 ? (
        <EmptyState title="No sessions scheduled" description="Schedule the first one above." />
      ) : (
        <ul className="flex flex-col gap-2 text-sm">
          {sessions.map((s) => (
            <li key={s.id} className="flex flex-col gap-1 rounded border border-neutral-200 p-2">
              <div className="flex items-center justify-between">
                <span>{s.sessionCode} — {s.courseCode ?? s.courseVersionId} ({s.enrolledCount ?? 0}/{s.capacity})</span>
                <StatusBadge tone={SESSION_STATUS_TONE[s.status] ?? "neutral"} label={s.status} />
              </div>
              {s.status === "scheduled" ? (
                <div className="flex flex-wrap items-center gap-2">
                  <details className="text-xs text-neutral-500">
                    <summary className="cursor-pointer">Assign employee</summary>
                    <InlineForm action={enrollEmployeeAction(s.id)} submitLabel="Assign">
                      {(describedBy, invalid) => (
                        <>
                          <label className="sr-only" htmlFor={`session-${s.id}-employeeId`}>
                            Employee id
                          </label>
                          <Input id={`session-${s.id}-employeeId`} name="employeeId" required placeholder="employee id" invalid={invalid} aria-describedby={describedBy} />
                        </>
                      )}
                    </InlineForm>
                  </details>
                  <BareActionButton action={bulkAssignAction(s.id)} label="Bulk-assign all (mandatory sessions only)" />
                  <details className="text-xs text-neutral-500">
                    <summary className="cursor-pointer">Cancel session</summary>
                    <InlineForm action={cancelSessionAction(s.id, s.recordVersion)} submitLabel="Cancel session">
                      {(describedBy, invalid) => (
                        <>
                          <label className="sr-only" htmlFor={`session-${s.id}-cancel-reason`}>
                            Reason
                          </label>
                          <Input id={`session-${s.id}-cancel-reason`} name="reason" required placeholder="reason" invalid={invalid} aria-describedby={describedBy} />
                        </>
                      )}
                    </InlineForm>
                  </details>
                </div>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </Section>
  );
}

function BareActionButton({ action, label }: { action: BoundAction; label: string }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  return (
    <form action={formAction}>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Working…">{label}</Button>
      <ErrorLine error={state.error} id={`${reactId}-error`} />
    </form>
  );
}

// --- Enrollment queue / attendance / assessment ---

function EnrollmentQueueSection({ pendingEnrollments, decideAction, recordAttendanceAction, recordCompletionAction, recordAssessmentAction }: {
  pendingEnrollments: TrainingEnrollmentRow[];
  decideAction: (enrollmentId: string, expectedVersion: number, decision: "approve" | "reject") => BoundAction;
  recordAttendanceAction: BoundAction;
  recordCompletionAction: BoundAction;
  recordAssessmentAction: BoundAction;
}) {
  return (
    <Section title="Enrollment approval queue" description="Requests pending approval (course versions with requires_enrollment_approval=true). Self-decision is structurally blocked at the RPC.">
      {pendingEnrollments.length === 0 ? (
        <EmptyState title="Nothing pending" description="No enrollment requests currently need a decision." />
      ) : (
        <ul className="flex flex-col gap-2 text-sm">
          {pendingEnrollments.map((e) => (
            <li key={e.id} className="flex flex-col gap-2 rounded border border-neutral-200 p-2">
              <div className="flex items-center justify-between">
                <span>{e.employeeFullName ?? e.employeeId} — {e.courseCode ?? e.courseVersionId} ({e.sessionCode})</span>
                <StatusBadge tone={ENROLLMENT_STATUS_TONE[e.status] ?? "neutral"} label={e.status} />
              </div>
              <div className="flex flex-wrap gap-2">
                <ApproveButton action={decideAction(e.id, e.recordVersion, "approve")} />
                <DecideRejectForm action={decideAction(e.id, e.recordVersion, "reject")} />
              </div>
            </li>
          ))}
        </ul>
      )}
      <details className="text-xs text-neutral-500">
        <summary className="cursor-pointer">Record attendance / completion / assessment (by enrollment id)</summary>
        <div className="mt-2 flex flex-col gap-3">
          <AttendanceForm recordAttendanceAction={recordAttendanceAction} />
          <CompletionForm recordCompletionAction={recordCompletionAction} />
          <AssessmentForm recordAssessmentAction={recordAssessmentAction} />
        </div>
      </details>
    </Section>
  );
}

function ApproveButton({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  return (
    <form action={formAction}>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Approving…">Approve</Button>
      <ErrorLine error={state.error} id={`${reactId}-error`} />
    </form>
  );
}

function DecideRejectForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  return (
    <form action={formAction} className="flex items-center gap-2">
      <label className="sr-only" htmlFor={reactId}>
        Reject reason
      </label>
      <Input id={reactId} name="decisionReason" required placeholder="reject reason" invalid={Boolean(state.error)} aria-describedby={state.error ? errorId : undefined} />
      <Button type="submit" variant="destructive" loading={pending} loadingLabel="Rejecting…">Reject</Button>
      <ErrorLine error={state.error} id={errorId} />
    </form>
  );
}

function AttendanceForm({ recordAttendanceAction }: { recordAttendanceAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(recordAttendanceAction, INITIAL_STATE);
  const reactId = useId();
  const enrollmentIdId = `${reactId}-enrollmentId`;
  const hoursId = `${reactId}-hoursAttended`;
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-center gap-2 text-xs">
      <label className="sr-only" htmlFor={enrollmentIdId}>
        Enrollment id
      </label>
      <Input id={enrollmentIdId} name="enrollmentId" required placeholder="enrollment id" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      <Checkbox name="attended" defaultChecked label="attended" />
      <label className="sr-only" htmlFor={hoursId}>
        Hours attended
      </label>
      <Input id={hoursId} name="hoursAttended" placeholder="hours" className="w-20" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Recording…">Record attendance</Button>
      <ErrorLine error={state.error} id={errorId} />
    </form>
  );
}

function CompletionForm({ recordCompletionAction }: { recordCompletionAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(recordCompletionAction, INITIAL_STATE);
  const reactId = useId();
  const enrollmentIdId = `${reactId}-enrollmentId`;
  const versionId = `${reactId}-expectedVersion`;
  const statusId = `${reactId}-completionStatus`;
  const notesId = `${reactId}-notes`;
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-center gap-2 text-xs">
      <label className="sr-only" htmlFor={enrollmentIdId}>
        Enrollment id
      </label>
      <Input id={enrollmentIdId} name="enrollmentId" required placeholder="enrollment id" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      <label className="sr-only" htmlFor={versionId}>
        Expected version
      </label>
      <Input id={versionId} name="expectedVersion" type="number" required placeholder="version" className="w-20" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      <label className="sr-only" htmlFor={statusId}>
        Completion status
      </label>
      <Select id={statusId} name="completionStatus" invalid={Boolean(state.error)} aria-describedby={describedBy}>
        <option value="completed">Completed</option><option value="failed">Failed</option><option value="no_show">No-show</option>
      </Select>
      <label className="sr-only" htmlFor={notesId}>
        Notes
      </label>
      <Input id={notesId} name="notes" placeholder="notes" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Recording…">Record completion</Button>
      <ErrorLine error={state.error} id={errorId} />
    </form>
  );
}

function AssessmentForm({ recordAssessmentAction }: { recordAssessmentAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(recordAssessmentAction, INITIAL_STATE);
  const reactId = useId();
  const enrollmentIdId = `${reactId}-enrollmentId`;
  const scoreId = `${reactId}-score`;
  const maxScoreId = `${reactId}-maxScore`;
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-center gap-2 text-xs">
      <label className="sr-only" htmlFor={enrollmentIdId}>
        Enrollment id
      </label>
      <Input id={enrollmentIdId} name="enrollmentId" required placeholder="enrollment id" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      <label className="sr-only" htmlFor={scoreId}>
        Score
      </label>
      <Input id={scoreId} name="score" type="number" required placeholder="score" className="w-20" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      <label className="sr-only" htmlFor={maxScoreId}>
        Max score
      </label>
      <Input id={maxScoreId} name="maxScore" type="number" defaultValue={100} placeholder="max score" className="w-24" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Recording…">Record assessment</Button>
      <ErrorLine error={state.error} id={errorId} />
    </form>
  );
}

// --- Certificate ---

function CertificateSection({ certificates, issueAction, importAction, attachEvidenceAction, verifyAction, revokeAction, runExpiryBatchAction, runReminderBatchAction }: {
  certificates: TrainingCertificateRow[];
  issueAction: BoundAction;
  importAction: BoundAction;
  attachEvidenceAction: (certificateId: string, expectedVersion: number) => BoundAction;
  verifyAction: (certificateId: string, expectedVersion: number) => BoundAction;
  revokeAction: (certificateId: string, expectedVersion: number) => BoundAction;
  runExpiryBatchAction: BoundAction;
  runReminderBatchAction: BoundAction;
}) {
  return (
    <Section title="Certificates" description="Certificate and provider evidence files are both private and malware-scanned before attach (PLT-128) -- provider accreditation lives in the Providers section above (ISS-2026-083). Expiry/reminder are real durable jobs (PLT-131/132).">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <InlineForm action={issueAction} submitLabel="Issue certificate">
          {(describedBy, invalid) => (
            <>
              <label className="sr-only" htmlFor="issue-cert-employeeId">
                Employee id
              </label>
              <Input id="issue-cert-employeeId" name="employeeId" required placeholder="employee id" invalid={invalid} aria-describedby={describedBy} />
              <label className="sr-only" htmlFor="issue-cert-courseVersionId">
                Course version id
              </label>
              <Input id="issue-cert-courseVersionId" name="courseVersionId" required placeholder="course version id" invalid={invalid} aria-describedby={describedBy} />
              <label className="sr-only" htmlFor="issue-cert-certificateNumber">
                Certificate number
              </label>
              <Input id="issue-cert-certificateNumber" name="certificateNumber" placeholder="certificate number" invalid={invalid} aria-describedby={describedBy} />
              <FormField id="issue-cert-issuedAt" label="Issued">
                <Input id="issue-cert-issuedAt" name="issuedAt" type="date" required invalid={invalid} aria-describedby={describedBy} />
              </FormField>
              <FormField id="issue-cert-expiryDate" label="Expires">
                <Input id="issue-cert-expiryDate" name="expiryDate" type="date" invalid={invalid} aria-describedby={describedBy} />
              </FormField>
            </>
          )}
        </InlineForm>
        <InlineForm action={importAction} submitLabel="Import historical certificate">
          {(describedBy, invalid) => (
            <>
              <label className="sr-only" htmlFor="import-cert-employeeId">
                Employee id
              </label>
              <Input id="import-cert-employeeId" name="employeeId" required placeholder="employee id" invalid={invalid} aria-describedby={describedBy} />
              <label className="sr-only" htmlFor="import-cert-externalCourseName">
                External course name
              </label>
              <Input id="import-cert-externalCourseName" name="externalCourseName" required placeholder="external course name" invalid={invalid} aria-describedby={describedBy} />
              <label className="sr-only" htmlFor="import-cert-certificateNumber">
                Certificate number
              </label>
              <Input id="import-cert-certificateNumber" name="certificateNumber" placeholder="certificate number" invalid={invalid} aria-describedby={describedBy} />
              <FormField id="import-cert-issuedAt" label="Issued">
                <Input id="import-cert-issuedAt" name="issuedAt" type="date" required invalid={invalid} aria-describedby={describedBy} />
              </FormField>
              <FormField id="import-cert-expiryDate" label="Expires">
                <Input id="import-cert-expiryDate" name="expiryDate" type="date" invalid={invalid} aria-describedby={describedBy} />
              </FormField>
            </>
          )}
        </InlineForm>
      </div>

      {certificates.length === 0 ? (
        <EmptyState title="No certificates yet" description="Issue or import one above." />
      ) : (
        <ul className="flex flex-col gap-2 text-sm">
          {certificates.slice(0, 25).map((c) => (
            <li key={c.id} className="flex items-center justify-between gap-2 rounded border border-neutral-200 p-2">
              <span>{c.employeeFullName ?? c.employeeId} — {c.courseName ?? c.externalCourseName} ({c.source === "external_import" ? "imported" : "internal"}, {c.verificationStatus}{c.evidenceFileId ? ", evidence attached" : ""})</span>
              <div className="flex items-center gap-2">
                <StatusBadge tone={CERTIFICATE_STATUS_TONE[c.status] ?? "neutral"} label={c.status} />
                {c.status !== "revoked" ? (
                  <details className="text-xs">
                    <summary className="cursor-pointer">{c.evidenceFileId ? "Replace evidence" : "Attach evidence"}</summary>
                    <InlineForm action={attachEvidenceAction(c.id, c.recordVersion)} submitLabel="Attach">
                      {(describedBy, invalid) => (
                        <>
                          <label className="sr-only" htmlFor={`cert-${c.id}-evidenceFileId`}>
                            Evidence file id
                          </label>
                          <Input id={`cert-${c.id}-evidenceFileId`} name="evidenceFileId" required placeholder="evidence file id (malware-scanned, PLT-128)" invalid={invalid} aria-describedby={describedBy} />
                        </>
                      )}
                    </InlineForm>
                  </details>
                ) : null}
                {c.verificationStatus === "unverified" ? <PublishButton action={verifyAction(c.id, c.recordVersion)} /> : null}
                {c.status !== "revoked" ? (
                  <details className="text-xs">
                    <summary className="cursor-pointer">Revoke</summary>
                    <InlineForm action={revokeAction(c.id, c.recordVersion)} submitLabel="Revoke">
                      {(describedBy, invalid) => (
                        <>
                          <label className="sr-only" htmlFor={`cert-${c.id}-revoke-reason`}>
                            Reason
                          </label>
                          <Input id={`cert-${c.id}-revoke-reason`} name="reason" required placeholder="reason" invalid={invalid} aria-describedby={describedBy} />
                        </>
                      )}
                    </InlineForm>
                  </details>
                ) : null}
              </div>
            </li>
          ))}
        </ul>
      )}

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 border-t border-neutral-200 pt-3">
        <InlineForm action={runExpiryBatchAction} submitLabel="Run expiry batch">
          {(describedBy, invalid) => (
            <>
              <label className="sr-only" htmlFor="expiry-batch-periodLabel">
                Period label
              </label>
              <Input id="expiry-batch-periodLabel" name="periodLabel" required placeholder="period label, e.g. 2026-08" invalid={invalid} aria-describedby={describedBy} />
            </>
          )}
        </InlineForm>
        <InlineForm action={runReminderBatchAction} submitLabel="Run expiry reminder batch">
          {(describedBy, invalid) => (
            <>
              <label className="sr-only" htmlFor="reminder-batch-periodLabel">
                Period label
              </label>
              <Input id="reminder-batch-periodLabel" name="periodLabel" required placeholder="period label, e.g. 2026-08" invalid={invalid} aria-describedby={describedBy} />
              <label className="sr-only" htmlFor="reminder-batch-lookaheadDays">
                Lookahead days
              </label>
              <Input id="reminder-batch-lookaheadDays" name="lookaheadDays" type="number" defaultValue={30} placeholder="lookahead days" invalid={invalid} aria-describedby={describedBy} />
            </>
          )}
        </InlineForm>
      </div>
    </Section>
  );
}

// --- Development plan ---

function DevelopmentPlanSection({ developmentPlans, createAction, addPlanActionAction }: {
  developmentPlans: TrainingDevelopmentPlanRow[];
  createAction: BoundAction;
  addPlanActionAction: (planId: string) => BoundAction;
}) {
  return (
    <Section title="Development plans" description="Authored by HR or the employee's own direct manager; may link to a specific HRT-283 performance outcome.">
      <InlineForm action={createAction} submitLabel="Create plan">
        {(describedBy, invalid) => (
          <>
            <label className="sr-only" htmlFor="dev-plan-employeeId">
              Employee id
            </label>
            <Input id="dev-plan-employeeId" name="employeeId" required placeholder="employee id" invalid={invalid} aria-describedby={describedBy} />
            <label className="sr-only" htmlFor="dev-plan-title">
              Title
            </label>
            <Input id="dev-plan-title" name="title" required placeholder="title" invalid={invalid} aria-describedby={describedBy} />
            <label className="sr-only" htmlFor="dev-plan-cycleLabel">
              Cycle label
            </label>
            <Input id="dev-plan-cycleLabel" name="cycleLabel" placeholder="cycle label" invalid={invalid} aria-describedby={describedBy} />
          </>
        )}
      </InlineForm>
      {developmentPlans.length === 0 ? (
        <EmptyState title="No development plans yet" description="Create the first one above." />
      ) : (
        <ul className="flex flex-col gap-2 text-sm">
          {developmentPlans.map((p) => (
            <li key={p.id} className="flex flex-col gap-2 rounded border border-neutral-200 p-2">
              <div className="flex items-center justify-between">
                <span>{p.employeeFullName ?? p.employeeId} — {p.title}</span>
                <StatusBadge tone={p.status === "completed" ? "success" : p.status === "cancelled" ? "danger" : "info"} label={p.status} />
              </div>
              {p.status === "draft" || p.status === "active" ? (
                <details className="text-xs text-neutral-500">
                  <summary className="cursor-pointer">Add action</summary>
                  <InlineForm action={addPlanActionAction(p.id)} submitLabel="Add action">
                    {(describedBy, invalid) => (
                      <>
                        <label className="sr-only" htmlFor={`dev-plan-${p.id}-actionType`}>
                          Action type
                        </label>
                        <Select id={`dev-plan-${p.id}-actionType`} name="actionType" invalid={invalid} aria-describedby={describedBy}>
                          <option value="training">Training</option><option value="coaching">Coaching</option>
                          <option value="stretch_assignment">Stretch assignment</option><option value="certification">Certification</option><option value="other">Other</option>
                        </Select>
                        <label className="sr-only" htmlFor={`dev-plan-${p.id}-description`}>
                          Description
                        </label>
                        <Input id={`dev-plan-${p.id}-description`} name="description" required placeholder="description" invalid={invalid} aria-describedby={describedBy} />
                        <label className="sr-only" htmlFor={`dev-plan-${p.id}-targetDate`}>
                          Target date
                        </label>
                        <Input id={`dev-plan-${p.id}-targetDate`} name="targetDate" type="date" invalid={invalid} aria-describedby={describedBy} />
                      </>
                    )}
                  </InlineForm>
                </details>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </Section>
  );
}

// --- Restricted talent workspace ---

const CYCLE_NEXT_STATUS: Record<string, string> = { draft: "active", active: "closed" };

function TalentSection({
  talentCycles, talentAssignments, talentPools, poolMembersByPoolId, distributionByPoolId, successionCandidates,
  createCycleAction, transitionCycleAction, assignReviewerAction, reassignReviewerAction, createPoolAction, addPoolMemberAction, removePoolMemberAction,
  proposeCandidateAction, decideCandidateAction,
}: {
  talentCycles: TalentReviewCycleRow[];
  talentAssignments: TalentReviewAssignmentRow[];
  talentPools: TalentPoolRow[];
  poolMembersByPoolId: Record<string, TalentPoolMemberRow[]>;
  distributionByPoolId: Record<string, TalentPoolDistributionRow[]>;
  successionCandidates: TalentSuccessionCandidateRow[];
  createCycleAction: BoundAction;
  transitionCycleAction: (cycleId: string, expectedVersion: number, targetStatus: string) => BoundAction;
  assignReviewerAction: (cycleId: string) => BoundAction;
  reassignReviewerAction: (assignmentId: string) => BoundAction;
  createPoolAction: BoundAction;
  addPoolMemberAction: (poolId: string) => BoundAction;
  removePoolMemberAction: (memberId: string, expectedVersion: number) => BoundAction;
  proposeCandidateAction: BoundAction;
  decideCandidateAction: (candidateId: string, expectedVersion: number, decision: "confirm" | "withdraw") => BoundAction;
}) {
  const cycles = talentCycles;
  return (
    <Section
      title="Restricted talent workspace"
      description="HRS:Override only, plus the specific assigned reviewer for that one case ('restricted talent reviewers see assigned cases'). A viewer with neither sees empty sections below, not a redirect."
    >
      <InlineForm action={createCycleAction} submitLabel="Create talent review cycle">
        {(describedBy, invalid) => (
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <label className="sr-only" htmlFor="talent-cycle-name">
              Cycle name
            </label>
            <Input id="talent-cycle-name" name="name" required placeholder="cycle name" invalid={invalid} aria-describedby={describedBy} />
            <label className="sr-only" htmlFor="talent-cycle-periodLabel">
              Period label
            </label>
            <Input id="talent-cycle-periodLabel" name="periodLabel" required placeholder="period label" invalid={invalid} aria-describedby={describedBy} />
          </div>
        )}
      </InlineForm>

      {cycles.length === 0 ? (
        <EmptyState title="No visible talent review cycles" description="Either none exist yet, or you hold neither HRS:Override nor an assigned reviewer case." />
      ) : (
        <ul className="flex flex-col gap-2 text-sm">
          {cycles.map((c) => {
            const assignmentsForCycle = talentAssignments.filter((a) => a.cycleId === c.id);
            const nextStatus = CYCLE_NEXT_STATUS[c.status];
            return (
              <li key={c.id} className="flex flex-col gap-2 rounded border border-neutral-200 p-2">
                <div className="flex items-center justify-between">
                  <span>{c.name} ({c.periodLabel})</span>
                  <div className="flex items-center gap-2">
                    <StatusBadge tone={CYCLE_STATUS_TONE[c.status] ?? "neutral"} label={c.status} />
                    {nextStatus ? <TransitionCycleButton action={transitionCycleAction(c.id, c.recordVersion, nextStatus)} label={`Move to ${nextStatus}`} /> : null}
                  </div>
                </div>
                <details className="text-xs text-neutral-500">
                  <summary className="cursor-pointer">Assign reviewer</summary>
                  <InlineForm action={assignReviewerAction(c.id)} submitLabel="Assign">
                    {(describedBy, invalid) => (
                      <>
                        <label className="sr-only" htmlFor={`talent-cycle-${c.id}-subjectEmployeeId`}>
                          Subject employee id
                        </label>
                        <Input id={`talent-cycle-${c.id}-subjectEmployeeId`} name="subjectEmployeeId" required placeholder="subject employee id" invalid={invalid} aria-describedby={describedBy} />
                        <label className="sr-only" htmlFor={`talent-cycle-${c.id}-reviewerEmployeeId`}>
                          Reviewer employee id
                        </label>
                        <Input id={`talent-cycle-${c.id}-reviewerEmployeeId`} name="reviewerEmployeeId" required placeholder="reviewer employee id" invalid={invalid} aria-describedby={describedBy} />
                      </>
                    )}
                  </InlineForm>
                </details>
                <ul className="flex flex-col gap-1 text-xs text-neutral-600">
                  {assignmentsForCycle.map((a) => (
                    <li key={a.id} className="flex flex-col gap-1">
                      <div className="flex items-center justify-between">
                        <span>{a.subjectFullName ?? a.subjectEmployeeId} → reviewer {a.reviewerFullName ?? a.reviewerEmployeeId}</span>
                        <StatusBadge tone={a.status === "reassigned" ? "neutral" : "success"} label={a.status} />
                      </div>
                      {a.status === "active" ? (
                        <details>
                          <summary className="cursor-pointer">Reassign</summary>
                          <InlineForm action={reassignReviewerAction(a.id)} submitLabel="Reassign">
                            {(describedBy, invalid) => (
                              <>
                                <label className="sr-only" htmlFor={`talent-assignment-${a.id}-newReviewerEmployeeId`}>
                                  New reviewer employee id
                                </label>
                                <Input id={`talent-assignment-${a.id}-newReviewerEmployeeId`} name="newReviewerEmployeeId" required placeholder="new reviewer employee id" invalid={invalid} aria-describedby={describedBy} />
                                <label className="sr-only" htmlFor={`talent-assignment-${a.id}-reason`}>
                                  Reason
                                </label>
                                <Input id={`talent-assignment-${a.id}-reason`} name="reason" required placeholder="reason" invalid={invalid} aria-describedby={describedBy} />
                              </>
                            )}
                          </InlineForm>
                        </details>
                      ) : null}
                    </li>
                  ))}
                </ul>
              </li>
            );
          })}
        </ul>
      )}

      <InlineForm action={createPoolAction} submitLabel="Create talent pool">
        {(describedBy, invalid) => (
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <label className="sr-only" htmlFor="talent-pool-name">
              Pool name
            </label>
            <Input id="talent-pool-name" name="name" required placeholder="pool name" invalid={invalid} aria-describedby={describedBy} />
            <label className="sr-only" htmlFor="talent-pool-poolType">
              Pool type
            </label>
            <Select id="talent-pool-poolType" name="poolType" invalid={invalid} aria-describedby={describedBy}>
              <option value="high_potential">High potential</option><option value="successor">Successor</option><option value="critical_role">Critical role</option>
            </Select>
          </div>
        )}
      </InlineForm>

      {talentPools.length === 0 ? (
        <EmptyState title="No visible talent pools" description="Either none exist yet, or you lack HRS:Override for this tenant." />
      ) : (
        <ul className="flex flex-col gap-2 text-sm">
          {talentPools.map((p) => {
            const members = poolMembersByPoolId[p.id] ?? [];
            const distribution = distributionByPoolId[p.id] ?? [];
            return (
              <li key={p.id} className="flex flex-col gap-2 rounded border border-neutral-200 p-2">
                <div className="flex items-center justify-between">
                  <span>{p.name} ({p.poolType})</span>
                  <StatusBadge tone={p.status === "active" ? "success" : "neutral"} label={p.status} />
                </div>
                <details className="text-xs text-neutral-500">
                  <summary className="cursor-pointer">Add member</summary>
                  <InlineForm action={addPoolMemberAction(p.id)} submitLabel="Add member">
                    {(describedBy, invalid) => (
                      <>
                        <label className="sr-only" htmlFor={`talent-pool-${p.id}-employeeId`}>
                          Employee id
                        </label>
                        <Input id={`talent-pool-${p.id}-employeeId`} name="employeeId" required placeholder="employee id" invalid={invalid} aria-describedby={describedBy} />
                        <label className="sr-only" htmlFor={`talent-pool-${p.id}-addedReason`}>
                          Reason
                        </label>
                        <Input id={`talent-pool-${p.id}-addedReason`} name="addedReason" required placeholder="reason" invalid={invalid} aria-describedby={describedBy} />
                      </>
                    )}
                  </InlineForm>
                </details>
                <ul className="flex flex-col gap-1 text-xs text-neutral-600">
                  {members.map((m) => (
                    <li key={m.id} className="flex items-center justify-between gap-2">
                      <span>{m.employeeFullName ?? m.employeeId}</span>
                      <details>
                        <summary className="cursor-pointer">Remove</summary>
                        <InlineForm action={removePoolMemberAction(m.id, m.recordVersion)} submitLabel="Remove">
                          {(describedBy, invalid) => (
                            <>
                              <label className="sr-only" htmlFor={`talent-pool-member-${m.id}-removedReason`}>
                                Reason
                              </label>
                              <Input id={`talent-pool-member-${m.id}-removedReason`} name="removedReason" required placeholder="reason" invalid={invalid} aria-describedby={describedBy} />
                            </>
                          )}
                        </InlineForm>
                      </details>
                    </li>
                  ))}
                </ul>
                <p className="text-xs text-neutral-500">{members.length} active member(s)</p>
                {distribution.length > 0 ? (
                  <div className="overflow-x-auto">
                    <table className="w-full text-xs">
                      <caption className="sr-only">Pool distribution by department, k-anonymity floor k=5</caption>
                      <thead><tr className="text-left text-neutral-500"><th scope="col">Department</th><th scope="col">Members</th></tr></thead>
                      <tbody>
                        {distribution.map((d) => (
                          <tr key={d.departmentOrgUnitId ?? "none"}>
                            <td>{d.departmentName ?? "—"}</td>
                            <td>{d.suppressed ? "< 5 (suppressed)" : d.memberCount}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                ) : null}
              </li>
            );
          })}
        </ul>
      )}

      <InlineForm action={proposeCandidateAction} submitLabel="Propose succession candidate">
        {(describedBy, invalid) => (
          <>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
              <label className="sr-only" htmlFor="succession-positionId">
                Position id
              </label>
              <Input id="succession-positionId" name="positionId" required placeholder="position id" invalid={invalid} aria-describedby={describedBy} />
              <label className="sr-only" htmlFor="succession-candidateEmployeeId">
                Candidate employee id
              </label>
              <Input id="succession-candidateEmployeeId" name="candidateEmployeeId" required placeholder="candidate employee id" invalid={invalid} aria-describedby={describedBy} />
            </div>
            <label className="sr-only" htmlFor="succession-readiness">
              Readiness
            </label>
            <Select id="succession-readiness" name="readiness" invalid={invalid} aria-describedby={describedBy}>
              <option value="ready_now">Ready now</option><option value="ready_1_2_years">Ready in 1-2 years</option>
              <option value="ready_3_plus_years">Ready in 3+ years</option><option value="development_needed">Development needed</option>
            </Select>
            <label className="sr-only" htmlFor="succession-decisionReason">
              Reason
            </label>
            <Input id="succession-decisionReason" name="decisionReason" required placeholder="reason" invalid={invalid} aria-describedby={describedBy} />
          </>
        )}
      </InlineForm>

      {successionCandidates.length === 0 ? (
        <EmptyState title="No visible succession candidates" description="Either none exist yet, or you lack HRS:Override for this tenant." />
      ) : (
        <ul className="flex flex-col gap-2 text-sm">
          {successionCandidates.map((c) => (
            <li key={c.id} className="flex flex-col gap-2 rounded border border-neutral-200 p-2">
              <div className="flex items-center justify-between">
                <span>{c.candidateFullName ?? c.candidateEmployeeId} → {c.positionTitle ?? c.positionId} ({c.readiness})</span>
                <StatusBadge tone={CANDIDATE_STATUS_TONE[c.status] ?? "neutral"} label={c.status} />
              </div>
              {c.status === "proposed" ? (
                <div className="flex flex-wrap gap-2">
                  <DecideCandidateForm action={decideCandidateAction(c.id, c.recordVersion, "confirm")} label="Confirm" variant="primary" />
                  <DecideCandidateForm action={decideCandidateAction(c.id, c.recordVersion, "withdraw")} label="Withdraw" variant="destructive" />
                </div>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </Section>
  );
}

function TransitionCycleButton({ action, label }: { action: BoundAction; label: string }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  return (
    <form action={formAction}>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Working…">{label}</Button>
      <ErrorLine error={state.error} id={`${reactId}-error`} />
    </form>
  );
}

function DecideCandidateForm({ action, label, variant }: { action: BoundAction; label: string; variant: "primary" | "destructive" }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  return (
    <form action={formAction} className="flex items-center gap-2">
      <label className="sr-only" htmlFor={reactId}>
        Reason
      </label>
      <Input id={reactId} name="decisionReason" required placeholder="reason" invalid={Boolean(state.error)} aria-describedby={state.error ? errorId : undefined} />
      <Button type="submit" variant={variant} loading={pending} loadingLabel="Deciding…">{label}</Button>
      <ErrorLine error={state.error} id={errorId} />
    </form>
  );
}

export interface TrainingTalentAdminPanelProps {
  competencies: TrainingCompetencyRow[];
  courses: TrainingCourseRow[];
  courseVersionsByCourseId: Record<string, TrainingCourseVersionRow[]>;
  providers: TrainingProviderRow[];
  sessions: TrainingSessionRow[];
  pendingEnrollments: TrainingEnrollmentRow[];
  certificates: TrainingCertificateRow[];
  developmentPlans: TrainingDevelopmentPlanRow[];
  talentCycles: TalentReviewCycleRow[];
  talentAssignments: TalentReviewAssignmentRow[];
  talentPools: TalentPoolRow[];
  poolMembersByPoolId: Record<string, TalentPoolMemberRow[]>;
  distributionByPoolId: Record<string, TalentPoolDistributionRow[]>;
  successionCandidates: TalentSuccessionCandidateRow[];
  createCompetencyAction: BoundAction;
  publishCompetencyAction: (competencyId: string, expectedVersion: number) => BoundAction;
  createCourseAction: BoundAction;
  publishCourseVersionAction: (versionId: string, expectedVersion: number) => BoundAction;
  addCourseCompetencyAction: (courseId: string) => BoundAction;
  addPrerequisiteAction: (courseId: string) => BoundAction;
  createProviderAction: BoundAction;
  createSessionAction: BoundAction;
  cancelSessionAction: (sessionId: string, expectedVersion: number) => BoundAction;
  enrollEmployeeAction: (sessionId: string) => BoundAction;
  bulkAssignMandatoryAction: (sessionId: string) => BoundAction;
  decideEnrollmentAction: (enrollmentId: string, expectedVersion: number, decision: "approve" | "reject") => BoundAction;
  recordAttendanceAction: BoundAction;
  recordCompletionAction: BoundAction;
  recordAssessmentAction: BoundAction;
  issueCertificateAction: BoundAction;
  importCertificateAction: BoundAction;
  attachCertificateEvidenceAction: (certificateId: string, expectedVersion: number) => BoundAction;
  attachProviderEvidenceAction: (providerId: string, expectedVersion: number) => BoundAction;
  verifyCertificateAction: (certificateId: string, expectedVersion: number) => BoundAction;
  revokeCertificateAction: (certificateId: string, expectedVersion: number) => BoundAction;
  runExpiryBatchAction: BoundAction;
  runReminderBatchAction: BoundAction;
  createDevelopmentPlanAction: BoundAction;
  addPlanActionAction: (planId: string) => BoundAction;
  createTalentReviewCycleAction: BoundAction;
  transitionCycleStatusAction: (cycleId: string, expectedVersion: number, targetStatus: string) => BoundAction;
  assignReviewerAction: (cycleId: string) => BoundAction;
  reassignReviewerAction: (assignmentId: string) => BoundAction;
  createTalentPoolAction: BoundAction;
  addPoolMemberAction: (poolId: string) => BoundAction;
  removePoolMemberAction: (memberId: string, expectedVersion: number) => BoundAction;
  proposeSuccessionCandidateAction: BoundAction;
  decideSuccessionCandidateAction: (candidateId: string, expectedVersion: number, decision: "confirm" | "withdraw") => BoundAction;
}

export function TrainingTalentAdminPanel(props: TrainingTalentAdminPanelProps) {
  return (
    <div className="flex flex-col gap-6 p-4">
      <h1 className="text-xl font-semibold text-neutral-900">Training and Talent</h1>
      <CompetencySection competencies={props.competencies} createAction={props.createCompetencyAction} publishAction={props.publishCompetencyAction} />
      <CourseSection
        courses={props.courses} courseVersionsByCourseId={props.courseVersionsByCourseId} createAction={props.createCourseAction}
        publishVersionAction={props.publishCourseVersionAction} addCompetencyAction={props.addCourseCompetencyAction} addPrerequisiteAction={props.addPrerequisiteAction}
      />
      <ProviderSessionSection
        providers={props.providers} sessions={props.sessions} courses={props.courses} courseVersionsByCourseId={props.courseVersionsByCourseId}
        attachProviderEvidenceAction={props.attachProviderEvidenceAction}
        createProviderAction={props.createProviderAction} createSessionAction={props.createSessionAction} cancelSessionAction={props.cancelSessionAction}
        enrollEmployeeAction={props.enrollEmployeeAction} bulkAssignAction={props.bulkAssignMandatoryAction}
      />
      <EnrollmentQueueSection
        pendingEnrollments={props.pendingEnrollments} decideAction={props.decideEnrollmentAction} recordAttendanceAction={props.recordAttendanceAction}
        recordCompletionAction={props.recordCompletionAction} recordAssessmentAction={props.recordAssessmentAction}
      />
      <CertificateSection
        certificates={props.certificates} issueAction={props.issueCertificateAction} importAction={props.importCertificateAction}
        attachEvidenceAction={props.attachCertificateEvidenceAction}
        verifyAction={props.verifyCertificateAction} revokeAction={props.revokeCertificateAction} runExpiryBatchAction={props.runExpiryBatchAction}
        runReminderBatchAction={props.runReminderBatchAction}
      />
      <DevelopmentPlanSection developmentPlans={props.developmentPlans} createAction={props.createDevelopmentPlanAction} addPlanActionAction={props.addPlanActionAction} />
      <TalentSection
        talentCycles={props.talentCycles} talentAssignments={props.talentAssignments} talentPools={props.talentPools} poolMembersByPoolId={props.poolMembersByPoolId}
        distributionByPoolId={props.distributionByPoolId} successionCandidates={props.successionCandidates}
        createCycleAction={props.createTalentReviewCycleAction} transitionCycleAction={props.transitionCycleStatusAction} assignReviewerAction={props.assignReviewerAction}
        reassignReviewerAction={props.reassignReviewerAction}
        createPoolAction={props.createTalentPoolAction} addPoolMemberAction={props.addPoolMemberAction} removePoolMemberAction={props.removePoolMemberAction}
        proposeCandidateAction={props.proposeSuccessionCandidateAction}
        decideCandidateAction={props.decideSuccessionCandidateAction}
      />
    </div>
  );
}
