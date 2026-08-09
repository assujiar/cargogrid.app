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
  terminateEmployee,
  transferEmployee,
  addEmployeeEmergencyContact,
  requestEmployeeChange,
  decideEmployeeChangeRequest,
  validateEmployeeImportRow,
  commitEmployeeImportJob,
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
