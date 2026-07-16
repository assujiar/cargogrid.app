import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  RequestSupportAccessInputSchema,
  SupportAccessGrantSchema,
  deriveSupportSessionBanner,
  parseSupportAccessGrant,
  parseSupportAccessSession,
} from "./support-access.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const GRANT_ID = "323e4567-e89b-12d3-a456-426614174000";
const SESSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const GRANTEE_ID = "523e4567-e89b-12d3-a456-426614174000";

const GRANT_ROW = {
  id: GRANT_ID,
  tenant_id: TENANT_ID,
  grantee_auth_user_id: GRANTEE_ID,
  reason: "customer cannot see invoices",
  case_id: "CASE-1",
  scope: "read_only",
  emergency: false,
  status: "approved",
  requested_by: "tester",
  requested_at: "2026-07-16T00:00:00.000Z",
  authorized_by_auth_user_id: null,
  approved_by: "tenant admin",
  granted_at: "2026-07-16T00:05:00.000Z",
  denied_by: null,
  denied_at: null,
  denial_reason: null,
  expires_at: "2026-07-16T08:00:00.000Z",
  revoked_at: null,
  revoked_by: null,
  revoked_reason: null,
  post_review_completed_at: null,
  post_review_by: null,
  post_review_note: null,
  record_version: 2,
  created_at: "2026-07-16T00:00:00.000Z",
  updated_at: "2026-07-16T00:05:00.000Z",
};

const SESSION_ROW = {
  id: SESSION_ID,
  grant_id: GRANT_ID,
  tenant_id: TENANT_ID,
  grantee_auth_user_id: GRANTEE_ID,
  reauth_confirmed_at: "2026-07-16T00:05:00.000Z",
  started_at: "2026-07-16T00:05:00.000Z",
  ended_at: null,
  ended_reason: null,
  created_at: "2026-07-16T00:05:00.000Z",
};

describe("parseSupportAccessGrant", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const grant = parseSupportAccessGrant(GRANT_ROW);
    assert.equal(grant.granteeAuthUserId, GRANTEE_ID);
    assert.equal(grant.caseId, "CASE-1");
    assert.equal(grant.grantedAt, "2026-07-16T00:05:00.000Z");
    assert.equal(grant.status, "approved");
  });

  test("rejects a row with an unknown status (defense against a future untyped enum value)", () => {
    assert.throws(() => parseSupportAccessGrant({ ...GRANT_ROW, status: "not_a_real_status" }));
  });
});

describe("parseSupportAccessSession", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const session = parseSupportAccessSession(SESSION_ROW);
    assert.equal(session.grantId, GRANT_ID);
    assert.equal(session.endedAt, null);
  });
});

describe("RequestSupportAccessInputSchema", () => {
  test("defaults scope to read_only, emergency to false, and authorizedByAuthUserId to null", () => {
    const parsed = RequestSupportAccessInputSchema.parse({
      tenantId: TENANT_ID,
      granteeAuthUserId: GRANTEE_ID,
      reason: "investigating a support ticket",
      caseId: "CASE-2",
      expiryMinutes: 60,
      requestedBy: "tester",
    });
    assert.equal(parsed.scope, "read_only");
    assert.equal(parsed.emergency, false);
    assert.equal(parsed.authorizedByAuthUserId, null);
  });

  test("rejects a non-positive expiryMinutes (mandatory time bound, Prompt 115 §25)", () => {
    assert.throws(() =>
      RequestSupportAccessInputSchema.parse({
        tenantId: TENANT_ID,
        granteeAuthUserId: GRANTEE_ID,
        reason: "x",
        caseId: "CASE-3",
        expiryMinutes: 0,
        requestedBy: "tester",
      }),
    );
  });

  /**
   * Mass-assignment protection proof, mirroring PLT-114's field-access contract test: an
   * attacker-supplied field that looks like a privilege escalation (forging pre-approval,
   * or a fabricated authority claim on a field this schema never exposes) must never
   * survive .parse() -- Zod's default "strip unknown keys" behavior is the actual control,
   * this test just proves it holds for this specific input shape.
   */
  test("strips unrecognized fields such as a forged status or authority claim", () => {
    const parsed = RequestSupportAccessInputSchema.parse({
      tenantId: TENANT_ID,
      granteeAuthUserId: GRANTEE_ID,
      reason: "x",
      caseId: "CASE-4",
      expiryMinutes: 60,
      requestedBy: "tester",
      status: "approved",
      grantedAt: "2020-01-01T00:00:00.000Z",
      bypass: true,
    } as never);
    assert.equal((parsed as Record<string, unknown>).status, undefined);
    assert.equal((parsed as Record<string, unknown>).grantedAt, undefined);
    assert.equal((parsed as Record<string, unknown>).bypass, undefined);
  });
});

describe("SupportAccessGrantSchema", () => {
  test("requires a non-null expiresAt (a grant is never open-ended)", () => {
    const { expiresAt: _expiresAt, ...withoutExpiry } = parseSupportAccessGrant(GRANT_ROW);
    assert.throws(() => SupportAccessGrantSchema.parse(withoutExpiry));
  });
});

describe("deriveSupportSessionBanner", () => {
  const grant = parseSupportAccessGrant(GRANT_ROW);

  test("is not visible when no session is open", () => {
    const banner = deriveSupportSessionBanner(grant, null);
    assert.equal(banner.visible, false);
    assert.equal(banner.state, "no_session");
    assert.equal(banner.secondsRemaining, 0);
  });

  test("is not visible when the session has already ended", () => {
    const session = parseSupportAccessSession({ ...SESSION_ROW, ended_at: "2026-07-16T00:10:00.000Z", ended_reason: "manual_end" });
    const banner = deriveSupportSessionBanner(grant, session);
    assert.equal(banner.visible, false);
    assert.equal(banner.state, "no_session");
  });

  test("is visible with the grant's reason/case/expiry surfaced while a session is open", () => {
    const session = parseSupportAccessSession(SESSION_ROW);
    const now = new Date("2026-07-16T06:00:00.000Z");
    const banner = deriveSupportSessionBanner(grant, session, now);
    assert.equal(banner.visible, true);
    assert.equal(banner.state, "active");
    assert.equal(banner.caseId, "CASE-1");
    assert.equal(banner.reason, grant.reason);
    assert.equal(banner.secondsRemaining, 2 * 60 * 60);
  });

  test("clamps secondsRemaining to zero rather than going negative once past expiry", () => {
    const session = parseSupportAccessSession(SESSION_ROW);
    const now = new Date("2026-07-17T00:00:00.000Z");
    const banner = deriveSupportSessionBanner(grant, session, now);
    assert.equal(banner.secondsRemaining, 0);
  });
});
