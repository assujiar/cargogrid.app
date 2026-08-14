import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseTrainingCompetencyRow,
  parseTrainingCourseVersionRow,
  parseTrainingCourseCompetencyRow,
  parseTrainingSessionRow,
  parseTrainingEnrollmentRow,
  parseTrainingAssessmentRow,
  parseTrainingCertificateRow,
  parseTrainingCertificateExpiryReminderRow,
  parseTrainingDevelopmentPlanRow,
  parseTalentReviewAssignmentRow,
  parseTalentReviewRow,
  parseTalentPoolMemberRow,
  parseTalentSuccessionCandidateRow,
  parseTalentPoolDistributionRow,
} from "./training-talent.ts";

const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "323e4567-e89b-12d3-a456-426614174000";
const ID_3 = "423e4567-e89b-12d3-a456-426614174000";

describe("parseTrainingCompetencyRow", () => {
  test("maps a draft competency", () => {
    const c = parseTrainingCompetencyRow({ id: ID_1, code: "safety_basics", name: "Safety Basics", description: null, category: "safety", status: "draft", record_version: 1 });
    assert.equal(c.status, "draft");
    assert.equal(c.description, null);
  });
});

describe("parseTrainingCourseVersionRow", () => {
  test("passing_score/duration_hours are decimal strings, never JS numbers", () => {
    const v = parseTrainingCourseVersionRow({
      id: ID_1, course_id: ID_2, version_number: 1, status: "published", description: "Intro", delivery_mode: "in_person",
      duration_hours: 4.5, is_mandatory: false, requires_enrollment_approval: false, requires_assessment: true, passing_score: 70,
      issues_certificate: true, certificate_validity_months: 24, record_version: 2,
    });
    assert.equal(typeof v.passingScore, "string");
    assert.equal(v.passingScore, "70");
    assert.equal(typeof v.durationHours, "string");
  });

  test("a non-assessed version carries null passing_score", () => {
    const v = parseTrainingCourseVersionRow({
      id: ID_1, course_id: ID_2, version_number: 1, status: "draft", description: null, delivery_mode: "e_learning",
      duration_hours: null, is_mandatory: true, requires_enrollment_approval: false, requires_assessment: false, passing_score: null,
      issues_certificate: false, certificate_validity_months: null, record_version: 1,
    });
    assert.equal(v.passingScore, null);
    assert.equal(v.isMandatory, true);
  });
});

describe("parseTrainingCourseCompetencyRow", () => {
  test("joined list projection carries competency code/name", () => {
    const r = parseTrainingCourseCompetencyRow({ course_id: ID_1, competency_id: ID_2, competency_code: "safety_basics", competency_name: "Safety Basics" });
    assert.equal(r.competencyCode, "safety_basics");
  });
});

describe("parseTrainingSessionRow", () => {
  test("a raw mutation-return row parses with joined display columns absent", () => {
    const s = parseTrainingSessionRow({
      id: ID_1, course_version_id: ID_2, provider_id: null, session_code: "sess_a", location: null, start_at: "2026-09-01T00:00:00Z",
      end_at: "2026-09-01T04:00:00Z", capacity: 10, status: "scheduled", cancel_reason: null, record_version: 1,
    });
    assert.equal(s.courseCode, undefined);
    assert.equal(s.enrolledCount, undefined);
  });

  test("a list-projection row carries the joined display columns and enrolled_count", () => {
    const s = parseTrainingSessionRow({
      id: ID_1, course_version_id: ID_2, course_id: ID_3, course_code: "safety_101", course_name: "Safety 101", provider_id: null,
      provider_name: null, session_code: "sess_a", location: "Room A", start_at: "2026-09-01T00:00:00Z", end_at: "2026-09-01T04:00:00Z",
      capacity: 10, enrolled_count: 3, status: "scheduled", record_version: 1,
    });
    assert.equal(s.courseCode, "safety_101");
    assert.equal(s.enrolledCount, 3);
  });
});

describe("parseTrainingEnrollmentRow", () => {
  test("waitlisted status and hours_attended as decimal string", () => {
    const e = parseTrainingEnrollmentRow({
      id: ID_1, session_id: ID_2, course_version_id: ID_3, status: "waitlisted", enrollment_source: "self", attended: null,
      hours_attended: null, completion_notes: null, record_version: 1,
    });
    assert.equal(e.status, "waitlisted");
  });
});

describe("parseTrainingAssessmentRow", () => {
  test("score/max_score are decimal strings; passed is a plain boolean", () => {
    const a = parseTrainingAssessmentRow({
      id: ID_1, enrollment_id: ID_2, employee_id: ID_3, course_version_id: ID_1, attempt_number: 2, score: 85, max_score: 100, passed: true,
      assessed_by: "hr", assessed_at: "2026-08-01T00:00:00Z", notes: "retake, passed", record_version: 1,
    });
    assert.equal(typeof a.score, "string");
    assert.equal(a.passed, true);
    assert.equal(a.attemptNumber, 2);
  });
});

describe("parseTrainingCertificateRow", () => {
  test("an external, unverified import carries a null course_version_id", () => {
    const c = parseTrainingCertificateRow({
      id: ID_1, course_version_id: null, external_course_name: "External First Aid", certificate_number: "CERT-1", issued_at: "2026-01-01",
      expiry_date: "2027-01-01", status: "issued", source: "external_import", verification_status: "unverified", evidence_file_id: null, record_version: 1,
    });
    assert.equal(c.courseVersionId, null);
    assert.equal(c.verificationStatus, "unverified");
  });

  test("a revoked certificate carries its status", () => {
    const c = parseTrainingCertificateRow({
      id: ID_1, course_version_id: ID_2, external_course_name: null, certificate_number: "CERT-2", issued_at: "2026-01-01", expiry_date: null,
      status: "revoked", source: "internal_completion", verification_status: "verified", evidence_file_id: null, record_version: 3,
    });
    assert.equal(c.status, "revoked");
  });
});

describe("parseTrainingCertificateExpiryReminderRow", () => {
  test("maps days_until_expiry", () => {
    const r = parseTrainingCertificateExpiryReminderRow({ id: ID_1, certificate_id: ID_2, employee_id: ID_3, period_label: "p1", days_until_expiry: 10, reminded_at: "2026-08-01T00:00:00Z" });
    assert.equal(r.daysUntilExpiry, 10);
  });
});

describe("parseTrainingDevelopmentPlanRow", () => {
  test("maps a plan linked to a performance outcome", () => {
    const p = parseTrainingDevelopmentPlanRow({
      id: ID_1, employee_id: ID_2, title: "FY2026 Growth Plan", cycle_label: "FY2026", status: "active", linked_performance_outcome_id: ID_3, record_version: 2,
    });
    assert.equal(p.linkedPerformanceOutcomeId, ID_3);
  });

  test("linked_performance_outcome_id is nullable", () => {
    const p = parseTrainingDevelopmentPlanRow({ id: ID_1, employee_id: ID_2, title: "Plan", cycle_label: null, status: "draft", linked_performance_outcome_id: null, record_version: 1 });
    assert.equal(p.linkedPerformanceOutcomeId, null);
  });
});

describe("parseTalentReviewAssignmentRow / parseTalentReviewRow", () => {
  test("a reassigned assignment carries its status", () => {
    const a = parseTalentReviewAssignmentRow({ id: ID_1, cycle_id: ID_2, subject_employee_id: ID_3, reviewer_employee_id: ID_1, status: "reassigned", record_version: 2 });
    assert.equal(a.status, "reassigned");
  });

  test("a submitted review carries its potential_rating/risk_of_loss enums", () => {
    const r = parseTalentReviewRow({
      id: ID_1, cycle_id: ID_2, subject_employee_id: ID_3, assignment_id: ID_1, potential_rating: "high", readiness_note: "ready for stretch",
      risk_of_loss: "medium", status: "submitted", submitted_at: "2026-08-01T00:00:00Z", record_version: 2,
    });
    assert.equal(r.potentialRating, "high");
    assert.equal(r.riskOfLoss, "medium");
  });

  test("a draft review carries null potential_rating", () => {
    const r = parseTalentReviewRow({
      id: ID_1, cycle_id: ID_2, subject_employee_id: ID_3, assignment_id: ID_1, potential_rating: null, readiness_note: null,
      risk_of_loss: null, status: "draft", submitted_at: null, record_version: 1,
    });
    assert.equal(r.potentialRating, null);
  });
});

describe("parseTalentPoolMemberRow", () => {
  test("addedReason is always a non-null string (mandatory business rule)", () => {
    const m = parseTalentPoolMemberRow({ id: ID_1, pool_id: ID_2, employee_id: ID_3, status: "active", added_reason: "strong leadership potential", added_at: "2026-08-01T00:00:00Z", record_version: 1 });
    assert.equal(m.addedReason, "strong leadership potential");
  });
});

describe("parseTalentSuccessionCandidateRow", () => {
  test("maps readiness/decision_reason", () => {
    const c = parseTalentSuccessionCandidateRow({
      id: ID_1, position_id: ID_2, candidate_employee_id: ID_3, readiness: "ready_1_2_years", decision_reason: "developing leadership skills",
      status: "proposed", record_version: 1,
    });
    assert.equal(c.readiness, "ready_1_2_years");
  });
});

describe("parseTalentPoolDistributionRow", () => {
  test("a suppressed (small-cohort) department carries a null member_count", () => {
    const r = parseTalentPoolDistributionRow({ department_org_unit_id: ID_1, department_name: "Small Dept", member_count: null, suppressed: true });
    assert.equal(r.memberCount, null);
    assert.equal(r.suppressed, true);
  });

  test("an unsuppressed department carries its real member_count", () => {
    const r = parseTalentPoolDistributionRow({ department_org_unit_id: ID_1, department_name: "Big Dept", member_count: 5, suppressed: false });
    assert.equal(r.memberCount, 5);
    assert.equal(r.suppressed, false);
  });
});
