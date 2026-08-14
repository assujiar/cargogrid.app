"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
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

function ErrorLine({ error }: { error: string | null }) {
  return error ? <p role="alert" className="text-xs text-danger">{error}</p> : null;
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

function InlineForm({ action, children, submitLabel, pendingLabel }: { action: BoundAction; children: React.ReactNode; submitLabel: string; pendingLabel?: string }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2">
      {children}
      <Button type="submit" variant="primary" loading={pending} loadingLabel={pendingLabel ?? "Working…"}>{submitLabel}</Button>
      <ErrorLine error={state.error} />
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
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
          <label className="text-xs text-neutral-500">Code<input name="code" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="e.g. safety_basics" /></label>
          <label className="text-xs text-neutral-500">Name<input name="name" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" /></label>
          <label className="text-xs text-neutral-500">Category<input name="category" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" /></label>
        </div>
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
  return (
    <form action={formAction}>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Publishing…">Publish</Button>
      <ErrorLine error={state.error} />
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
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
          <label className="text-xs text-neutral-500">Code<input name="code" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="e.g. safety_101" /></label>
          <label className="text-xs text-neutral-500">Name<input name="name" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" /></label>
          <label className="text-xs text-neutral-500">Category<input name="category" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" /></label>
        </div>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <label className="text-xs text-neutral-500">
            Delivery mode
            <select name="deliveryMode" defaultValue="in_person" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
              <option value="in_person">In person</option><option value="virtual">Virtual</option><option value="e_learning">E-learning</option><option value="blended">Blended</option>
            </select>
          </label>
          <label className="text-xs text-neutral-500">Description<input name="description" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" /></label>
        </div>
        <div className="flex flex-wrap gap-4 text-xs text-neutral-600">
          <label className="flex items-center gap-1"><input type="checkbox" name="isMandatory" /> Mandatory compliance training</label>
          <label className="flex items-center gap-1"><input type="checkbox" name="requiresEnrollmentApproval" /> Requires enrollment approval</label>
          <label className="flex items-center gap-1"><input type="checkbox" name="requiresAssessment" /> Requires assessment</label>
          <label className="flex items-center gap-1"><input type="checkbox" name="issuesCertificate" /> Issues a certificate</label>
        </div>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <label className="text-xs text-neutral-500">Passing score (if assessed)<input name="passingScore" type="number" defaultValue={70} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" /></label>
          <label className="text-xs text-neutral-500">Certificate validity (months)<input name="certificateValidityMonths" type="number" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" /></label>
        </div>
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
                    <input name="competencyId" required placeholder="competency id" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
                  </InlineForm>
                </details>
                <details className="text-xs text-neutral-500">
                  <summary className="cursor-pointer">Add prerequisite (by course id)</summary>
                  <InlineForm action={addPrerequisiteAction(course.id)} submitLabel="Add prerequisite">
                    <input name="prerequisiteCourseId" required placeholder="prerequisite course id" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
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

function ProviderSessionSection({ providers, sessions, courses, courseVersionsByCourseId, createProviderAction, createSessionAction, cancelSessionAction, enrollEmployeeAction, bulkAssignAction }: {
  providers: TrainingProviderRow[];
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
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <label className="text-xs text-neutral-500">Name<input name="name" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" /></label>
          <label className="text-xs text-neutral-500">
            Type
            <select name="providerType" defaultValue="internal" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
              <option value="internal">Internal</option><option value="external">External</option>
            </select>
          </label>
        </div>
      </InlineForm>

      <InlineForm action={createSessionAction} submitLabel="Schedule session">
        <label className="text-xs text-neutral-500">
          Published course version
          <select name="courseVersionId" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
            <option value="">Select…</option>
            {publishedVersions.map(({ course, version }) => (
              <option key={version.id} value={version.id}>{course.code} v{version.versionNumber}</option>
            ))}
          </select>
        </label>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <label className="text-xs text-neutral-500">
            Provider
            <select name="providerId" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
              <option value="">None</option>
              {providers.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </label>
          <label className="text-xs text-neutral-500">Session code<input name="sessionCode" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" /></label>
        </div>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
          <label className="text-xs text-neutral-500">Start<input name="startAt" type="datetime-local" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" /></label>
          <label className="text-xs text-neutral-500">End<input name="endAt" type="datetime-local" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" /></label>
          <label className="text-xs text-neutral-500">Capacity<input name="capacity" type="number" min={1} required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" /></label>
        </div>
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
                      <input name="employeeId" required placeholder="employee id" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
                    </InlineForm>
                  </details>
                  <BareActionButton action={bulkAssignAction(s.id)} label="Bulk-assign all (mandatory sessions only)" />
                  <details className="text-xs text-neutral-500">
                    <summary className="cursor-pointer">Cancel session</summary>
                    <InlineForm action={cancelSessionAction(s.id, s.recordVersion)} submitLabel="Cancel session">
                      <input name="reason" required placeholder="reason" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
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
  return (
    <form action={formAction}>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Working…">{label}</Button>
      <ErrorLine error={state.error} />
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
  return (
    <form action={formAction}>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Approving…">Approve</Button>
      <ErrorLine error={state.error} />
    </form>
  );
}

function DecideRejectForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex items-center gap-2">
      <input name="decisionReason" required placeholder="reject reason" className="rounded border border-neutral-300 p-2 text-sm" />
      <Button type="submit" variant="destructive" loading={pending} loadingLabel="Rejecting…">Reject</Button>
      <ErrorLine error={state.error} />
    </form>
  );
}

function AttendanceForm({ recordAttendanceAction }: { recordAttendanceAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(recordAttendanceAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-center gap-2 text-xs">
      <input name="enrollmentId" required placeholder="enrollment id" className="rounded border border-neutral-300 p-2 text-sm" />
      <label className="flex items-center gap-1"><input type="checkbox" name="attended" defaultChecked /> attended</label>
      <input name="hoursAttended" placeholder="hours" className="w-20 rounded border border-neutral-300 p-2 text-sm" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Recording…">Record attendance</Button>
      <ErrorLine error={state.error} />
    </form>
  );
}

function CompletionForm({ recordCompletionAction }: { recordCompletionAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(recordCompletionAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-center gap-2 text-xs">
      <input name="enrollmentId" required placeholder="enrollment id" className="rounded border border-neutral-300 p-2 text-sm" />
      <input name="expectedVersion" type="number" required placeholder="version" className="w-20 rounded border border-neutral-300 p-2 text-sm" />
      <select name="completionStatus" className="rounded border border-neutral-300 p-2 text-sm">
        <option value="completed">Completed</option><option value="failed">Failed</option><option value="no_show">No-show</option>
      </select>
      <input name="notes" placeholder="notes" className="rounded border border-neutral-300 p-2 text-sm" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Recording…">Record completion</Button>
      <ErrorLine error={state.error} />
    </form>
  );
}

function AssessmentForm({ recordAssessmentAction }: { recordAssessmentAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(recordAssessmentAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-center gap-2 text-xs">
      <input name="enrollmentId" required placeholder="enrollment id" className="rounded border border-neutral-300 p-2 text-sm" />
      <input name="score" type="number" required placeholder="score" className="w-20 rounded border border-neutral-300 p-2 text-sm" />
      <input name="maxScore" type="number" defaultValue={100} placeholder="max score" className="w-24 rounded border border-neutral-300 p-2 text-sm" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Recording…">Record assessment</Button>
      <ErrorLine error={state.error} />
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
    <Section title="Certificates" description="Certificate evidence files are private and malware-scanned before attach (PLT-128); provider evidence is not yet a built capability (disclosed in the build log). Expiry/reminder are real durable jobs (PLT-131/132).">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <InlineForm action={issueAction} submitLabel="Issue certificate">
          <input name="employeeId" required placeholder="employee id" className="rounded border border-neutral-300 p-2 text-sm" />
          <input name="courseVersionId" required placeholder="course version id" className="rounded border border-neutral-300 p-2 text-sm" />
          <input name="certificateNumber" placeholder="certificate number" className="rounded border border-neutral-300 p-2 text-sm" />
          <label className="text-xs text-neutral-500">Issued<input name="issuedAt" type="date" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" /></label>
          <label className="text-xs text-neutral-500">Expires<input name="expiryDate" type="date" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" /></label>
        </InlineForm>
        <InlineForm action={importAction} submitLabel="Import historical certificate">
          <input name="employeeId" required placeholder="employee id" className="rounded border border-neutral-300 p-2 text-sm" />
          <input name="externalCourseName" required placeholder="external course name" className="rounded border border-neutral-300 p-2 text-sm" />
          <input name="certificateNumber" placeholder="certificate number" className="rounded border border-neutral-300 p-2 text-sm" />
          <label className="text-xs text-neutral-500">Issued<input name="issuedAt" type="date" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" /></label>
          <label className="text-xs text-neutral-500">Expires<input name="expiryDate" type="date" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" /></label>
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
                      <input name="evidenceFileId" required placeholder="evidence file id (malware-scanned, PLT-128)" className="rounded border border-neutral-300 p-2 text-sm" />
                    </InlineForm>
                  </details>
                ) : null}
                {c.verificationStatus === "unverified" ? <PublishButton action={verifyAction(c.id, c.recordVersion)} /> : null}
                {c.status !== "revoked" ? (
                  <details className="text-xs">
                    <summary className="cursor-pointer">Revoke</summary>
                    <InlineForm action={revokeAction(c.id, c.recordVersion)} submitLabel="Revoke">
                      <input name="reason" required placeholder="reason" className="rounded border border-neutral-300 p-2 text-sm" />
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
          <input name="periodLabel" required placeholder="period label, e.g. 2026-08" className="rounded border border-neutral-300 p-2 text-sm" />
        </InlineForm>
        <InlineForm action={runReminderBatchAction} submitLabel="Run expiry reminder batch">
          <input name="periodLabel" required placeholder="period label, e.g. 2026-08" className="rounded border border-neutral-300 p-2 text-sm" />
          <input name="lookaheadDays" type="number" defaultValue={30} placeholder="lookahead days" className="rounded border border-neutral-300 p-2 text-sm" />
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
        <input name="employeeId" required placeholder="employee id" className="rounded border border-neutral-300 p-2 text-sm" />
        <input name="title" required placeholder="title" className="rounded border border-neutral-300 p-2 text-sm" />
        <input name="cycleLabel" placeholder="cycle label" className="rounded border border-neutral-300 p-2 text-sm" />
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
                    <select name="actionType" className="rounded border border-neutral-300 p-2 text-sm">
                      <option value="training">Training</option><option value="coaching">Coaching</option>
                      <option value="stretch_assignment">Stretch assignment</option><option value="certification">Certification</option><option value="other">Other</option>
                    </select>
                    <input name="description" required placeholder="description" className="rounded border border-neutral-300 p-2 text-sm" />
                    <input name="targetDate" type="date" className="rounded border border-neutral-300 p-2 text-sm" />
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
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <input name="name" required placeholder="cycle name" className="rounded border border-neutral-300 p-2 text-sm" />
          <input name="periodLabel" required placeholder="period label" className="rounded border border-neutral-300 p-2 text-sm" />
        </div>
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
                    <input name="subjectEmployeeId" required placeholder="subject employee id" className="rounded border border-neutral-300 p-2 text-sm" />
                    <input name="reviewerEmployeeId" required placeholder="reviewer employee id" className="rounded border border-neutral-300 p-2 text-sm" />
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
                            <input name="newReviewerEmployeeId" required placeholder="new reviewer employee id" className="rounded border border-neutral-300 p-2 text-sm" />
                            <input name="reason" required placeholder="reason" className="rounded border border-neutral-300 p-2 text-sm" />
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
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <input name="name" required placeholder="pool name" className="rounded border border-neutral-300 p-2 text-sm" />
          <select name="poolType" className="rounded border border-neutral-300 p-2 text-sm">
            <option value="high_potential">High potential</option><option value="successor">Successor</option><option value="critical_role">Critical role</option>
          </select>
        </div>
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
                    <input name="employeeId" required placeholder="employee id" className="rounded border border-neutral-300 p-2 text-sm" />
                    <input name="addedReason" required placeholder="reason" className="rounded border border-neutral-300 p-2 text-sm" />
                  </InlineForm>
                </details>
                <ul className="flex flex-col gap-1 text-xs text-neutral-600">
                  {members.map((m) => (
                    <li key={m.id} className="flex items-center justify-between gap-2">
                      <span>{m.employeeFullName ?? m.employeeId}</span>
                      <details>
                        <summary className="cursor-pointer">Remove</summary>
                        <InlineForm action={removePoolMemberAction(m.id, m.recordVersion)} submitLabel="Remove">
                          <input name="removedReason" required placeholder="reason" className="rounded border border-neutral-300 p-2 text-sm" />
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
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <input name="positionId" required placeholder="position id" className="rounded border border-neutral-300 p-2 text-sm" />
          <input name="candidateEmployeeId" required placeholder="candidate employee id" className="rounded border border-neutral-300 p-2 text-sm" />
        </div>
        <select name="readiness" className="rounded border border-neutral-300 p-2 text-sm">
          <option value="ready_now">Ready now</option><option value="ready_1_2_years">Ready in 1-2 years</option>
          <option value="ready_3_plus_years">Ready in 3+ years</option><option value="development_needed">Development needed</option>
        </select>
        <input name="decisionReason" required placeholder="reason" className="rounded border border-neutral-300 p-2 text-sm" />
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
  return (
    <form action={formAction}>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Working…">{label}</Button>
      <ErrorLine error={state.error} />
    </form>
  );
}

function DecideCandidateForm({ action, label, variant }: { action: BoundAction; label: string; variant: "primary" | "destructive" }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex items-center gap-2">
      <input name="decisionReason" required placeholder="reason" className="rounded border border-neutral-300 p-2 text-sm" />
      <Button type="submit" variant={variant} loading={pending} loadingLabel="Deciding…">{label}</Button>
      <ErrorLine error={state.error} />
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
