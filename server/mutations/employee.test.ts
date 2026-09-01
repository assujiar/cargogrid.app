import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createEmployeeDraft,
  updateEmployeeDraft,
  submitEmployeeForApproval,
  decideEmployeeApproval,
  activateEmployee,
  linkEmployeeUser,
  suspendEmployee,
  reactivateEmployee,
  terminateEmployee,
  archiveEmployeeProfile,
  transferEmployee,
  addEmployeeEmergencyContact,
  requestEmployeeChange,
  decideEmployeeChangeRequest,
  validateEmployeeImportRow,
  commitEmployeeImportJob,
  reactivateUserAfterRehire,
  activateDueEmployeeLifecycleTransitions,
  initiateEmployeeDocumentUpload,
  EmployeeMutationError,
  type EmployeeMutationRpcClient,
} from "./employee.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const MASTER_RECORD_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const USER_ID = "423e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "523e4567-e89b-12d3-a456-426614174000";
const STAGING_ROW_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): { client: EmployeeMutationRpcClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as EmployeeMutationRpcClient;
  return { client, calls };
}

const EMPLOYEE_ROW = {
  master_record_id: MASTER_RECORD_ID,
  tenant_id: TENANT_ID,
  user_id: null,
  full_name: "Budi Santoso",
  employment_type: "full_time",
  lifecycle_status: "draft",
  intake_source: "hr_created",
  work_email: null,
  personal_email: null,
  personal_phone: null,
  hire_date: null,
  company_org_unit_id: null,
  branch_org_unit_id: null,
  department_org_unit_id: null,
  position_title: null,
  manager_employee_id: null,
  revision_reason: null,
  suspend_reason: null,
  terminate_reason: null,
  archive_reason: null,
  leave_reason: null,
  record_version: 1,
  created_by: "staff",
  created_at: "2026-08-09T00:00:00.000Z",
  updated_at: "2026-08-09T00:00:00.000Z",
};

describe("createEmployeeDraft", () => {
  test("calls create_employee_draft with mapped snake_case args", async () => {
    const { client, calls } = fakeRpcClient({ data: [EMPLOYEE_ROW], error: null });
    await createEmployeeDraft(client, {
      tenantId: TENANT_ID,
      fullName: "Budi Santoso",
      employmentType: "full_time",
      workEmail: null,
      personalEmail: null,
      personalPhone: null,
      nationalIdNumber: null,
      dateOfBirth: null,
      gender: null,
      hireDate: null,
      companyOrgUnitId: null,
      branchOrgUnitId: null,
      departmentOrgUnitId: null,
      positionTitle: null,
      managerEmployeeId: null,
      userId: null,
      employeeNumber: null,
      intakeSource: "hr_created",
      idempotencyKey: "idem-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(calls[0]?.fn, "create_employee_draft");
    assert.equal(calls[0]?.args.p_tenant_id, TENANT_ID);
    assert.equal(calls[0]?.args.p_full_name, "Budi Santoso");
    assert.equal(calls[0]?.args.p_idempotency_key, "idem-1");
  });

  test("classifies a known error prefix from the RPC error message", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks HRS:Create" } });
    await assert.rejects(
      () =>
        createEmployeeDraft(client, {
          tenantId: TENANT_ID,
          fullName: "X",
          employmentType: "full_time",
          workEmail: null,
          personalEmail: null,
          personalPhone: null,
          nationalIdNumber: null,
          dateOfBirth: null,
          gender: null,
          hireDate: null,
          companyOrgUnitId: null,
          branchOrgUnitId: null,
          departmentOrgUnitId: null,
          positionTitle: null,
          managerEmployeeId: null,
          userId: null,
          employeeNumber: null,
          intakeSource: "hr_created",
          idempotencyKey: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff",
        }),
      (err: unknown) => err instanceof EmployeeMutationError && err.code === "insufficient_authority",
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_wholly_unexpected_db_error: oops" } });
    await assert.rejects(
      () =>
        createEmployeeDraft(client, {
          tenantId: TENANT_ID,
          fullName: "X",
          employmentType: "full_time",
          workEmail: null,
          personalEmail: null,
          personalPhone: null,
          nationalIdNumber: null,
          dateOfBirth: null,
          gender: null,
          hireDate: null,
          companyOrgUnitId: null,
          branchOrgUnitId: null,
          departmentOrgUnitId: null,
          positionTitle: null,
          managerEmployeeId: null,
          userId: null,
          employeeNumber: null,
          intakeSource: "hr_created",
          idempotencyKey: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff",
        }),
      (err: unknown) => err instanceof EmployeeMutationError && err.code === "mutation_failed",
    );
  });

  test("throws invalid_response when the RPC returns no row", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(
      () =>
        createEmployeeDraft(client, {
          tenantId: TENANT_ID,
          fullName: "X",
          employmentType: "full_time",
          workEmail: null,
          personalEmail: null,
          personalPhone: null,
          nationalIdNumber: null,
          dateOfBirth: null,
          gender: null,
          hireDate: null,
          companyOrgUnitId: null,
          branchOrgUnitId: null,
          departmentOrgUnitId: null,
          positionTitle: null,
          managerEmployeeId: null,
          userId: null,
          employeeNumber: null,
          intakeSource: "hr_created",
          idempotencyKey: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff",
        }),
      (err: unknown) => err instanceof EmployeeMutationError && err.code === "invalid_response",
    );
  });
});

describe("updateEmployeeDraft / submitEmployeeForApproval / decideEmployeeApproval / activateEmployee", () => {
  test("updateEmployeeDraft maps every field, including nulls for unset optionals", async () => {
    const { client, calls } = fakeRpcClient({ data: [EMPLOYEE_ROW], error: null });
    await updateEmployeeDraft(client, {
      masterRecordId: MASTER_RECORD_ID,
      expectedVersion: 1,
      fullName: "Budi Santoso",
      employmentType: "full_time",
      workEmail: null,
      personalEmail: null,
      personalPhone: null,
      nationalIdNumber: null,
      dateOfBirth: null,
      gender: null,
      hireDate: "2026-01-15",
      probationEndDate: null,
      companyOrgUnitId: null,
      branchOrgUnitId: null,
      departmentOrgUnitId: null,
      positionTitle: null,
      managerEmployeeId: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(calls[0]?.fn, "update_employee_draft");
    assert.equal(calls[0]?.args.p_hire_date, "2026-01-15");
    assert.equal(calls[0]?.args.p_manager_employee_id, null);
  });

  test("submitEmployeeForApproval maps master_record_id/expected_version/actor", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...EMPLOYEE_ROW, lifecycle_status: "submitted" }], error: null });
    const result = await submitEmployeeForApproval(client, { masterRecordId: MASTER_RECORD_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "staff" });
    assert.equal(calls[0]?.fn, "submit_employee_for_approval");
    assert.equal(result.lifecycleStatus, "submitted");
  });

  test("decideEmployeeApproval maps decision/reason", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...EMPLOYEE_ROW, lifecycle_status: "approved" }], error: null });
    await decideEmployeeApproval(client, { masterRecordId: MASTER_RECORD_ID, expectedVersion: 1, decision: "approve", reason: null, actorAuthUserId: ACTOR_ID, actorLabel: "approver" });
    assert.equal(calls[0]?.args.p_decision, "approve");
  });

  test("activateEmployee", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...EMPLOYEE_ROW, lifecycle_status: "active" }], error: null });
    await activateEmployee(client, { masterRecordId: MASTER_RECORD_ID, expectedVersion: 2, actorAuthUserId: ACTOR_ID, actorLabel: "approver" });
    assert.equal(calls[0]?.fn, "activate_employee");
  });
});

describe("linkEmployeeUser / suspendEmployee / terminateEmployee / transferEmployee", () => {
  test("linkEmployeeUser maps userId", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...EMPLOYEE_ROW, user_id: USER_ID }], error: null });
    const result = await linkEmployeeUser(client, { masterRecordId: MASTER_RECORD_ID, expectedVersion: 1, userId: USER_ID, actorAuthUserId: ACTOR_ID, actorLabel: "staff" });
    assert.equal(calls[0]?.args.p_user_id, USER_ID);
    assert.equal(result.userId, USER_ID);
  });

  test("suspendEmployee requires a reason at the schema level (empty string rejected before any RPC call)", async () => {
    await assert.rejects(() =>
      suspendEmployee(fakeRpcClient({ data: [], error: null }).client, { masterRecordId: MASTER_RECORD_ID, expectedVersion: 1, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "manager" }),
    );
  });

  test("terminateEmployee maps reason/employmentEndDate", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...EMPLOYEE_ROW, lifecycle_status: "terminated" }], error: null });
    await terminateEmployee(client, { masterRecordId: MASTER_RECORD_ID, expectedVersion: 3, reason: "resignation", employmentEndDate: "2026-06-30", actorAuthUserId: ACTOR_ID, actorLabel: "manager" });
    assert.equal(calls[0]?.args.p_employment_end_date, "2026-06-30");
  });

  test("transferEmployee maps org unit/position/manager/reason", async () => {
    const { client, calls } = fakeRpcClient({ data: [EMPLOYEE_ROW], error: null });
    await transferEmployee(client, {
      masterRecordId: MASTER_RECORD_ID,
      expectedVersion: 1,
      companyOrgUnitId: null,
      branchOrgUnitId: null,
      departmentOrgUnitId: null,
      positionTitle: "Senior Analyst",
      managerEmployeeId: null,
      reason: "org restructuring",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(calls[0]?.fn, "transfer_employee");
    assert.equal(calls[0]?.args.p_position_title, "Senior Analyst");
  });
});

describe("addEmployeeEmergencyContact / requestEmployeeChange / decideEmployeeChangeRequest", () => {
  test("addEmployeeEmergencyContact maps isPrimary", async () => {
    const { client, calls } = fakeRpcClient({
      data: [{ id: MASTER_RECORD_ID, master_record_id: MASTER_RECORD_ID, name: "Contact", relationship: null, phone: null, email: null, is_primary: true, record_version: 1, created_at: "2026-08-09T00:00:00.000Z" }],
      error: null,
    });
    await addEmployeeEmergencyContact(client, { masterRecordId: MASTER_RECORD_ID, name: "Contact", relationship: null, phone: null, email: null, isPrimary: true, actorAuthUserId: ACTOR_ID, actorLabel: "staff" });
    assert.equal(calls[0]?.args.p_is_primary, true);
  });

  test("requestEmployeeChange never sends an actorLabel param (the RPC has none)", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: MASTER_RECORD_ID,
          master_record_id: MASTER_RECORD_ID,
          requested_by_user_id: USER_ID,
          field_key: "personal_phone",
          current_value_snapshot: null,
          requested_value: "+62-811-1",
          reason: null,
          status: "pending",
          decided_by: null,
          decided_at: null,
          decided_reason: null,
          record_version: 1,
          created_at: "2026-08-09T00:00:00.000Z",
        },
      ],
      error: null,
    });
    await requestEmployeeChange(client, { masterRecordId: MASTER_RECORD_ID, fieldKey: "personal_phone", requestedValue: "+62-811-1", reason: null, actorAuthUserId: ACTOR_ID });
    assert.deepEqual(calls[0]?.args, {
      p_master_record_id: MASTER_RECORD_ID,
      p_field_key: "personal_phone",
      p_requested_value: "+62-811-1",
      p_reason: null,
      p_actor_auth_user_id: ACTOR_ID,
    });
  });

  test("decideEmployeeChangeRequest maps decision/decidedReason", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: MASTER_RECORD_ID,
          master_record_id: MASTER_RECORD_ID,
          requested_by_user_id: USER_ID,
          field_key: "personal_phone",
          current_value_snapshot: null,
          requested_value: "+62-811-1",
          reason: null,
          status: "approved",
          decided_by: "staff",
          decided_at: "2026-08-09T00:00:00.000Z",
          decided_reason: "verified",
          record_version: 2,
          created_at: "2026-08-09T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const result = await decideEmployeeChangeRequest(client, { requestId: MASTER_RECORD_ID, expectedVersion: 1, decision: "approved", decidedReason: "verified", actorAuthUserId: ACTOR_ID, actorLabel: "staff" });
    assert.equal(calls[0]?.args.p_decision, "approved");
    assert.equal(result.status, "approved");
  });
});

describe("validateEmployeeImportRow", () => {
  test("calls validate_employee_import_row with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { id: STAGING_ROW_ID, validation_status: "valid" }, error: null });

    const row = await validateEmployeeImportRow(client, { stagingRowId: STAGING_ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "validate_employee_import_row");
    assert.equal(calls[0]?.args.p_staging_row_id, STAGING_ROW_ID);
    assert.equal(calls[0]?.args.p_actor_auth_user_id, ACTOR_ID);
    assert.equal(calls[0]?.args.p_actor_label, "tester");
    assert.equal(row.validation_status, "valid");
  });
});

describe("commitEmployeeImportJob", () => {
  test("calls commit_employee_import_job with the exact snake_case params, defaulting allowPartial to false", async () => {
    const { client, calls } = fakeRpcClient({ data: { job_id: JOB_ID, status: "completed" }, error: null });

    const job = await commitEmployeeImportJob(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "commit_employee_import_job");
    assert.equal(calls[0]?.args.p_job_id, JOB_ID);
    assert.equal(calls[0]?.args.p_allow_partial, false);
    assert.equal(job.status, "completed");
  });

  test("classifies import_export_job_has_invalid_rows", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "import_export_job_has_invalid_rows: job x has 2 invalid row(s); pass p_allow_partial to accept a partial commit" } }).client;
    await assert.rejects(
      () => commitEmployeeImportJob(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof EmployeeMutationError);
        assert.equal(err.code, "import_export_job_has_invalid_rows");
        return true;
      },
    );
  });
});

describe("reactivateUserAfterRehire", () => {
  test("calls reactivate_user_after_rehire with the exact snake_case params, no expected_version", async () => {
    const { client, calls } = fakeRpcClient({ data: { id: USER_ID, status: "active" }, error: null });

    const row = await reactivateUserAfterRehire(client, { masterRecordId: MASTER_RECORD_ID, reason: "restore access after rejoining", actorAuthUserId: ACTOR_ID, actorLabel: "manager" });

    assert.equal(calls[0]?.fn, "reactivate_user_after_rehire");
    assert.equal(calls[0]?.args.p_master_record_id, MASTER_RECORD_ID);
    assert.equal(calls[0]?.args.p_reason, "restore access after rejoining");
    assert.equal(calls[0]?.args.p_actor_auth_user_id, ACTOR_ID);
    assert.ok(!("p_expected_version" in calls[0]!.args));
    assert.equal(row.status, "active");
  });

  test("requires a reason at the schema level (empty string rejected before any RPC call)", async () => {
    await assert.rejects(() =>
      reactivateUserAfterRehire(fakeRpcClient({ data: [], error: null }).client, { masterRecordId: MASTER_RECORD_ID, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "manager" }),
    );
  });

  test("classifies no_rehire_event (HRT-295 / ISS-2026-108's own new error code)", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "no_rehire_event: employee x has no recorded terminated -> active (rehire) transition on file, cannot reactivate Platform access via this path" } }).client;
    await assert.rejects(
      () => reactivateUserAfterRehire(client, { masterRecordId: MASTER_RECORD_ID, reason: "attempted reactivation", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof EmployeeMutationError);
        assert.equal(err.code, "no_rehire_event");
        return true;
      },
    );
  });
});

// ISS-2026-065 closure (supabase/migrations/
// 20260731310000_add_hris_employee_lifecycle_effective_dating_iss2026065.sql):
// every one of the 7 lifecycle-transition RPCs threads an optional effectiveDate
// (and, for the 3 RPCs with no pre-existing reason parameter, backdateReason)
// through to p_effective_date/p_backdate_reason. Omitting it (the pre-migration
// call shape every existing caller still uses) maps to null, letting the RPC's
// own server-side default (current_date) apply -- fully backward-compatible.
describe("ISS-2026-065: effective-dated lifecycle parameters", () => {
  test("createEmployeeDraft omits effectiveDate/backdateReason -> both null", async () => {
    const { client, calls } = fakeRpcClient({ data: [EMPLOYEE_ROW], error: null });
    await createEmployeeDraft(client, {
      tenantId: TENANT_ID,
      fullName: "Budi Santoso",
      employmentType: "full_time",
      workEmail: null,
      personalEmail: null,
      personalPhone: null,
      nationalIdNumber: null,
      dateOfBirth: null,
      gender: null,
      hireDate: null,
      companyOrgUnitId: null,
      branchOrgUnitId: null,
      departmentOrgUnitId: null,
      positionTitle: null,
      managerEmployeeId: null,
      userId: null,
      employeeNumber: null,
      intakeSource: "hr_created",
      idempotencyKey: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(calls[0]?.args.p_effective_date, null);
    assert.equal(calls[0]?.args.p_backdate_reason, null);
  });

  test("createEmployeeDraft threads through an explicit effectiveDate/backdateReason", async () => {
    const { client, calls } = fakeRpcClient({ data: [EMPLOYEE_ROW], error: null });
    await createEmployeeDraft(client, {
      tenantId: TENANT_ID,
      fullName: "Budi Santoso",
      employmentType: "full_time",
      workEmail: null,
      personalEmail: null,
      personalPhone: null,
      nationalIdNumber: null,
      dateOfBirth: null,
      gender: null,
      hireDate: null,
      companyOrgUnitId: null,
      branchOrgUnitId: null,
      departmentOrgUnitId: null,
      positionTitle: null,
      managerEmployeeId: null,
      userId: null,
      employeeNumber: null,
      intakeSource: "hr_created",
      idempotencyKey: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
      effectiveDate: "2026-01-01",
      backdateReason: "historical parity migration",
    });
    assert.equal(calls[0]?.args.p_effective_date, "2026-01-01");
    assert.equal(calls[0]?.args.p_backdate_reason, "historical parity migration");
  });

  test("updateEmployeeDraft threads through effectiveDate/backdateReason", async () => {
    const { client, calls } = fakeRpcClient({ data: [EMPLOYEE_ROW], error: null });
    await updateEmployeeDraft(client, {
      masterRecordId: MASTER_RECORD_ID,
      expectedVersion: 1,
      fullName: "Budi Santoso",
      employmentType: "full_time",
      workEmail: null,
      personalEmail: null,
      personalPhone: null,
      nationalIdNumber: null,
      dateOfBirth: null,
      gender: null,
      hireDate: null,
      probationEndDate: null,
      companyOrgUnitId: null,
      branchOrgUnitId: null,
      departmentOrgUnitId: null,
      positionTitle: null,
      managerEmployeeId: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
      effectiveDate: "2026-01-01",
      backdateReason: "correction",
    });
    assert.equal(calls[0]?.args.p_effective_date, "2026-01-01");
    assert.equal(calls[0]?.args.p_backdate_reason, "correction");
  });

  test("suspendEmployee threads through effectiveDate (no separate backdateReason param -- reason already mandatory)", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...EMPLOYEE_ROW, lifecycle_status: "suspended" }], error: null });
    await suspendEmployee(client, { masterRecordId: MASTER_RECORD_ID, expectedVersion: 1, reason: "scheduled suspension", actorAuthUserId: ACTOR_ID, actorLabel: "manager", effectiveDate: "2026-09-01" });
    assert.equal(calls[0]?.args.p_effective_date, "2026-09-01");
    assert.ok(!("p_backdate_reason" in calls[0]!.args));
  });

  test("reactivateEmployee threads through effectiveDate/backdateReason", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...EMPLOYEE_ROW, lifecycle_status: "active" }], error: null });
    await reactivateEmployee(client, { masterRecordId: MASTER_RECORD_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "manager", effectiveDate: "2026-09-01", backdateReason: "end of suspension" });
    assert.equal(calls[0]?.fn, "reactivate_employee");
    assert.equal(calls[0]?.args.p_effective_date, "2026-09-01");
    assert.equal(calls[0]?.args.p_backdate_reason, "end of suspension");
  });

  test("terminateEmployee threads through effectiveDate", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...EMPLOYEE_ROW, lifecycle_status: "terminated" }], error: null });
    await terminateEmployee(client, { masterRecordId: MASTER_RECORD_ID, expectedVersion: 1, reason: "resignation", employmentEndDate: "2026-09-30", actorAuthUserId: ACTOR_ID, actorLabel: "manager", effectiveDate: "2026-09-01" });
    assert.equal(calls[0]?.args.p_effective_date, "2026-09-01");
  });

  test("archiveEmployeeProfile threads through effectiveDate", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...EMPLOYEE_ROW, lifecycle_status: "archived" }], error: null });
    await archiveEmployeeProfile(client, { masterRecordId: MASTER_RECORD_ID, expectedVersion: 1, reason: "retention closure", actorAuthUserId: ACTOR_ID, actorLabel: "staff", effectiveDate: "2026-01-01" });
    assert.equal(calls[0]?.fn, "archive_employee_profile");
    assert.equal(calls[0]?.args.p_effective_date, "2026-01-01");
  });

  test("transferEmployee threads through effectiveDate", async () => {
    const { client, calls } = fakeRpcClient({ data: [EMPLOYEE_ROW], error: null });
    await transferEmployee(client, {
      masterRecordId: MASTER_RECORD_ID,
      expectedVersion: 1,
      companyOrgUnitId: null,
      branchOrgUnitId: null,
      departmentOrgUnitId: null,
      positionTitle: "Senior Analyst",
      managerEmployeeId: null,
      reason: "org restructuring",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
      effectiveDate: "2026-01-01",
    });
    assert.equal(calls[0]?.args.p_effective_date, "2026-01-01");
  });

  // ISS-2026-065 Tier C follow-up fix (20260731320000): app.record_employee_
  // lifecycle_version now raises lifecycle_conflict when a write would silently
  // supersede/truncate a still-live, differently-reasoned lifecycle version --
  // reachable through any of the 7 RPCs; transferEmployee exercised here as the
  // representative case (the same classifyError mechanism applies uniformly).
  test("transferEmployee classifies lifecycle_conflict from the shared version writer", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "lifecycle_conflict: employee X already has a terminate lifecycle version not yet in effect" } });
    await assert.rejects(
      () =>
        transferEmployee(client, {
          masterRecordId: MASTER_RECORD_ID,
          expectedVersion: 1,
          companyOrgUnitId: null,
          branchOrgUnitId: null,
          departmentOrgUnitId: null,
          positionTitle: "Senior Analyst",
          managerEmployeeId: null,
          reason: "org restructuring",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff",
        }),
      (err: unknown) => err instanceof EmployeeMutationError && err.code === "lifecycle_conflict",
    );
  });
});

describe("activateDueEmployeeLifecycleTransitions", () => {
  test("calls activate_due_employee_lifecycle_transitions with mapped snake_case args and returns the activated count", async () => {
    const { client, calls } = fakeRpcClient({ data: 3, error: null });
    const result = await activateDueEmployeeLifecycleTransitions(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "sweeper" });
    assert.equal(calls[0]?.fn, "activate_due_employee_lifecycle_transitions");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "sweeper" });
    assert.equal(result, 3);
  });

  test("throws invalid_response when the RPC returns a non-numeric result", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    await assert.rejects(
      () => activateDueEmployeeLifecycleTransitions(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "sweeper" }),
      (err: unknown) => err instanceof EmployeeMutationError && err.code === "invalid_response",
    );
  });

  test("classifies insufficient_authority (HRS:Override required)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks HRS:Override" } });
    await assert.rejects(
      () => activateDueEmployeeLifecycleTransitions(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "sweeper" }),
      (err: unknown) => err instanceof EmployeeMutationError && err.code === "insufficient_authority",
    );
  });
});

// ISS-2026-064 item 2 closure.
describe("initiateEmployeeDocumentUpload", () => {
  const FILE_ROW = {
    id: "723e4567-e89b-12d3-a456-426614174000",
    tenant_id: TENANT_ID,
    document_type_code: "employee_document",
    config_version_id: "823e4567-e89b-12d3-a456-426614174000",
    record_type: "employee",
    record_id: MASTER_RECORD_ID,
    classification: "confidential",
    original_filename: "termination-letter.pdf",
    mime_type: "application/pdf",
    size_bytes: 2048,
    malware_scan_status: "pending",
    malware_scan_completed_at: null,
    malware_scan_provider_ref: null,
    version_group_id: "923e4567-e89b-12d3-a456-426614174000",
    version_number: 1,
    is_latest_version: true,
    lifecycle_status: "active",
    legal_hold: false,
    legal_hold_reason: null,
    deleted_at: null,
    uploaded_by_auth_user_id: ACTOR_ID,
    shared_org_unit_ids: [],
    customer_account_ref: null,
    idempotency_key: null,
    created_at: "2026-09-01T00:00:00.000Z",
    updated_at: "2026-09-01T00:00:00.000Z",
  };

  test("calls initiate_employee_document_upload with mapped snake_case args, classification defaulting to null", async () => {
    const { client, calls } = fakeRpcClient({ data: [FILE_ROW], error: null });
    const result = await initiateEmployeeDocumentUpload(client, {
      masterRecordId: MASTER_RECORD_ID,
      originalFilename: "termination-letter.pdf",
      mimeType: "application/pdf",
      sizeBytes: 2048,
      classification: null,
      idempotencyKey: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(calls[0]?.fn, "initiate_employee_document_upload");
    assert.deepEqual(calls[0]?.args, {
      p_master_record_id: MASTER_RECORD_ID,
      p_original_filename: "termination-letter.pdf",
      p_mime_type: "application/pdf",
      p_size_bytes: 2048,
      p_classification: null,
      p_idempotency_key: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "staff",
    });
    // Never a hardcoded classification -- the RPC's own return is trusted as-is, so a
    // future regression to a hardcoded literal in either this function or the RPC
    // itself surfaces here as a mismatch against the tenant-published default.
    assert.equal(result.classification, "confidential");
    assert.equal(result.recordType, "employee");
    assert.equal(result.recordId, MASTER_RECORD_ID);
    assert.ok(!("storagePath" in result));
  });

  test("throws invalid_response when the RPC returns no row", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(
      () =>
        initiateEmployeeDocumentUpload(client, {
          masterRecordId: MASTER_RECORD_ID,
          originalFilename: "x.pdf",
          mimeType: "application/pdf",
          sizeBytes: 10,
          classification: null,
          idempotencyKey: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff",
        }),
      (err: unknown) => err instanceof EmployeeMutationError && err.code === "invalid_response",
    );
  });

  test("classifies insufficient_authority (HRS:Edit required, never HRS:View)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks HRS:Edit" } });
    await assert.rejects(
      () =>
        initiateEmployeeDocumentUpload(client, {
          masterRecordId: MASTER_RECORD_ID,
          originalFilename: "x.pdf",
          mimeType: "application/pdf",
          sizeBytes: 10,
          classification: null,
          idempotencyKey: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff",
        }),
      (err: unknown) => err instanceof EmployeeMutationError && err.code === "insufficient_authority",
    );
  });

  test("classifies employee_not_found (the shared existence-oracle-safe not-found shape)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "employee_not_found: no such employee" } });
    await assert.rejects(
      () =>
        initiateEmployeeDocumentUpload(client, {
          masterRecordId: MASTER_RECORD_ID,
          originalFilename: "x.pdf",
          mimeType: "application/pdf",
          sizeBytes: 10,
          classification: null,
          idempotencyKey: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff",
        }),
      (err: unknown) => err instanceof EmployeeMutationError && err.code === "employee_not_found",
    );
  });

  test("classifies employee_closed (an archived employee refuses new documents)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "employee_closed: employee is archived" } });
    await assert.rejects(
      () =>
        initiateEmployeeDocumentUpload(client, {
          masterRecordId: MASTER_RECORD_ID,
          originalFilename: "x.pdf",
          mimeType: "application/pdf",
          sizeBytes: 10,
          classification: null,
          idempotencyKey: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff",
        }),
      (err: unknown) => err instanceof EmployeeMutationError && err.code === "employee_closed",
    );
  });

  test("classifies idempotency_key_conflict", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "idempotency_key_conflict: key already used for a different file upload" } });
    await assert.rejects(
      () =>
        initiateEmployeeDocumentUpload(client, {
          masterRecordId: MASTER_RECORD_ID,
          originalFilename: "x.pdf",
          mimeType: "application/pdf",
          sizeBytes: 10,
          classification: null,
          idempotencyKey: "reused-key",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff",
        }),
      (err: unknown) => err instanceof EmployeeMutationError && err.code === "idempotency_key_conflict",
    );
  });

  // Each of the 7 newly-reachable PLT-128 error prefixes (app.initiate_file_upload,
  // called internally by app.initiate_employee_document_upload) classifies to its own
  // named code, never the generic "mutation_failed" fallback.
  const NEWLY_REACHABLE_DOCUMENT_ERROR_CODES = [
    "document_type_not_configured",
    "document_unsafe_filename",
    "document_mime_type_not_allowed",
    "document_file_too_large",
    "document_invalid_classification",
    "document_classification_too_weak",
    "file_actor_unauthorized",
  ] as const;

  for (const code of NEWLY_REACHABLE_DOCUMENT_ERROR_CODES) {
    test(`classifies ${code} (newly reachable through app.initiate_file_upload)`, async () => {
      const { client } = fakeRpcClient({ data: null, error: { message: `${code}: synthetic test message` } });
      await assert.rejects(
        () =>
          initiateEmployeeDocumentUpload(client, {
            masterRecordId: MASTER_RECORD_ID,
            originalFilename: "x.pdf",
            mimeType: "application/pdf",
            sizeBytes: 10,
            classification: null,
            idempotencyKey: null,
            actorAuthUserId: ACTOR_ID,
            actorLabel: "staff",
          }),
        (err: unknown) => err instanceof EmployeeMutationError && err.code === code,
      );
    });
  }
});
