import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createTrainingCompetency,
  publishTrainingCompetency,
  createTrainingCourse,
  createTrainingCourseVersion,
  publishTrainingCourseVersion,
  addTrainingCoursePrerequisite,
  createTrainingSession,
  cancelTrainingSession,
  enrollSelfInTrainingSession,
  enrollEmployeeInTrainingSession,
  bulkAssignMandatoryTrainingSession,
  decideTrainingEnrollment,
  cancelTrainingEnrollment,
  recordTrainingAssessment,
  issueTrainingCertificate,
  attachTrainingCertificateEvidence,
  revokeTrainingCertificate,
  runTrainingCertificateExpiryBatch,
  runTrainingCertificateExpiryReminderBatch,
  createTrainingDevelopmentPlan,
  addTrainingDevelopmentPlanAction,
  assignTalentReviewer,
  reassignTalentReviewer,
  submitTalentReview,
  createTalentPool,
  addTalentPoolMember,
  proposeSuccessionCandidate,
  decideSuccessionCandidate,
  TrainingTalentMutationError,
  type TrainingTalentMutationRpcClient,
} from "./training-talent.ts";

const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "323e4567-e89b-12d3-a456-426614174000";
const ID_3 = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: TrainingTalentMutationRpcClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as TrainingTalentMutationRpcClient;
  return { client, calls };
}

describe("TrainingTalentMutationError classification", () => {
  test("recognizes a known error-code prefix", () => {
    const err = new TrainingTalentMutationError("training_prerequisite_not_met: employee has not completed every prerequisite");
    assert.equal(err.code, "training_prerequisite_not_met");
  });

  test("recognizes self_decision_not_permitted", () => {
    const err = new TrainingTalentMutationError("self_decision_not_permitted: an actor may not decide their own enrollment request");
    assert.equal(err.code, "self_decision_not_permitted");
  });

  test("falls back to unknown for an unrecognized prefix", () => {
    const err = new TrainingTalentMutationError("some_other_raw_postgres_error: detail");
    assert.equal(err.code, "unknown");
  });
});

describe("competency / course mutations", () => {
  test("createTrainingCompetency forwards every field and parses the result", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, code: "safety_basics", name: "Safety Basics", description: null, category: "safety", status: "draft", record_version: 1 }, error: null });
    const row = await createTrainingCompetency(client, { tenantId: ID_2, code: "safety_basics", name: "Safety Basics", description: null, category: "safety", actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(calls[0]?.fn, "create_training_competency");
    assert.equal(row.status, "draft");
  });

  test("publishTrainingCompetency forwards expected_version", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, code: "x", name: "X", description: null, category: null, status: "published", record_version: 2 }, error: null });
    await publishTrainingCompetency(client, { competencyId: ID_1, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(calls[0]?.args.p_expected_version, 1);
  });

  test("createTrainingCourse and createTrainingCourseVersion forward every version-shape field", async () => {
    const { client: c1, calls: calls1 } = fakeClient({ data: { id: ID_1, code: "safety_101", name: "Safety 101", category: null, status: "active" }, error: null });
    await createTrainingCourse(c1, { tenantId: ID_2, code: "safety_101", name: "Safety 101", category: null, actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(calls1[0]?.fn, "create_training_course");

    const { client: c2, calls: calls2 } = fakeClient({
      data: {
        id: ID_1, course_id: ID_2, version_number: 1, status: "draft", description: null, delivery_mode: "in_person", duration_hours: 4,
        is_mandatory: false, requires_enrollment_approval: false, requires_assessment: true, passing_score: 70, issues_certificate: true,
        certificate_validity_months: 24, record_version: 1,
      },
      error: null,
    });
    const v = await createTrainingCourseVersion(c2, {
      courseId: ID_2, description: null, deliveryMode: "in_person", durationHours: 4, isMandatory: false, requiresEnrollmentApproval: false,
      requiresAssessment: true, passingScore: 70, issuesCertificate: true, certificateValidityMonths: 24, actorAuthUserId: ACTOR_ID, actorLabel: "hr",
    });
    assert.equal(calls2[0]?.args.p_passing_score, 70);
    assert.equal(v.requiresAssessment, true);
  });

  test("publishTrainingCourseVersion rejects with a mapped error on an already-published version", async () => {
    const { client } = fakeClient({ data: null, error: { message: "invalid_transition: version x is published not draft" } });
    await assert.rejects(() => publishTrainingCourseVersion(client, { versionId: ID_1, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "hr" }), TrainingTalentMutationError);
  });

  test("addTrainingCoursePrerequisite forwards both course ids", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, course_id: ID_2, prerequisite_course_id: ID_3 }, error: null });
    await addTrainingCoursePrerequisite(client, { courseId: ID_2, prerequisiteCourseId: ID_3, actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(calls[0]?.args.p_course_id, ID_2);
    assert.equal(calls[0]?.args.p_prerequisite_course_id, ID_3);
  });
});

describe("session / enrollment mutations", () => {
  test("createTrainingSession forwards dates and capacity", async () => {
    const { client, calls } = fakeClient({
      data: { id: ID_1, course_version_id: ID_2, provider_id: null, session_code: "sess_a", location: null, start_at: "2026-09-01T00:00:00Z", end_at: "2026-09-01T04:00:00Z", capacity: 10, status: "scheduled", record_version: 1 },
      error: null,
    });
    await createTrainingSession(client, { tenantId: ID_3, courseVersionId: ID_2, providerId: null, sessionCode: "sess_a", location: null, startAt: "2026-09-01T00:00:00Z", endAt: "2026-09-01T04:00:00Z", capacity: 10, actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(calls[0]?.args.p_capacity, 10);
  });

  test("cancelTrainingSession requires a reason field forwarded verbatim", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, course_version_id: ID_2, provider_id: null, session_code: "s", location: null, start_at: "x", end_at: "y", capacity: 5, status: "cancelled", cancel_reason: "venue unavailable", record_version: 2 }, error: null });
    await cancelTrainingSession(client, { sessionId: ID_1, expectedVersion: 1, reason: "venue unavailable", actorAuthUserId: ACTOR_ID, actorLabel: "talentadmin" });
    assert.equal(calls[0]?.args.p_reason, "venue unavailable");
  });

  test("enrollSelfInTrainingSession never takes an employee_id parameter -- self-resolved server-side", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, session_id: ID_2, course_version_id: ID_3, status: "enrolled", enrollment_source: "self", record_version: 1 }, error: null });
    await enrollSelfInTrainingSession(client, { tenantId: ID_3, sessionId: ID_2, actorAuthUserId: ACTOR_ID, actorLabel: "emp1" });
    assert.equal(Object.prototype.hasOwnProperty.call(calls[0]?.args, "p_employee_id"), false);
  });

  test("enrollEmployeeInTrainingSession forwards an explicit employee_id", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, session_id: ID_2, course_version_id: ID_3, status: "pending_approval", enrollment_source: "hr_assigned", record_version: 1 }, error: null });
    await enrollEmployeeInTrainingSession(client, { tenantId: ID_3, sessionId: ID_2, employeeId: ID_1, actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(calls[0]?.args.p_employee_id, ID_1);
  });

  test("bulkAssignMandatoryTrainingSession maps assigned_count/skipped_count", async () => {
    const { client } = fakeClient({ data: { assigned_count: 5, skipped_count: 0 }, error: null });
    const result = await bulkAssignMandatoryTrainingSession(client, { tenantId: ID_1, sessionId: ID_2, actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(result.assignedCount, 5);
    assert.equal(result.skippedCount, 0);
  });

  test("decideTrainingEnrollment rejects self-decision with a mapped error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "self_decision_not_permitted: an actor may not decide their own enrollment request" } });
    await assert.rejects(
      () => decideTrainingEnrollment(client, { enrollmentId: ID_1, expectedVersion: 1, decision: "approve", decisionReason: null, actorAuthUserId: ACTOR_ID, actorLabel: "emp2" }),
      (err: unknown) => err instanceof TrainingTalentMutationError && err.code === "self_decision_not_permitted",
    );
  });

  test("cancelTrainingEnrollment forwards a mandatory reason", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, session_id: ID_2, course_version_id: ID_3, status: "cancelled", enrollment_source: "self", record_version: 2 }, error: null });
    await cancelTrainingEnrollment(client, { enrollmentId: ID_1, expectedVersion: 1, reason: "schedule conflict", actorAuthUserId: ACTOR_ID, actorLabel: "mgr1" });
    assert.equal(calls[0]?.args.p_reason, "schedule conflict");
  });
});

describe("assessment / certificate mutations", () => {
  test("recordTrainingAssessment forwards score/max_score and parses computed passed", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, enrollment_id: ID_2, employee_id: ID_3, course_version_id: ID_1, attempt_number: 1, score: 85, max_score: 100, passed: true, assessed_by: "hr", assessed_at: "2026-08-01T00:00:00Z", notes: null, record_version: 1 }, error: null });
    const row = await recordTrainingAssessment(client, { enrollmentId: ID_2, score: 85, maxScore: 100, notes: null, actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(calls[0]?.args.p_score, 85);
    assert.equal(row.passed, true);
  });

  test("issueTrainingCertificate forwards enrollment/course-version linkage", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, course_version_id: ID_2, external_course_name: null, certificate_number: "CERT-1", issued_at: "2026-01-01", expiry_date: null, status: "issued", source: "internal_completion", verification_status: "verified", evidence_file_id: null, record_version: 1 }, error: null });
    await issueTrainingCertificate(client, { tenantId: ID_3, employeeId: ID_1, courseVersionId: ID_2, enrollmentId: null, certificateNumber: "CERT-1", issuedAt: "2026-01-01", expiryDate: null, actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(calls[0]?.args.p_course_version_id, ID_2);
  });

  test("attachTrainingCertificateEvidence rejects an infected file with a mapped error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "evidence_file_infected: file x failed malware scanning" } });
    await assert.rejects(
      () => attachTrainingCertificateEvidence(client, { certificateId: ID_1, expectedVersion: 1, evidenceFileId: ID_2, actorAuthUserId: ACTOR_ID, actorLabel: "hr" }),
      (err: unknown) => err instanceof TrainingTalentMutationError && err.code === "evidence_file_infected",
    );
  });

  test("revokeTrainingCertificate forwards a mandatory reason", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, course_version_id: ID_2, external_course_name: null, certificate_number: "CERT-1", issued_at: "2026-01-01", expiry_date: null, status: "revoked", source: "internal_completion", verification_status: "verified", evidence_file_id: null, record_version: 2 }, error: null });
    await revokeTrainingCertificate(client, { certificateId: ID_1, expectedVersion: 1, reason: "issued in error", actorAuthUserId: ACTOR_ID, actorLabel: "talentadmin" });
    assert.equal(calls[0]?.args.p_reason, "issued in error");
  });

  test("runTrainingCertificateExpiryBatch and reminder batch map their return shapes", async () => {
    const { client: c1 } = fakeClient({ data: { expired_count: 2, job_id: ID_1 }, error: null });
    const r1 = await runTrainingCertificateExpiryBatch(c1, { tenantId: ID_2, asOfDate: "2026-08-01", periodLabel: "p1", actorAuthUserId: ACTOR_ID, actorLabel: "talentadmin" });
    assert.equal(r1.expiredCount, 2);

    const { client: c2 } = fakeClient({ data: { reminded_count: 1, skipped_count: 0, job_id: ID_1 }, error: null });
    const r2 = await runTrainingCertificateExpiryReminderBatch(c2, { tenantId: ID_2, asOfDate: "2026-08-01", lookaheadDays: 30, periodLabel: "p1", actorAuthUserId: ACTOR_ID, actorLabel: "talentadmin" });
    assert.equal(r2.remindedCount, 1);
  });
});

describe("development plan mutations", () => {
  test("createTrainingDevelopmentPlan forwards linked_performance_outcome_id", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, employee_id: ID_2, title: "Plan", cycle_label: null, status: "draft", linked_performance_outcome_id: ID_3, record_version: 1 }, error: null });
    await createTrainingDevelopmentPlan(client, { tenantId: ID_1, employeeId: ID_2, title: "Plan", cycleLabel: null, linkedPerformanceOutcomeId: ID_3, actorAuthUserId: ACTOR_ID, actorLabel: "mgr1" });
    assert.equal(calls[0]?.args.p_linked_performance_outcome_id, ID_3);
  });

  test("addTrainingDevelopmentPlanAction forwards action_type/description", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, plan_id: ID_2, action_type: "certification", description: "Complete Safety 201", linked_course_id: null, target_date: null, status: "planned", completed_note: null, completed_at: null, record_version: 1 }, error: null });
    await addTrainingDevelopmentPlanAction(client, { planId: ID_2, actionType: "certification", description: "Complete Safety 201", linkedCourseId: null, targetDate: null, actorAuthUserId: ACTOR_ID, actorLabel: "mgr1" });
    assert.equal(calls[0]?.args.p_action_type, "certification");
  });
});

describe("restricted talent mutations", () => {
  test("assignTalentReviewer rejects self-assignment with a mapped error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "invalid_assignee: a reviewer may not be assigned to their own case" } });
    await assert.rejects(
      () => assignTalentReviewer(client, { cycleId: ID_1, subjectEmployeeId: ID_2, reviewerEmployeeId: ID_2, actorAuthUserId: ACTOR_ID, actorLabel: "talentadmin" }),
      (err: unknown) => err instanceof TrainingTalentMutationError && err.code === "invalid_assignee",
    );
  });

  test("reassignTalentReviewer forwards a mandatory reason", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, cycle_id: ID_2, subject_employee_id: ID_3, reviewer_employee_id: ID_1, status: "active", record_version: 1 }, error: null });
    await reassignTalentReviewer(client, { assignmentId: ID_1, newReviewerEmployeeId: ID_3, reason: "conflict of interest", actorAuthUserId: ACTOR_ID, actorLabel: "talentadmin" });
    assert.equal(calls[0]?.args.p_reason, "conflict of interest");
  });

  test("submitTalentReview forwards potential_rating/risk_of_loss", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, cycle_id: ID_2, subject_employee_id: ID_3, assignment_id: ID_1, potential_rating: "high", readiness_note: null, risk_of_loss: "medium", status: "submitted", submitted_at: "2026-08-01T00:00:00Z", record_version: 2 }, error: null });
    await submitTalentReview(client, { reviewId: ID_1, expectedVersion: 1, potentialRating: "high", readinessNote: null, riskOfLoss: "medium", actorAuthUserId: ACTOR_ID, actorLabel: "reviewer1" });
    assert.equal(calls[0]?.args.p_potential_rating, "high");
  });

  test("createTalentPool and addTalentPoolMember both require HRS:Override -- a denial surfaces as a mapped error", async () => {
    const { client: c1 } = fakeClient({ data: null, error: { message: "insufficient_authority: identity x lacks HRS:Override for tenant y" } });
    await assert.rejects(() => createTalentPool(c1, { tenantId: ID_1, name: "HiPo", description: null, poolType: "high_potential", actorAuthUserId: ACTOR_ID, actorLabel: "hr" }), TrainingTalentMutationError);

    const { client: c2, calls } = fakeClient({ data: { id: ID_1, pool_id: ID_2, employee_id: ID_3, status: "active", added_reason: "strong potential", added_at: "2026-08-01T00:00:00Z", record_version: 1 }, error: null });
    await addTalentPoolMember(c2, { poolId: ID_2, employeeId: ID_3, addedReason: "strong potential", actorAuthUserId: ACTOR_ID, actorLabel: "talentadmin" });
    assert.equal(calls[0]?.args.p_added_reason, "strong potential");
  });

  test("proposeSuccessionCandidate and decideSuccessionCandidate both forward a mandatory reason", async () => {
    const { client: c1, calls: calls1 } = fakeClient({ data: { id: ID_1, position_id: ID_2, candidate_employee_id: ID_3, readiness: "ready_1_2_years", decision_reason: "strong performer", status: "proposed", record_version: 1 }, error: null });
    await proposeSuccessionCandidate(c1, { tenantId: ID_1, positionId: ID_2, candidateEmployeeId: ID_3, readiness: "ready_1_2_years", decisionReason: "strong performer", actorAuthUserId: ACTOR_ID, actorLabel: "talentadmin" });
    assert.equal(calls1[0]?.args.p_decision_reason, "strong performer");

    const { client: c2 } = fakeClient({ data: null, error: { message: "self_decision_not_permitted: an actor may not decide their own succession candidacy" } });
    await assert.rejects(
      () => decideSuccessionCandidate(c2, { candidateId: ID_1, expectedVersion: 1, decision: "confirm", decisionReason: "self-decided", actorAuthUserId: ACTOR_ID, actorLabel: "emp1" }),
      (err: unknown) => err instanceof TrainingTalentMutationError && err.code === "self_decision_not_permitted",
    );
  });
});
