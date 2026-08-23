import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseDrRestoreTest,
  parseSupportEntitlement,
  parseEnterpriseOnboardingChecklist,
  RecordDrRestoreTestInputSchema,
  SetSupportEntitlementInputSchema,
  VerifyOnboardingChecklistItemInputSchema,
} from "./disaster-recovery-enterprise-support.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const ROW_ID = "423e4567-e89b-12d3-a456-426614174000";

describe("parseDrRestoreTest", () => {
  test("round-trips a passed test", () => {
    const test1 = parseDrRestoreTest({
      id: ROW_ID, tenant_id: TENANT_ID, deployment_type: "shared", component_scope: "database", status: "passed",
      observed_rpo_minutes: 30, observed_rto_minutes: 60, failure_reason: null, recovery_steps: null, retest_scheduled_at: null,
      owner_auth_user_id: null, owner_label: null, tested_by_auth_user_id: ACTOR_ID, tested_by: "admin1",
      tested_at: "2026-08-22T00:00:00.000Z", created_at: "2026-08-22T00:00:00.000Z",
    });
    assert.equal(test1.status, "passed");
    assert.equal(test1.observedRpoMinutes, 30);
  });

  test("rejects an unrecognized component_scope", () => {
    assert.throws(() =>
      parseDrRestoreTest({
        id: ROW_ID, tenant_id: TENANT_ID, deployment_type: "shared", component_scope: "not-a-real-scope", status: "passed",
        observed_rpo_minutes: 30, observed_rto_minutes: 60, failure_reason: null, recovery_steps: null, retest_scheduled_at: null,
        owner_auth_user_id: null, owner_label: null, tested_by_auth_user_id: null, tested_by: null,
        tested_at: "2026-08-22T00:00:00.000Z", created_at: "2026-08-22T00:00:00.000Z",
      }),
    );
  });
});

describe("parseSupportEntitlement", () => {
  test("round-trips an enterprise_24_7 entitlement", () => {
    const entitlement = parseSupportEntitlement({
      id: ROW_ID, tenant_id: TENANT_ID, tier: "enterprise_24_7", contract_reference: "MSA-2026-006",
      escalation_contact_name: "NOC Team", escalation_contact_email: "noc@example.test", p1_response_minutes: 15,
      created_by: "admin1", created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z", record_version: 2,
    });
    assert.equal(entitlement.tier, "enterprise_24_7");
    assert.equal(entitlement.p1ResponseMinutes, 15);
  });
});

describe("parseEnterpriseOnboardingChecklist", () => {
  test("round-trips a ready_for_production checklist", () => {
    const checklist = parseEnterpriseOnboardingChecklist({
      id: ROW_ID, tenant_id: TENANT_ID, sso_verified: true, sso_verified_at: "2026-08-22T00:00:00.000Z",
      api_verified: true, api_verified_at: "2026-08-22T00:00:00.000Z", integrations_verified: true, integrations_verified_at: "2026-08-22T00:00:00.000Z",
      dr_evidence_verified: true, dr_evidence_verified_at: "2026-08-22T00:00:00.000Z", support_entitlement_verified: true, support_entitlement_verified_at: "2026-08-22T00:00:00.000Z",
      hypercare_plan_acknowledged: true, hypercare_plan_acknowledged_at: "2026-08-22T00:00:00.000Z", hypercare_plan_acknowledged_by_auth_user_id: ACTOR_ID, hypercare_plan_acknowledged_by: "approver1",
      status: "ready_for_production", created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z", record_version: 6,
    });
    assert.equal(checklist.status, "ready_for_production");
  });
});

describe("input schemas", () => {
  test("RecordDrRestoreTestInputSchema accepts a passed test with real evidence", () => {
    const parsed = RecordDrRestoreTestInputSchema.parse({
      tenantId: TENANT_ID, deploymentType: "shared", componentScope: "database", status: "passed",
      observedRpoMinutes: 30, observedRtoMinutes: 60, failureReason: null, recoverySteps: null, retestScheduledAt: null,
      ownerAuthUserId: null, ownerLabel: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
    });
    assert.equal(parsed.status, "passed");
  });

  test("SetSupportEntitlementInputSchema rejects an unrecognized tier", () => {
    assert.throws(() =>
      SetSupportEntitlementInputSchema.parse({
        tenantId: TENANT_ID, tier: "not-a-real-tier", contractReference: null, escalationContactName: null,
        escalationContactEmail: null, p1ResponseMinutes: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
      }),
    );
  });

  test("VerifyOnboardingChecklistItemInputSchema rejects an unrecognized item", () => {
    assert.throws(() =>
      VerifyOnboardingChecklistItemInputSchema.parse({
        tenantId: TENANT_ID, item: "not-a-real-item", humanAcknowledged: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
      }),
    );
  });
});
