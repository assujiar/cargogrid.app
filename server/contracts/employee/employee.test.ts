import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseEmployeeProfile,
  parseEmployeeOwnProfile,
  parseEmployeeMutationResult,
  parseEmployeeListRow,
  parseMyTeamEmployeeRow,
  parseEmployeeExportRow,
  parseEmployeeEmergencyContact,
  parseEmployeeLifecycleEvent,
  parseEmployeeDuplicateCandidate,
  parseEmployeeDuplicateSearchRow,
  parseEmployeeChangeRequest,
  CreateEmployeeDraftInputSchema,
  RequestEmployeeChangeInputSchema,
  TransferEmployeeInputSchema,
} from "./employee.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const MASTER_RECORD_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";

describe("parseEmployeeProfile", () => {
  test("maps snake_case columns, defaults absent nullable fields to null", () => {
    const row = {
      master_record_id: MASTER_RECORD_ID,
      employee_number: "EMP-2026-000001",
      tenant_id: TENANT_ID,
      user_id: null,
      full_name: "Budi Santoso",
      employment_type: "full_time",
      lifecycle_status: "draft",
      intake_source: "hr_created",
      work_email: "budi@example.test",
      work_phone: null,
      personal_email: null,
      personal_phone: null,
      national_id_number: null,
      date_of_birth: null,
      gender: null,
      personal_address_street: null,
      personal_address_city: null,
      personal_address_province: null,
      personal_address_postal_code: null,
      personal_address_country: null,
      hire_date: null,
      probation_end_date: null,
      employment_end_date: null,
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
      created_at: "2026-08-09T00:00:00.000Z",
      updated_at: "2026-08-09T00:00:00.000Z",
      personal_data_masked: true,
    };
    const parsed = parseEmployeeProfile(row);
    assert.equal(parsed.masterRecordId, MASTER_RECORD_ID);
    assert.equal(parsed.employeeNumber, "EMP-2026-000001");
    assert.equal(parsed.fullName, "Budi Santoso");
    assert.equal(parsed.userId, null);
    assert.equal(parsed.personalDataMasked, true);
  });

  test("carries unmasked personal fields through when the RPC provided them", () => {
    const row = {
      master_record_id: MASTER_RECORD_ID,
      employee_number: "EMP-2026-000002",
      tenant_id: TENANT_ID,
      user_id: ACTOR_ID,
      full_name: "Siti Rahayu",
      employment_type: "contract",
      lifecycle_status: "active",
      intake_source: "hr_created",
      work_email: null,
      work_phone: null,
      personal_email: "siti@personal.test",
      personal_phone: "+62-811-1",
      national_id_number: "3201-XXXX",
      date_of_birth: "1990-01-01",
      gender: "female",
      personal_address_street: "Jl. Merdeka 1",
      personal_address_city: "Jakarta",
      personal_address_province: null,
      personal_address_postal_code: null,
      personal_address_country: "Indonesia",
      hire_date: "2026-01-01",
      probation_end_date: null,
      employment_end_date: null,
      company_org_unit_id: null,
      branch_org_unit_id: null,
      department_org_unit_id: null,
      position_title: "Analyst",
      manager_employee_id: null,
      revision_reason: null,
      suspend_reason: null,
      terminate_reason: null,
      archive_reason: null,
      leave_reason: null,
      record_version: 2,
      created_at: "2026-08-09T00:00:00.000Z",
      updated_at: "2026-08-09T00:00:00.000Z",
      personal_data_masked: false,
    };
    const parsed = parseEmployeeProfile(row);
    assert.equal(parsed.personalEmail, "siti@personal.test");
    assert.equal(parsed.nationalIdNumber, "3201-XXXX");
    assert.equal(parsed.personalDataMasked, false);
  });
});

describe("parseEmployeeOwnProfile", () => {
  test("maps the raw app.get_my_employee_profile row shape (no personal_data_masked column)", () => {
    const row = {
      master_record_id: MASTER_RECORD_ID,
      employee_number: "EMP-2026-000003",
      tenant_id: TENANT_ID,
      user_id: ACTOR_ID,
      full_name: "Own Profile Person",
      employment_type: "full_time",
      lifecycle_status: "active",
      intake_source: "hr_created",
      work_email: null,
      work_phone: null,
      personal_email: "own@personal.test",
      personal_phone: null,
      national_id_number: null,
      date_of_birth: null,
      gender: null,
      personal_address_street: null,
      personal_address_city: null,
      personal_address_province: null,
      personal_address_postal_code: null,
      personal_address_country: null,
      hire_date: null,
      probation_end_date: null,
      employment_end_date: null,
      company_org_unit_id: null,
      branch_org_unit_id: null,
      department_org_unit_id: null,
      position_title: null,
      manager_employee_id: null,
      record_version: 1,
      created_at: "2026-08-09T00:00:00.000Z",
      updated_at: "2026-08-09T00:00:00.000Z",
    };
    const parsed = parseEmployeeOwnProfile(row);
    assert.equal(parsed.personalEmail, "own@personal.test");
    assert.equal(parsed.userId, ACTOR_ID);
  });
});

describe("parseEmployeeMutationResult / parseEmployeeListRow / parseMyTeamEmployeeRow / parseEmployeeExportRow", () => {
  test("parseEmployeeMutationResult maps the raw app.employees lifecycle-RPC row", () => {
    const parsed = parseEmployeeMutationResult({
      master_record_id: MASTER_RECORD_ID,
      tenant_id: TENANT_ID,
      user_id: null,
      full_name: "Mutation Result Person",
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
      created_at: "2026-08-09T00:00:00.000Z",
      updated_at: "2026-08-09T00:00:00.000Z",
    });
    assert.equal(parsed.fullName, "Mutation Result Person");
    assert.equal(parsed.lifecycleStatus, "draft");
  });

  test("parseEmployeeListRow carries zero PII columns by construction (no personal_email field read)", () => {
    const parsed = parseEmployeeListRow({
      master_record_id: MASTER_RECORD_ID,
      employee_number: "EMP-2026-000004",
      full_name: "List Row Person",
      employment_type: "full_time",
      lifecycle_status: "active",
      department_org_unit_id: null,
      position_title: null,
      hire_date: null,
      record_version: 1,
      created_at: "2026-08-09T00:00:00.000Z",
      updated_at: "2026-08-09T00:00:00.000Z",
    });
    assert.equal(parsed.employeeNumber, "EMP-2026-000004");
    assert.deepEqual(Object.keys(parsed).includes("personalEmail" as never), false);
  });

  test("parseMyTeamEmployeeRow", () => {
    const parsed = parseMyTeamEmployeeRow({
      master_record_id: MASTER_RECORD_ID,
      employee_number: "EMP-2026-000005",
      full_name: "Team Row Person",
      employment_type: "full_time",
      lifecycle_status: "active",
      position_title: "Analyst",
      hire_date: "2026-01-01",
    });
    assert.equal(parsed.positionTitle, "Analyst");
  });

  test("parseEmployeeExportRow", () => {
    const parsed = parseEmployeeExportRow({
      employee_number: "EMP-2026-000006",
      full_name: "Export Row Person",
      employment_type: "contract",
      lifecycle_status: "active",
      hire_date: null,
      department_org_unit_id: null,
      position_title: null,
    });
    assert.equal(parsed.employmentType, "contract");
  });
});

describe("parseEmployeeEmergencyContact / parseEmployeeLifecycleEvent / parseEmployeeDuplicateCandidate / parseEmployeeDuplicateSearchRow / parseEmployeeChangeRequest", () => {
  test("parseEmployeeEmergencyContact treats masked phone/email as null, not an error", () => {
    const parsed = parseEmployeeEmergencyContact({
      id: MASTER_RECORD_ID,
      master_record_id: MASTER_RECORD_ID,
      name: "Emergency Contact",
      relationship: "Sibling",
      phone: null,
      email: null,
      is_primary: true,
      record_version: 1,
      created_at: "2026-08-09T00:00:00.000Z",
    });
    assert.equal(parsed.phone, null);
    assert.equal(parsed.name, "Emergency Contact");
  });

  test("parseEmployeeLifecycleEvent defaults metadata to an empty object when absent", () => {
    const parsed = parseEmployeeLifecycleEvent({
      id: MASTER_RECORD_ID,
      master_record_id: MASTER_RECORD_ID,
      from_status: "draft",
      to_status: "submitted",
      reason: null,
      metadata: undefined,
      actor_label: "staff",
      occurred_at: "2026-08-09T00:00:00.000Z",
    });
    assert.deepEqual(parsed.metadata, {});
  });

  test("parseEmployeeDuplicateCandidate", () => {
    const parsed = parseEmployeeDuplicateCandidate({
      id: MASTER_RECORD_ID,
      source_master_record_id: MASTER_RECORD_ID,
      candidate_master_record_id: ACTOR_ID,
      similarity_basis: "manual HR review match",
      similarity_score: "1.0",
      decision: "pending",
      decided_by: null,
      decided_at: null,
      decided_reason: null,
      record_version: 1,
      created_at: "2026-08-09T00:00:00.000Z",
    });
    assert.equal(parsed.decision, "pending");
    assert.equal(parsed.similarityScore, 1);
  });

  test("parseEmployeeDuplicateSearchRow", () => {
    const parsed = parseEmployeeDuplicateSearchRow({
      master_record_id: MASTER_RECORD_ID,
      employee_number: "EMP-2026-000007",
      full_name: "Search Row Person",
      similarity_score: "0.42",
      match_basis: "full_name trigram similarity",
    });
    assert.equal(parsed.matchBasis, "full_name trigram similarity");
  });

  test("parseEmployeeChangeRequest", () => {
    const parsed = parseEmployeeChangeRequest({
      id: MASTER_RECORD_ID,
      master_record_id: MASTER_RECORD_ID,
      requested_by_user_id: ACTOR_ID,
      field_key: "personal_email",
      current_value_snapshot: "old@x.test",
      requested_value: "new@x.test",
      reason: null,
      status: "pending",
      decided_by: null,
      decided_at: null,
      decided_reason: null,
      record_version: 1,
      created_at: "2026-08-09T00:00:00.000Z",
    });
    assert.equal(parsed.fieldKey, "personal_email");
    assert.equal(parsed.status, "pending");
  });

  test("parseEmployeeChangeRequest -- masked row (batch 291-293 Tier C fix, ISS-2026-092/099): app.get_employee_change_requests nulls current_value_snapshot/requested_value/reason/decided_reason for a caller who is neither self nor HRS:View personal data", () => {
    const parsed = parseEmployeeChangeRequest({
      id: MASTER_RECORD_ID,
      master_record_id: MASTER_RECORD_ID,
      requested_by_user_id: ACTOR_ID,
      field_key: "personal_email",
      current_value_snapshot: null,
      requested_value: null,
      reason: null,
      status: "pending",
      decided_by: null,
      decided_at: null,
      decided_reason: null,
      record_version: 1,
      created_at: "2026-08-09T00:00:00.000Z",
    });
    assert.equal(parsed.currentValueSnapshot, null);
    assert.equal(parsed.requestedValue, null);
    assert.equal(parsed.fieldKey, "personal_email");
    assert.equal(parsed.status, "pending");
  });
});

describe("mutation input schemas", () => {
  test("CreateEmployeeDraftInputSchema rejects an empty fullName", () => {
    assert.throws(() =>
      CreateEmployeeDraftInputSchema.parse({
        tenantId: TENANT_ID,
        fullName: "",
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
    );
  });

  test("RequestEmployeeChangeInputSchema rejects a fieldKey outside the fixed allow-list", () => {
    assert.throws(() =>
      RequestEmployeeChangeInputSchema.parse({
        masterRecordId: MASTER_RECORD_ID,
        fieldKey: "national_id_number",
        requestedValue: "1234",
        reason: null,
        actorAuthUserId: ACTOR_ID,
      }),
    );
  });

  test("RequestEmployeeChangeInputSchema accepts an allow-listed fieldKey and carries no actorLabel field", () => {
    const parsed = RequestEmployeeChangeInputSchema.parse({
      masterRecordId: MASTER_RECORD_ID,
      fieldKey: "personal_phone",
      requestedValue: "+62-811-1",
      reason: "updated number",
      actorAuthUserId: ACTOR_ID,
    });
    assert.equal(parsed.fieldKey, "personal_phone");
    assert.deepEqual("actorLabel" in parsed, false);
  });

  test("TransferEmployeeInputSchema accepts null org unit/manager for a full clear-out transfer", () => {
    const parsed = TransferEmployeeInputSchema.parse({
      masterRecordId: MASTER_RECORD_ID,
      expectedVersion: 1,
      companyOrgUnitId: null,
      branchOrgUnitId: null,
      departmentOrgUnitId: null,
      positionTitle: null,
      managerEmployeeId: null,
      reason: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(parsed.companyOrgUnitId, null);
  });
});
