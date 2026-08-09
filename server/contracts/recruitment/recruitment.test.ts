import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseJobVacancy,
  parseCandidateProfile,
  parseCandidateListRow,
  parseJobApplication,
  parseCandidateAssessment,
  parseInterview,
  parseJobOffer,
  parseJobOfferVersion,
  parseOfferTimeline,
  parsePublicVacancySummary,
  parsePublicSubmitResult,
  CreateJobVacancyDraftInputSchema,
  SubmitPublicJobApplicationInputSchema,
} from "./recruitment.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "323e4567-e89b-12d3-a456-426614174000";

describe("recruitment contract parsers", () => {
  test("parseJobVacancy maps snake_case row", () => {
    const vacancy = parseJobVacancy({
      id: ID_1,
      tenant_id: TENANT_ID,
      position_id: ID_2,
      title: "Software Engineer",
      employment_type: "full_time",
      headcount: 2,
      status: "open",
      status_reason: null,
      description: "desc",
      requirements: null,
      hiring_manager_employee_id: null,
      owner_auth_user_id: null,
      record_version: 1,
      created_at: "2026-08-09T00:00:00.000Z",
      updated_at: "2026-08-09T00:00:00.000Z",
    });
    assert.equal(vacancy.title, "Software Engineer");
    assert.equal(vacancy.headcount, 2);
    assert.equal(vacancy.status, "open");
  });

  test("parseCandidateProfile maps masked pii to null", () => {
    const candidate = parseCandidateProfile({
      id: ID_1,
      tenant_id: TENANT_ID,
      full_name: "Ada Lovelace",
      email: null,
      phone: null,
      national_id_number: null,
      date_of_birth: null,
      address: null,
      resume_file_id: null,
      source: "staff_created",
      status: "active",
      consent_given: true,
      consent_given_at: "2026-08-09T00:00:00.000Z",
      consent_version: "v1",
      personal_data_masked: true,
      record_version: 1,
      created_at: "2026-08-09T00:00:00.000Z",
      updated_at: "2026-08-09T00:00:00.000Z",
    });
    assert.equal(candidate.personalDataMasked, true);
    assert.equal(candidate.email, null);
    assert.equal(candidate.fullName, "Ada Lovelace");
  });

  test("parseCandidateListRow carries no pii column", () => {
    const row = parseCandidateListRow({ id: ID_1, full_name: "Ada Lovelace", source: "staff_created", status: "active", consent_given: true, created_at: "2026-08-09T00:00:00.000Z" });
    assert.equal(row.fullName, "Ada Lovelace");
    assert.equal((row as Record<string, unknown>).email, undefined);
  });

  test("parseJobApplication maps stage/source", () => {
    const application = parseJobApplication({
      id: ID_1,
      tenant_id: TENANT_ID,
      vacancy_id: ID_2,
      candidate_id: ID_2,
      stage: "screening",
      source: "public_application",
      applied_at: "2026-08-09T00:00:00.000Z",
      stage_since: "2026-08-09T00:00:00.000Z",
      rejection_reason: null,
      withdrawal_reason: null,
      record_version: 1,
      created_at: "2026-08-09T00:00:00.000Z",
      updated_at: "2026-08-09T00:00:00.000Z",
    });
    assert.equal(application.stage, "screening");
    assert.equal(application.source, "public_application");
  });

  test("parseCandidateAssessment coerces numeric score/max_score", () => {
    const assessment = parseCandidateAssessment({
      id: ID_1,
      tenant_id: TENANT_ID,
      application_id: ID_2,
      assessment_type: "technical",
      criteria_version: "v1",
      max_score: "100",
      pass_threshold: "60",
      score: "85",
      status: "completed",
      notes: null,
      completed_at: "2026-08-09T00:00:00.000Z",
      record_version: 1,
      created_at: "2026-08-09T00:00:00.000Z",
    });
    assert.equal(assessment.score, 85);
    assert.equal(assessment.maxScore, 100);
  });

  test("parseInterview maps mode/status", () => {
    const interview = parseInterview({
      id: ID_1,
      tenant_id: TENANT_ID,
      application_id: ID_2,
      round: 1,
      mode: "video",
      scheduled_at: "2026-08-09T00:00:00.000Z",
      duration_minutes: 45,
      location_or_link: "https://meet.example.test",
      status: "scheduled",
      cancel_reason: null,
      record_version: 1,
      created_at: "2026-08-09T00:00:00.000Z",
    });
    assert.equal(interview.mode, "video");
    assert.equal(interview.durationMinutes, 45);
  });

  test("parseJobOffer and parseJobOfferVersion + parseOfferTimeline compose", () => {
    const offer = parseJobOffer({
      id: ID_1,
      tenant_id: TENANT_ID,
      application_id: ID_2,
      status: "draft",
      approval_status: "not_required",
      approval_request_id: null,
      current_version_id: ID_2,
      record_version: 1,
      created_at: "2026-08-09T00:00:00.000Z",
      updated_at: "2026-08-09T00:00:00.000Z",
    });
    const version = parseJobOfferVersion({
      id: ID_2,
      offer_id: ID_1,
      version_number: 1,
      compensation_amount: "15000000",
      compensation_currency: "IDR",
      effective_date: "2026-09-01",
      expiry_date: null,
      title: "Software Engineer",
      employment_type: "full_time",
      benefits_note: null,
      status: "draft",
      created_at: "2026-08-09T00:00:00.000Z",
    });
    const timeline = parseOfferTimeline({ offer: { ...offerRowFrom(offer) }, versions: [versionRowFrom(version)] });
    assert.equal(timeline.offer.status, "draft");
    assert.equal(timeline.versions.length, 1);
    assert.equal(timeline.versions[0]?.compensationAmount, 15000000);
  });

  test("parsePublicVacancySummary and parsePublicSubmitResult", () => {
    const summary = parsePublicVacancySummary({ posting_token: "abc123", title: "Engineer", employment_type: "full_time", org_unit_name: "Engineering", headcount: 1, published_at: "2026-08-09T00:00:00.000Z" });
    assert.equal(summary.postingToken, "abc123");

    const result = parsePublicSubmitResult({ submit_status: "ok", application_id: ID_1 });
    assert.equal(result.submitStatus, "ok");
    assert.equal(result.applicationId, ID_1);
  });

  test("CreateJobVacancyDraftInputSchema rejects an empty title", () => {
    assert.throws(() =>
      CreateJobVacancyDraftInputSchema.parse({
        tenantId: TENANT_ID,
        positionId: ID_1,
        title: "",
        employmentType: "full_time",
        headcount: 1,
        description: null,
        requirements: null,
        hiringManagerEmployeeId: null,
        idempotencyKey: null,
        actorAuthUserId: ID_2,
        actorLabel: "tester",
      }),
    );
  });

  test("SubmitPublicJobApplicationInputSchema requires a valid email", () => {
    assert.throws(() =>
      SubmitPublicJobApplicationInputSchema.parse({
        postingToken: "tok",
        clientKey: "key",
        fullName: "Ada Lovelace",
        email: "not-an-email",
        phone: null,
        consentGiven: true,
        consentVersion: "v1",
        idempotencyKey: null,
      }),
    );
  });
});

// Small local helpers so the composite parseOfferTimeline test can feed back through
// the exact snake_case shape parseJobOffer/parseJobOfferVersion themselves expect,
// without duplicating every field by hand.
function offerRowFrom(offer: ReturnType<typeof parseJobOffer>): Record<string, unknown> {
  return {
    id: offer.id,
    tenant_id: offer.tenantId,
    application_id: offer.applicationId,
    status: offer.status,
    approval_status: offer.approvalStatus,
    approval_request_id: offer.approvalRequestId,
    current_version_id: offer.currentVersionId,
    record_version: offer.recordVersion,
    created_at: offer.createdAt,
    updated_at: offer.updatedAt,
  };
}
function versionRowFrom(version: ReturnType<typeof parseJobOfferVersion>): Record<string, unknown> {
  return {
    id: version.id,
    offer_id: version.offerId,
    version_number: version.versionNumber,
    compensation_amount: version.compensationAmount,
    compensation_currency: version.compensationCurrency,
    effective_date: version.effectiveDate,
    expiry_date: version.expiryDate,
    title: version.title,
    employment_type: version.employmentType,
    benefits_note: version.benefitsNote,
    status: version.status,
    created_at: version.createdAt,
  };
}
